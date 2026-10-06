import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when the app is only hosting the unit tests; it must not prompt or install a tap then.
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Consecutive failed tap starts tolerated before reporting a stale TCC entry. Trust can
    /// be reported a moment before the tap can actually be created.
    private static let failedStartsBeforeError = 3
    private static let staleTrustMessage = "Remove WheelFlip from Accessibility, then add it again."

    private let state = AppState.shared
    private var trustTimer: Timer?
    private var failedStarts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        state.pushConfig()
        state.refreshSystemStatus()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(didBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        syncEngine()
        if !state.isTrusted {
            Permissions.prompt()
            SettingsWindowController.shared.show()
        }
    }

    /// Re-opening the app (Finder, Spotlight, `open -a`) is the way back to Settings when the
    /// menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScrollEngine.shared.stop()
    }

    // MARK: Engine lifecycle

    /// Brings the tap in line with the current Accessibility trust. While the tap is not
    /// running this is re-run every second; once it runs, no timer is left.
    @objc private func syncEngine() {
        let trusted = Permissions.isTrusted
        if trusted != state.isTrusted { state.isTrusted = trusted }

        guard trusted else {
            if ScrollEngine.shared.isRunning { ScrollEngine.shared.stop() }
            failedStarts = 0
            setStatus(running: false, error: nil)
            setPolling(true)
            return
        }

        if ScrollEngine.shared.start() {
            failedStarts = 0
            setStatus(running: true, error: nil)
            setPolling(false)
        } else {
            // Trusted but no tap: a stale TCC entry, typically after re-signing.
            failedStarts += 1
            let stale = failedStarts >= Self.failedStartsBeforeError
            let firstReport = stale && state.tapError == nil
            setStatus(running: false, error: stale ? Self.staleTrustMessage : nil)
            if firstReport { SettingsWindowController.shared.show() }
            setPolling(true)
        }
    }

    private func setStatus(running: Bool, error: String?) {
        if running != state.tapRunning { state.tapRunning = running }
        if error != state.tapError { state.tapError = error }
    }

    private func setPolling(_ on: Bool) {
        guard on != (trustTimer != nil) else { return }
        if on {
            let timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(syncEngine),
                                             userInfo: nil, repeats: true)
            timer.tolerance = 0.2
            trustTimer = timer
        } else {
            trustTimer?.invalidate()
            trustTimer = nil
        }
    }

    @objc private func didWake() {
        syncEngine()
        ScrollEngine.shared.reenable()
    }

    @objc private func didBecomeActive() {
        syncEngine()
        state.refreshSystemStatus()
    }
}
