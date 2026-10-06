# WheelFlip — Implementation Spec (for Claude Code)

> **Instructions for Claude Code:** Build the macOS app described below from scratch in this repository. Follow the constraints strictly, implement every file listed in §6, make it build with the commands in §10, and verify against the acceptance criteria in §11. Do not add third-party runtime dependencies. If something here turns out to be wrong at build time (API name, signature), fix it in the most native way and leave a short comment explaining the change.

---

## 1. Goal

A tiny native macOS menu bar app that **inverts the scroll direction of physical mouse wheels only**, leaving trackpad (and Magic Mouse) scrolling untouched.

### Background (why this app exists)

macOS has one shared setting for scroll direction: toggling "Natural scrolling" in Mouse settings also changes it for the Trackpad. Most people want **natural** on the trackpad and **traditional** on a wheel mouse. The open-source app UnnaturalScrollWheels (ther0n, GPL-3.0) solves this with an event tap, but it is unsigned/not notarized, has had macOS 26 breakage, and is no longer actively maintained.

WheelFlip is a **clean-room** reimplementation. **Do not copy code from UnnaturalScrollWheels** (GPL-3.0); implement from the description in this spec.

### How it works (one paragraph)

The user keeps the system setting at **Natural** (good for the trackpad). WheelFlip installs a `CGEventTap` on scroll-wheel events, classifies each event as *mouse wheel* or *touch surface* (trackpad / Magic Mouse), and for mouse-wheel events negates the scroll deltas in place. Optionally it also replaces accelerated wheel deltas with a fixed number of lines per notch ("linear scrolling").

---

## 2. Constraints (non-negotiable)

| Constraint | Meaning |
|---|---|
| Fully native | Swift 5 mode, SwiftUI + AppKit + CoreGraphics + ServiceManagement. No Electron/Catalyst/third-party packages. |
| Fully offline | No networking code at all, no update checker, no analytics, no crash reporting. App must work with Wi-Fi off. Do not add the network client entitlement. |
| Small | Target app bundle < 3 MB. `arm64` only. Dead-code stripping on. No asset catalogs except AppIcon. |
| Optimized | Event-tap callback is O(1): no allocations, no `String` work, no logging, no locks held longer than a struct copy. Idle CPU ≈ 0 %. Resident memory target < 30 MB. |
| Mouse only | Trackpad and Magic Mouse scrolling must pass through completely unmodified. |
| Menu bar app | No Dock icon (`LSUIElement = YES`). Controlled from the menu bar. |
| Launch at login | Via `SMAppService.mainApp`. No helper app, no LaunchAgent plist. |
| Platform | macOS 14.0+ deployment target, Apple Silicon (developer machine: M3 Pro). Must work on macOS 15 and macOS 26. |
| Not sandboxed | Active event taps that modify events need Accessibility permission, which is incompatible with the App Sandbox. Hardened Runtime ON. |

### Non-goals

Pointer acceleration settings, button remapping, per-app rules, smooth-scroll animation, keyboard features, Intel builds, App Store distribution. (Per-app exclusions are listed as a future extension in §13 only.)

---

## 3. Identity

| Item | Value |
|---|---|
| App name | WheelFlip |
| Bundle ID | `uz.stiv.wheelflip` |
| Minimum macOS | 14.0 |
| Architectures | arm64 |
| Signing | Apple Development (automatic), Team ID from the developer's account. Ad-hoc signing must NOT be used: TCC (Accessibility) permission is bound to the code signature and would reset on every build. |

---

## 4. Event classification and transformation

### 4.1 Event tap

