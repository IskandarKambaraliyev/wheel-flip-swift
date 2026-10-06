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
