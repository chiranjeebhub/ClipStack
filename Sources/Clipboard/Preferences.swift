import AppKit
import ClipboardCore

/// UserDefaults keys. Views bind to these with `@AppStorage`; services read them through `Preferences`.
enum PrefKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let pasteDirectly = "pasteDirectly"
    static let alwaysPlainText = "alwaysPlainText"
    static let panelPosition = "panelPosition"
    static let retentionDays = "retentionDays"
    static let maxItems = "maxItems"
    static let ignoreConcealed = "ignoreConcealed"
    static let ignoreTransient = "ignoreTransient"
    static let isPaused = "isPaused"
    static let ignoredApps = "ignoredApps"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case center, mouse
    var id: String { rawValue }
    var label: String { self == .center ? "Center of screen" : "Near the pointer" }
}

enum Preferences {
    static let defaultIgnoredApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.showMenuBarIcon: true,
            PrefKey.pasteDirectly: true,
            PrefKey.alwaysPlainText: false,
            PrefKey.panelPosition: PanelPosition.center.rawValue,
            PrefKey.retentionDays: Retention.month.rawValue,
            PrefKey.maxItems: 1000,
            PrefKey.ignoreConcealed: true,
            PrefKey.ignoreTransient: true,
            PrefKey.isPaused: false,
            PrefKey.ignoredApps: defaultIgnoredApps,
            PrefKey.hotKeyCode: Int(KeyCombo.default.keyCode),
            PrefKey.hotKeyModifiers: Int(KeyCombo.default.modifiers.rawValue),
            PrefKey.hasCompletedOnboarding: false,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var pasteDirectly: Bool { defaults.bool(forKey: PrefKey.pasteDirectly) }
    static var alwaysPlainText: Bool { defaults.bool(forKey: PrefKey.alwaysPlainText) }
    static var ignoreConcealed: Bool { defaults.bool(forKey: PrefKey.ignoreConcealed) }
    static var ignoreTransient: Bool { defaults.bool(forKey: PrefKey.ignoreTransient) }
    static var panelPosition: PanelPosition {
        PanelPosition(rawValue: defaults.string(forKey: PrefKey.panelPosition) ?? "") ?? .center
    }
    static var retention: Retention { Retention(rawValue: defaults.integer(forKey: PrefKey.retentionDays)) ?? .month }
    static var maxItems: Int { max(50, defaults.integer(forKey: PrefKey.maxItems)) }

    static var isPaused: Bool {
        get { defaults.bool(forKey: PrefKey.isPaused) }
        set { defaults.set(newValue, forKey: PrefKey.isPaused) }
    }

    static var ignoredApps: [String] {
        get { defaults.stringArray(forKey: PrefKey.ignoredApps) ?? [] }
        set { defaults.set(newValue, forKey: PrefKey.ignoredApps) }
    }

    static var hotKey: KeyCombo {
        get {
            KeyCombo(
                keyCode: UInt32(defaults.integer(forKey: PrefKey.hotKeyCode)),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: PrefKey.hotKeyModifiers)))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: PrefKey.hotKeyCode)
            defaults.set(Int(newValue.modifiers.rawValue), forKey: PrefKey.hotKeyModifiers)
        }
    }
}
