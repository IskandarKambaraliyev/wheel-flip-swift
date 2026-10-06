import Foundation
import Observation

/// Settings and live status shared by the menu, the Settings window and the app delegate.
@Observable @MainActor
final class AppState {
    static let shared = AppState()

    private enum Key {
        static let enabled = "wf.enabled"
        static let invertVertical = "wf.invertVertical"
        static let invertHorizontal = "wf.invertHorizontal"
        static let linear = "wf.linear"
        static let linesPerNotch = "wf.linesPerNotch"
        static let detection = "wf.detection"
        static let showMenuBarIcon = "wf.showMenuBarIcon"
    }

    static let linesPerNotchRange = 1...10

    // MARK: Persisted settings

    var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled); pushConfig() } }
    var invertVertical: Bool { didSet { defaults.set(invertVertical, forKey: Key.invertVertical); pushConfig() } }
    var invertHorizontal: Bool { didSet { defaults.set(invertHorizontal, forKey: Key.invertHorizontal); pushConfig() } }
    var linear: Bool { didSet { defaults.set(linear, forKey: Key.linear); pushConfig() } }
    var linesPerNotch: Int { didSet { defaults.set(linesPerNotch, forKey: Key.linesPerNotch); pushConfig() } }
    var detection: Detection { didSet { defaults.set(detection.rawValue, forKey: Key.detection); pushConfig() } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }

    // MARK: Status (not persisted)

    var isTrusted = false
    var tapRunning = false
    var tapError: String?
    var systemNatural = true
    var sample = InspectorSample()
    var inspecting = false {
        didSet {
            guard inspecting != oldValue else { return }
            pushConfig()
            updateInspectorTimer()
        }
    }

    /// Backed by `SMAppService`, not by storage, so it is registered with the observation
    /// registrar by hand to keep the toggle in sync with the real login item status.
    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return LoginItem.isEnabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) { LoginItem.set(newValue) }
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var inspectorTimer: Timer?

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.invertVertical: true,
            Key.invertHorizontal: false,
            Key.linear: false,
            Key.linesPerNotch: 3,
            Key.detection: Detection.standard.rawValue,
            Key.showMenuBarIcon: true,
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        invertVertical = defaults.bool(forKey: Key.invertVertical)
        invertHorizontal = defaults.bool(forKey: Key.invertHorizontal)
        linear = defaults.bool(forKey: Key.linear)
        linesPerNotch = Self.clampLines(defaults.integer(forKey: Key.linesPerNotch))
        detection = Detection(rawValue: defaults.integer(forKey: Key.detection)) ?? .standard
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
    }

    private static func clampLines(_ value: Int) -> Int {
        min(max(value, linesPerNotchRange.lowerBound), linesPerNotchRange.upperBound)
    }

    /// Copies the engine-relevant settings to the tap thread.
    func pushConfig() {
        ScrollEngine.shared.update(EngineConfig(enabled: enabled,
                                                invertVertical: invertVertical,
                                                invertHorizontal: invertHorizontal,
                                                linear: linear,
                                                linesPerNotch: Int64(Self.clampLines(linesPerNotch)),
                                                detection: detection,
                                                inspect: inspecting))
    }

    /// Re-reads state owned by the system: scroll direction and login item status.
    func refreshSystemStatus() {
        let natural = SystemScrollSetting.isNatural
        if natural != systemNatural { systemNatural = natural }
        withMutation(keyPath: \.launchAtLogin) {}
    }

    // MARK: Inspector

    /// The timer exists only while the inspector is expanded.
    private func updateInspectorTimer() {
        inspectorTimer?.invalidate()
        inspectorTimer = nil
        guard inspecting else { return }

        ScrollEngine.shared.resetSample()
        sample = InspectorSample()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullSample() }
        }
        // Common modes, so the readout keeps updating while the Settings window itself scrolls.
        RunLoop.main.add(timer, forMode: .common)
        inspectorTimer = timer
    }

    private func pullSample() {
        let latest = ScrollEngine.shared.latestSample()
        if latest != sample { sample = latest }
    }
}