- Location: `.cghidEventTap` (earliest point, before other apps see the event).
- Placement: `.headInsertEventTap`.
- Options: `.defaultTap` (active filter, can modify events).
- Mask: `scrollWheel` only (`1 << CGEventType.scrollWheel.rawValue`). Also handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` (these arrive regardless of mask) by re-enabling the tap.
- Runs on a **dedicated background thread** with its own `CFRunLoop`, so a busy main thread (SwiftUI) can never cause the system to disable the tap for timeout.

### 4.2 Classifying an event as "mouse wheel"

Read these integer fields:

| Field | Meaning |
|---|---|
| `.scrollWheelEventIsContinuous` | 0 = classic line-based wheel; 1 = pixel/continuous |
| `.scrollWheelEventScrollPhase` | non-zero during a touch gesture (began/changed/ended) |
| `.scrollWheelEventMomentumPhase` | non-zero during inertial scrolling after a flick |

Classification (`Detection.standard`, default):

```
if isContinuous == 0                      → mouse wheel
else if scrollPhase != 0 || momentum != 0 → touch surface (trackpad / Magic Mouse) → pass through
else                                       → mouse wheel (high-resolution / smooth wheels, e.g. Logitech)
```

`Detection.strict` (setting, for troubleshooting): only `isContinuous == 0` counts as a mouse wheel; everything else passes through.

Magic Mouse produces phased events, so it is treated like a trackpad (follows the system Natural setting). This is intentional: the app targets wheel mice.

### 4.3 Ignore our own / synthetic events

Skip any event whose `.eventSourceUserData` equals the app's marker constant `0x57464C50` ("WFLP"). (WheelFlip modifies in place and never posts events in v1, but keep the guard so a future "re-post" mode cannot loop.)

### 4.4 Inverting

Each axis has three delta fields that must be changed together, otherwise some apps (Safari, Chromium, Electron) still scroll the original way:

| Axis | Line delta (Int) | Fixed-point delta (Double) | Point/pixel delta (Int) |
|---|---|---|---|
| Vertical (Axis1) | `.scrollWheelEventDeltaAxis1` | `.scrollWheelEventFixedPtDeltaAxis1` | `.scrollWheelEventPointDeltaAxis1` |
| Horizontal (Axis2) | `.scrollWheelEventDeltaAxis2` | `.scrollWheelEventFixedPtDeltaAxis2` | `.scrollWheelEventPointDeltaAxis2` |

Rule: **read all three first, then write all three** in the order line → fixed-point → point. Setting the line delta can cause CoreGraphics to recompute the others, so the final write order matters.

Shift+wheel on most mice arrives as Axis2 (horizontal); the horizontal setting covers that.

### 4.5 Linear scrolling (optional, off by default)

When enabled, for each mouse-wheel event and each non-zero axis:

```
sign  = signum(lineDelta != 0 ? lineDelta : fixedPtDelta)
lines = settings.linesPerNotch            // 1...10, default 3
line  = sign * lines
fixed = Double(sign * lines)
point = sign * lines * 10                 // ~10 px per line, macOS default scale
```

Apply inversion after this (negate the computed values if the axis is inverted).

---

## 5. UX specification

### 5.1 Menu bar

- Icon: SF Symbol `computermouse` when active, `computermouse` with reduced opacity (or `nosign` overlay via `computermouse.fill` + `.secondary`) when disabled or when permission is missing. Keep it a single `Image`.
- Use `MenuBarExtra` with the **`.menu` style** (native NSMenu, lightest weight).
- Menu items:

```
✓ Enabled                         ⌘E
─────────────────────────────
✓ Invert vertical
  Invert horizontal
  Linear scrolling
