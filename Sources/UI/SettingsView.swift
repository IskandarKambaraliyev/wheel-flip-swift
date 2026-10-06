import SwiftUI

struct SettingsView: View {
    static let width: CGFloat = 420
    static let minHeight: CGFloat = 360

    private static let statusID = "status"

    @Environment(AppState.self) private var state

    /// Missing permission or a tap that will not start: the Status section needs the user.
    private var needsAttention: Bool { !state.isTrusted || state.tapError != nil }

    var body: some View {
        @Bindable var state = state

        ScrollViewReader { proxy in
            Form {
                Section {
                    Toggle("Enabled", isOn: $state.enabled)
                    Toggle("Launch at login", isOn: $state.launchAtLogin)
                    Toggle("Show menu bar icon", isOn: $state.showMenuBarIcon)
                } header: {
                    Text("General")
                } footer: {
                    caption("With the icon hidden, open WheelFlip again to get back to this window.")
                }

                Section("Mouse wheel") {
                    Toggle("Invert vertical", isOn: $state.invertVertical)
                    Toggle("Invert horizontal", isOn: $state.invertHorizontal)
                    Toggle("Linear scrolling", isOn: $state.linear)
                    Stepper("Lines per notch: \(state.linesPerNotch)",
                            value: $state.linesPerNotch, in: AppState.linesPerNotchRange)
                        .disabled(!state.linear)
                }

                Section {
                    Picker("Mode", selection: $state.detection) {
                        Text("Standard").tag(Detection.standard)
                        Text("Strict").tag(Detection.strict)
                    }
                } header: {
                    Text("Detection")
                } footer: {
                    caption("Strict reverses only classic notched wheels and leaves smooth-scrolling mice alone.")
                }

                Section {
                    if !state.isTrusted {
                        warning("WheelFlip needs Accessibility access to reverse the mouse wheel.")
                    }
                    if let error = state.tapError {
                        warning(error)
                    }
                    LabeledContent("Accessibility") {
                        Text(state.isTrusted ? "Granted" : "Not granted")
                            .foregroundStyle(state.isTrusted ? Color.secondary : Color.orange)
                        if needsAttention {
                            Button("Open Settings") { Permissions.openAccessibilitySettings() }
                        }
                    }
                    .id(Self.statusID)
                    LabeledContent("System scroll direction", value: state.systemNatural ? "Natural" : "Standard")
                } header: {
                    Text("Status")
                } footer: {
                    caption("Keep system scrolling on Natural for the trackpad; WheelFlip reverses only the mouse wheel.")
                }

                Section {
                    DisclosureGroup("Scroll inspector", isExpanded: $state.inspecting) {
                        InspectorView()
                    }
                }
            }
            .formStyle(.grouped)
            // `.task`, not `.onAppear`: the form has to be laid out before it can be scrolled.
            .task { revealStatus(proxy) }
            .onChange(of: state.tapError) { revealStatus(proxy) }
        }
        .frame(width: Self.width)
        .frame(minHeight: Self.minHeight)
    }

    /// The form is taller than the window, so bring the Status section into view when it
    /// is the thing the user has to act on.
    private func revealStatus(_ proxy: ScrollViewProxy) {
        if needsAttention { proxy.scrollTo(Self.statusID, anchor: .center) }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }
}
