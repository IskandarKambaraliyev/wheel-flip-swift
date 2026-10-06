import SwiftUI

@main
struct WheelFlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    // No SwiftUI `Settings` scene: the Settings window is owned by SettingsWindowController so
    // it can be opened from AppKit code as well (see the note there).
    var body: some Scene {
        MenuBarExtra(isInserted: $state.showMenuBarIcon) {
            MenuView().environment(state)
        } label: {
            Image(nsImage: state.enabled && state.tapRunning ? MenuBarIcon.active : MenuBarIcon.inactive)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Change from the spec (§8.6), which dimmed the icon with `.opacity(0.45)`: SwiftUI passes a
/// MenuBarExtra label's image straight to the status item and drops view modifiers, so the
/// opacity never showed. The dimmed state is baked into its own template image instead.
private enum MenuBarIcon {
    static let active = make(alpha: 1)
    static let inactive = make(alpha: 0.45)

    /// Both states are drawn the same way: a symbol image and a drawn image give the status
    /// item slightly different widths, which would make it shift whenever the state changes.
    private static func make(alpha: CGFloat) -> NSImage {
        let symbol = NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil) ?? NSImage()
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WheelFlip"
        return image
    }
}
