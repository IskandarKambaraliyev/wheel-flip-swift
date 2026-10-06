import AppKit
import SwiftUI

/// Hosts `SettingsView` in an AppKit-owned window.
///
/// Change from the spec (§8.5/§8.6), which used a SwiftUI `Settings` scene opened with
/// `NSApp.sendAction(Selector(("showSettingsWindow:")))`: macOS 14+ rejects that selector
/// ("Please use SettingsLink…"), and `SettingsLink` / `openSettings` only work from a live
/// SwiftUI view, which does not exist while the menu bar icon is hidden. Owning the window
/// lets the app delegate open Settings at launch and on reopen in every state.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        AppState.shared.refreshSystemStatus()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // An agent app launched at login may not be allowed to activate; still surface the window.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView().environment(AppState.shared))
        let window = SettingsWindow(contentViewController: host)
        window.title = "WheelFlip Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: SettingsView.width, height: SettingsView.minHeight))
        window.center()
        window.setFrameAutosaveName("WheelFlipSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Collapsing the inspector stops its timer and the capture on the tap thread.
        AppState.shared.inspecting = false
        // Drop the SwiftUI hierarchy; an idle WheelFlip keeps no window around.
        window = nil
    }
}

private final class SettingsWindow: NSWindow {
    /// An agent app without window scenes gets no File menu, so nothing else provides ⌘W.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