─────────────────────────────
⚠ Grant Accessibility access…     (only when not trusted)
Settings…                         ⌘,
Quit WheelFlip                    ⌘Q
```

### 5.2 Settings window (single pane, ~420 × 360 pt, `Form` with `.grouped` style)

Sections:

1. **General**: Enabled; Launch at login; Show menu bar icon.
2. **Mouse wheel**: Invert vertical; Invert horizontal; Linear scrolling + Stepper "Lines per notch" (1–10, disabled unless linear is on).
3. **Detection**: Picker Standard / Strict, with a one-line caption explaining Strict.
4. **Status**: Accessibility permission (Granted / Not granted + "Open Settings" button); current system scroll direction (read-only: "Natural" / "Standard") with a caption: *"Keep system scrolling on Natural for the trackpad; WheelFlip reverses only the mouse wheel."*
5. **Scroll inspector** (DisclosureGroup, collapsed): while expanded, shows the last scroll event's `isContinuous`, `phase`, `momentum`, line/point deltas and the classification ("Mouse wheel → inverted" / "Trackpad → passed through"). Used to diagnose odd mice. Inspector capture is only active while this group is expanded.

### 5.3 Hidden icon behavior

If "Show menu bar icon" is off, the app keeps running. Re-opening the app (Finder, Spotlight, `open -a WheelFlip`) must show the Settings window (implement `applicationShouldHandleReopen` / `applicationDidBecomeActive` handling) so the user can always get back.

### 5.4 First launch / permission flow

1. On launch, check `AXIsProcessTrusted()`.
2. If not trusted: call `AXIsProcessTrustedWithOptions` with the prompt option once, and show the Settings window with the Status section highlighted.
3. Poll `AXIsProcessTrusted()` every 1 s (timer on main thread, invalidated once trusted). As soon as it becomes true, start the event tap without requiring a restart.
4. If the tap fails to be created while trusted (rare, stale TCC entry after re-signing), show: "Remove WheelFlip from Accessibility, then add it again" with an Open Settings button.

Deep link to settings: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

---

## 6. Project layout

Use **XcodeGen** to generate the Xcode project (build-time tool only, not shipped). If `xcodegen` is missing: `brew install xcodegen`.

```
WheelFlip/
├── project.yml
├── Makefile
├── README.md
├── Sources/
│   ├── App/
│   │   ├── WheelFlipApp.swift        # @main, MenuBarExtra + Settings scenes
│   │   ├── AppDelegate.swift         # reopen handling, permission polling, start/stop engine
│   │   ├── AppState.swift            # @Observable settings + status, persistence (UserDefaults)
│   │   └── LoginItem.swift           # SMAppService.mainApp wrapper
│   ├── Engine/
│   │   ├── ScrollEngine.swift        # tap thread, tap lifecycle, config snapshot
│   │   ├── ScrollTransform.swift     # pure functions: classify + transform (unit-testable)
│   │   └── EngineConfig.swift        # small POD struct shared with the tap thread
│   ├── UI/
│   │   ├── MenuView.swift
│   │   ├── SettingsView.swift
│   │   └── InspectorView.swift
│   └── Support/
│       ├── Permissions.swift         # AX trust check, prompt, open settings
│       └── SystemScrollSetting.swift # reads com.apple.swipescrolldirection
├── Resources/
│   ├── Assets.xcassets/AppIcon.appiconset
│   ├── Info.plist
│   └── WheelFlip.entitlements        # empty dict (no sandbox, no network)
└── Tests/
    └── ScrollTransformTests.swift
```

### 6.1 `project.yml`

```yaml
name: WheelFlip
options:
  bundleIdPrefix: uz.stiv
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "5.10"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    ARCHS: arm64
    ONLY_ACTIVE_ARCH: YES
    ENABLE_HARDENED_RUNTIME: YES
    DEAD_CODE_STRIPPING: YES
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: "XXXXXXXXXX"          # ← set your Team ID
  configs:
    Release:
      SWIFT_OPTIMIZATION_LEVEL: "-O"
      SWIFT_COMPILATION_MODE: wholemodule
      STRIP_INSTALLED_PRODUCT: YES
      STRIP_STYLE: all
      DEBUG_INFORMATION_FORMAT: dwarf-with-dsym
targets:
  WheelFlip:
    type: application
    platform: macOS
    sources: [Sources, Resources]
    info:
      path: Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: WheelFlip
        CFBundleShortVersionString: "1.0.0"
        CFBundleVersion: "1"
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "© 2026 Abdulloh"
    entitlements:
      path: Resources/WheelFlip.entitlements
      properties: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: uz.stiv.wheelflip
  WheelFlipTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: WheelFlip
```

### 6.2 `Makefile`

```make
APP=WheelFlip
BUILD=build

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
	  -derivedDataPath $(BUILD) -destination 'platform=macOS,arch=arm64' build

test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -derivedDataPath $(BUILD) \
	  -destination 'platform=macOS,arch=arm64' test

install: build
	rm -rf /Applications/$(APP).app
	cp -R $(BUILD)/Build/Products/Release/$(APP).app /Applications/
	@du -sh /Applications/$(APP).app

reset-permission:
	tccutil reset Accessibility uz.stiv.wheelflip
```

---

## 7. Engine implementation (critical path — implement exactly)

### 7.1 `EngineConfig.swift`

```swift
enum Detection: Int, Codable, CaseIterable { case standard = 0, strict = 1 }

/// Plain value type copied into the tap thread. Keep it POD (no classes, no strings).
struct EngineConfig: Equatable {
    var enabled = true
    var invertVertical = true
    var invertHorizontal = false
    var linear = false
    var linesPerNotch: Int64 = 3
    var detection: Detection = .standard
    var inspect = false
}

let kWheelFlipMarker: Int64 = 0x57464C50   // "WFLP"
```

### 7.2 `ScrollTransform.swift` (pure, unit-tested)

```swift
import CoreGraphics

struct AxisDeltas: Equatable {
    var line: Int64
    var fixed: Double
    var point: Int64
}

