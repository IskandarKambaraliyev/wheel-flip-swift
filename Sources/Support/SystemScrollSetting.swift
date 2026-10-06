import Foundation

/// Read-only view of the system "Natural scrolling" preference. WheelFlip never writes it.
enum SystemScrollSetting {
    /// Missing key ⇒ Natural (the macOS default).
    ///
    /// Read through CFPreferences: `UserDefaults(suiteName: UserDefaults.globalDomain)` returns
    /// nil because the global domain is not a valid suite name.
    static var isNatural: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let value = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                              kCFPreferencesAnyApplication)
        return (value as? Bool) ?? true
    }
}
