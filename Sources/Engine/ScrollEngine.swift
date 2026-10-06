import CoreGraphics
import Foundation
import os

struct InspectorSample: Equatable {
    var continuous: Int64 = 0, phase: Int64 = 0, momentum: Int64 = 0
    var line: Int64 = 0, point: Int64 = 0
    var wasMouse = false
}

/// Owns the event tap and its thread. All public methods are called from the main thread.
final class ScrollEngine {
    static let shared = ScrollEngine()

    private let lock = OSAllocatedUnfairLock(initialState: EngineConfig())
    private let sampleLock = OSAllocatedUnfairLock(initialState: InspectorSample())
    fileprivate var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    var isRunning: Bool { tap != nil }

    func update(_ config: EngineConfig) { lock.withLock { $0 = config } }
    fileprivate func config() -> EngineConfig { lock.withLock { $0 } }

    func latestSample() -> InspectorSample { sampleLock.withLock { $0 } }
    fileprivate func record(_ s: InspectorSample) { sampleLock.withLock { $0 = s } }
    /// Clears the inspector sample so a new inspection session does not show a stale event.
    func resetSample() { record(InspectorSample()) }

    /// Returns false if the tap could not be created (not trusted / stale TCC).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: wheelFlipTapCallback,
                                           userInfo: nil) else { return false }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let t = Thread { [weak self] in
            self?.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        t.name = "WheelFlip.EventTap"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
        return true
    }

    /// Re-arms a tap the system may have disabled (e.g. across sleep/wake).
    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil; runLoop = nil; thread = nil
    }
}

// C-compatible callback: no captures, no allocations on the hot path.
private func wheelFlipTapCallback(proxy: CGEventTapProxy,
                                  type: CGEventType,
                                  event: CGEvent,
                                  userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let engine = ScrollEngine.shared

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = engine.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

    let cfg = engine.config()
    guard cfg.enabled,
          event.getIntegerValueField(.eventSourceUserData) != kWheelFlipMarker
    else { return Unmanaged.passUnretained(event) }

    let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
    let phase      = event.getIntegerValueField(.scrollWheelEventScrollPhase)
    let momentum   = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
    let isMouse = ScrollTransform.isMouseWheel(continuous: continuous, phase: phase,
                                               momentum: momentum, detection: cfg.detection)

    if cfg.inspect {
        engine.record(InspectorSample(continuous: continuous, phase: phase, momentum: momentum,
                                      line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                                      point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                                      wasMouse: isMouse))
    }
    guard isMouse else { return Unmanaged.passUnretained(event) }

    apply(event, invert: cfg.invertVertical, cfg,
          .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
    apply(event, invert: cfg.invertHorizontal, cfg,
          .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)

    return Unmanaged.passUnretained(event)
}

// Write order matters: setting the line delta makes CoreGraphics recompute the fixed-point
// and point deltas, so those two are written afterwards.
@inline(__always)
private func apply(_ e: CGEvent, invert: Bool, _ cfg: EngineConfig,
                   _ lineF: CGEventField, _ fixedF: CGEventField, _ pointF: CGEventField) {
    guard invert || cfg.linear else { return }
    let d = AxisDeltas(line: e.getIntegerValueField(lineF),
                       fixed: e.getDoubleValueField(fixedF),
                       point: e.getIntegerValueField(pointF))
    if d.line == 0 && d.fixed == 0 && d.point == 0 { return }
    let o = ScrollTransform.transform(d, invert: invert, linear: cfg.linear, lines: cfg.linesPerNotch)
    e.setIntegerValueField(lineF, value: o.line)
    e.setDoubleValueField(fixedF, value: o.fixed)
    e.setIntegerValueField(pointF, value: o.point)
}