enum ScrollTransform {
    @inline(__always)
    static func isMouseWheel(continuous: Int64, phase: Int64, momentum: Int64, detection: Detection) -> Bool {
        if continuous == 0 { return true }
        if detection == .strict { return false }
        return phase == 0 && momentum == 0
    }

    @inline(__always)
    static func transform(_ d: AxisDeltas, invert: Bool, linear: Bool, lines: Int64) -> AxisDeltas {
        var out = d
        if linear {
            let s: Int64 = d.line != 0 ? (d.line > 0 ? 1 : -1)
                         : (d.fixed > 0 ? 1 : (d.fixed < 0 ? -1 : 0))
            if s != 0 {
                out = AxisDeltas(line: s * lines, fixed: Double(s * lines), point: s * lines * 10)
            }
        }
        if invert {
            out = AxisDeltas(line: -out.line, fixed: -out.fixed, point: -out.point)
        }
        return out
    }
}
```

### 7.3 `ScrollEngine.swift`

```swift
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
```

Notes for implementation:
- `OSAllocatedUnfairLock` is macOS 13+, fine for the 14.0 target. The lock only guards a struct copy.
- If Swift complains about passing a top-level function as `CGEventTapCallBack`, wrap it in a non-capturing closure literal; it must stay `@convention(c)`-compatible.
- Never call `print`/`Logger` inside the callback in Release builds.

---

## 8. App layer

### 8.1 `AppState.swift`

- `@Observable @MainActor final class AppState`.
- Persisted properties (UserDefaults, keys prefixed `wf.`): `enabled`, `invertVertical`, `invertHorizontal`, `linear`, `linesPerNotch`, `detection`, `showMenuBarIcon`.
- Non-persisted: `isTrusted`, `tapRunning`, `tapError: String?`, `systemNatural: Bool`, `inspecting: Bool`, `sample: InspectorSample`.
- Every `didSet` of an engine-relevant property calls `pushConfig()` → `ScrollEngine.shared.update(EngineConfig(...))`.
- `launchAtLogin` is computed from `SMAppService.mainApp.status == .enabled`; setter calls `LoginItem.set(_:)`.
- While `inspecting` is true, a 0.25 s main-thread timer copies `ScrollEngine.shared.latestSample()` into `sample`. Timer exists only while inspecting.

### 8.2 `LoginItem.swift`

```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { SMAppService.openSystemSettingsLoginItems() }
    }
}
```

Default: on first launch, do NOT enable launch at login automatically; show the toggle in Settings (one-tap).

### 8.3 `Permissions.swift`

```swift
import ApplicationServices
import AppKit

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
```

### 8.4 `SystemScrollSetting.swift`

Read `com.apple.swipescrolldirection` from the global domain (`UserDefaults(suiteName: UserDefaults.globalDomain)` or `CFPreferencesCopyAppValue(... kCFPreferencesAnyApplication)`). Missing key ⇒ Natural (macOS default). Refresh when Settings opens and on `NSApplication.didBecomeActiveNotification`. Read-only; WheelFlip never writes system preferences.

### 8.5 `AppDelegate.swift`

- `applicationDidFinishLaunching`: load state → push config → if trusted, `ScrollEngine.shared.start()`; else prompt once + open Settings + start 1 s trust-poll timer.
- When polling detects trust: invalidate timer, start engine, update state.
- Observe `NSWorkspace.didWakeNotification`: if trusted and tap not running, restart engine; if running, re-enable tap (`CGEvent.tapEnable`).
- `applicationShouldHandleReopen` → open Settings (works even when the menu bar icon is hidden).
- `applicationWillTerminate` → `ScrollEngine.shared.stop()`.

Opening Settings from AppKit code on macOS 14+: use `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` then `NSApp.activate(ignoringOtherApps: true)`. From SwiftUI menu use `SettingsLink`.

### 8.6 `WheelFlipApp.swift`

```swift
import SwiftUI

