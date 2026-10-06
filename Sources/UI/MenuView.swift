import SwiftUI

/// Content of the menu bar item. Rendered as a native NSMenu (`.menu` style).
struct MenuView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Toggle("Enabled", isOn: $state.enabled)
            .keyboardShortcut("e")

        Divider()

        Toggle("Invert vertical", isOn: $state.invertVertical)
        Toggle("Invert horizontal", isOn: $state.invertHorizontal)
        Toggle("Linear scrolling", isOn: $state.linear)

        Divider()

        if !state.isTrusted {
            Button {
                Permissions.openAccessibilitySettings()
            } label: {
                Label("Grant Accessibility access…", systemImage: "exclamationmark.triangle")
            }
        }
        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")
        Button("Quit WheelFlip") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
