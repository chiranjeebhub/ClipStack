import Foundation
import Security

/// Mirrors preferences through iCloud key-value storage, so settings and the shortcut follow the
/// user to a reinstall or another Mac. Machine-specific state (launch at login, Accessibility,
/// pause, onboarding, the sync switch itself) stays local.
@MainActor
final class SettingsSync {
    static let syncedKeys = [
        PrefKey.showMenuBarIcon, PrefKey.pasteDirectly, PrefKey.alwaysPlainText, PrefKey.panelPosition,
        PrefKey.retentionDays, PrefKey.maxItems, PrefKey.ignoreConcealed, PrefKey.ignoreTransient,
        PrefKey.ignoredApps, PrefKey.hotKeyCode, PrefKey.hotKeyModifiers,
    ]

    /// True when this build carries the key-value store entitlement; ad-hoc builds don't.
    nonisolated static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) != nil
    }

    private let defaults = UserDefaults.standard
    private var observer: NSObjectProtocol?
    private var isEnabled = false

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled, Self.isEntitled else { return }
        isEnabled = enabled
        if enabled {
            let store = NSUbiquitousKeyValueStore.default
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
            ) { [weak self] note in
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                MainActor.assumeIsolated { self?.pull(keys: keys ?? Self.syncedKeys) }
            }
            store.synchronize()
            // Settings already in iCloud (a reinstall or another Mac) win over this Mac's defaults.
            if Self.syncedKeys.contains(where: { store.object(forKey: $0) != nil }) {
                pull(keys: Self.syncedKeys)
            }
            push()
        } else if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Uploads local values that differ from iCloud. Called whenever local preferences change.
    /// Only values the user actually set are sent, never registered defaults, so a fresh install
    /// can't overwrite settings in iCloud before they've downloaded.
    func push() {
        guard isEnabled, let bundleID = Bundle.main.bundleIdentifier else { return }
        let saved = defaults.persistentDomain(forName: bundleID) ?? [:]
        let store = NSUbiquitousKeyValueStore.default
        for key in Self.syncedKeys {
            guard let value = saved[key] else { continue }
            if !Self.equal(store.object(forKey: key), value) { store.set(value, forKey: key) }
        }
    }

    private func pull(keys: [String]) {
        let store = NSUbiquitousKeyValueStore.default
        for key in keys where Self.syncedKeys.contains(key) {
            guard let value = store.object(forKey: key) else { continue }
            if !Self.equal(defaults.object(forKey: key), value) { defaults.set(value, forKey: key) }
        }
    }

    private static func equal(_ lhs: Any?, _ rhs: Any) -> Bool {
        guard let lhs else { return false }
        return (lhs as AnyObject).isEqual(rhs)
    }
}