@main
struct WheelFlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $state.showMenuBarIcon) {
            MenuView().environment(state)
        } label: {
            Image(systemName: "computermouse")
                .opacity(state.enabled && state.tapRunning ? 1 : 0.45)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView().environment(state)
        }
    }
}
```

(`AppState.shared` is a single instance also used by `AppDelegate`.)

### 8.7 UI rules

- System fonts and controls only; no custom colors except `.secondary` captions and an orange warning for missing permission.
- `MenuView` uses `Toggle` and `Button` items inside the `.menu` style (they render as native menu items with checkmarks).
- Keyboard shortcut ⌘E for Enabled.
- `SettingsView` is a single `Form`, `.formStyle(.grouped)`, fixed width 420.

---

## 9. Performance & size checklist

- Callback path: 3 field reads for classification, up to 6 reads + 6 writes for transformation, one unfair-lock struct copy. Nothing else.
- No timers run in steady state (trust poll stops once trusted; inspector timer only while inspecting).
- No `Combine`, no `NotificationCenter` observers on the hot path.
- Release build: whole-module optimization, stripping, arm64 only.
- Verify with `make install` (prints bundle size) and Activity Monitor (CPU ≈ 0 % idle, ~0.1–0.5 % while scrolling hard).

---

## 10. Build, run, test

```bash
brew install xcodegen          # once
make gen                       # generate WheelFlip.xcodeproj
make test                      # unit tests for ScrollTransform
make install                   # Release build → /Applications/WheelFlip.app
open -a WheelFlip
```

During development, keep the app signed with the same Team ID. If Accessibility permission seems granted but the tap won't start after re-signing: `make reset-permission`, relaunch, grant again.

---

## 11. Acceptance criteria

Unit tests (`Tests/ScrollTransformTests.swift`) must cover:

- [ ] `isMouseWheel`: continuous 0 → true (both detections); continuous 1 + phase 0 + momentum 0 → true (standard), false (strict); any non-zero phase or momentum → false.
- [ ] `transform` invert only: all three deltas negated, zero stays zero.
- [ ] `transform` linear: line 1 → `lines`, line −7 → `-lines`, fixed-only input uses fixed sign, point = line × 10.
- [ ] `transform` linear + invert combined.

Manual tests (system setting: **Natural** ON):

- [ ] Wheel mouse, scroll down → content moves like a traditional mouse (page goes down) in Safari, Chrome, Finder, Xcode, VS Code, Terminal.
- [ ] Trackpad two-finger scroll → natural, unchanged; momentum after flick unchanged.
- [ ] Magic Mouse (if available) → unchanged (natural).
- [ ] Shift+wheel / tilt wheel with "Invert horizontal" on → reversed; off → unchanged.
- [ ] Linear scrolling: fast wheel spin no longer accelerates; each notch moves the same amount.
- [ ] Toggle Enabled off → mouse follows system setting immediately; on → inverted again.
- [ ] Fresh install: permission prompt appears; after granting, works without relaunch.
- [ ] Launch at login: reboot → app running, inversion active, no windows shown.
- [ ] Hide menu bar icon → app still works; `open -a WheelFlip` shows Settings.
- [ ] Sleep/wake → still working.
- [ ] Wi-Fi off → everything works (no network code exists; grep the codebase for `URLSession`, must be zero results).
- [ ] Bundle size < 3 MB; idle CPU ≈ 0 %.

---

## 12. Known pitfalls

| Pitfall | Handling |
|---|---|
| Some smooth-scroll mice or vendor drivers (e.g. Logi Options+) emit continuous events | Standard detection treats phase-less continuous events as mouse; Strict mode exists for edge cases; Inspector shows the raw fields. |
| Vendor driver already inverts the wheel | Tell the user (README) to disable inversion in the vendor app or in WheelFlip, not both. |
| TCC permission stuck after re-signing | Detect "trusted but tapCreate returned nil" and show the remove/re-add instructions; `tccutil reset`. |
| System disables the tap under load | Handled by re-enabling on `.tapDisabledByTimeout` and by running on a dedicated thread. |
| Secure Event Input (password fields) | Does not affect scroll events; no special handling. |
| Future macOS changes field semantics | Inspector + unit-tested transform make regressions quick to diagnose. |

---

## 13. Future extensions (do NOT build in v1)

- Per-app exclusions (check frontmost app's bundle ID; cache it via `NSWorkspace.didActivateApplicationNotification`, never query inside the callback).
- Device-based detection via `IOHIDManager` (would require Input Monitoring permission).
- Scroll speed multiplier separate from linear mode.

---

## 14. README.md (generate)

Short README with: what it does, why (shared Natural setting), install (`make install`), granting Accessibility, recommended setup (system Natural ON + WheelFlip invert vertical ON), troubleshooting (Strict mode, Inspector, `make reset-permission`), and a note that it is a clean-room implementation inspired by UnnaturalScrollWheels.
