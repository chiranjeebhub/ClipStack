import AppKit
import ClipboardCore
import Observation

/// Owns the long-lived services and wires them together.
@MainActor
@Observable
final class AppEnvironment {
    let store: HistoryStore
    @ObservationIgnored let monitor: PasteboardMonitor
    @ObservationIgnored let pasteService: PasteService
    let syncStatus = CloudSyncStatus()
    @ObservationIgnored let cloudSync: CloudSync
    @ObservationIgnored private let settingsSync = SettingsSync()
    @ObservationIgnored private(set) lazy var panel = QuickPanelController(environment: self)
    @ObservationIgnored private lazy var settingsWindow = SettingsWindowController(environment: self)
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var registeredCombo: KeyCombo?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var syncEnabled = false
    @ObservationIgnored private var syncTimer: Timer?

    /// Mirrors the "Pause Recording" preference so menus update immediately.
    var isPaused: Bool = Preferences.isPaused {
        didSet { Preferences.isPaused = isPaused }
    }

    init() {
        Preferences.migrateLegacyDefaults()
        Preferences.registerDefaults()
        ReviewPrompt.recordLaunch()
        HistoryPersistence.migrateLegacyDirectory()
        if DemoData.isEnabled { DemoData.resetDirectory() }
        let directory = DemoData.isEnabled ? DemoData.directory : HistoryPersistence.defaultDirectory()
        store = HistoryStore(persistence: HistoryPersistence(directory: directory))
        if DemoData.isEnabled { DemoData.seed(store) }
        monitor = PasteboardMonitor(store: store)
        pasteService = PasteService(store: store, monitor: monitor)
        cloudSync = CloudSync(
            store: store, status: syncStatus,
            directory: directory, imagesDirectory: directory.appendingPathComponent("images", isDirectory: true)
        )
        store.onChange = { [weak self] saved, deleted in
            guard let self, self.syncEnabled else { return }
            let sync = self.cloudSync
            Task { await sync.enqueue(saved: saved, deleted: deleted) }
        }
    }

    func start() {
        applyPreferences()
        // The screenshot demo shows sample items only, so nothing copied meanwhile is recorded.
        if !DemoData.isEnabled { monitor.start() }
        // Backstop for missed push notifications from CloudKit.
        let syncTimer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFromCloud() }
        }
        syncTimer.tolerance = 60
        RunLoop.main.add(syncTimer, forMode: .common)
        self.syncTimer = syncTimer
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    private func applyPreferences() {
        if store.retention != Preferences.retention { store.retention = Preferences.retention }
        if store.maxItems != Preferences.maxItems { store.maxItems = Preferences.maxItems }
        if isPaused != Preferences.isPaused { isPaused = Preferences.isPaused }
        let wantsSync = Preferences.iCloudSync && !DemoData.isEnabled
        if syncEnabled != wantsSync {
            syncEnabled = wantsSync
            let sync = cloudSync
            if syncEnabled {
                Task { await sync.start() }
            } else {
                Task { await sync.stop() }
            }
            settingsSync.setEnabled(syncEnabled)
        }
        if !DemoData.isEnabled { settingsSync.push() }
        let combo = Preferences.hotKey
        if combo != registeredCombo {
            hotKey = nil
            hotKey = HotKey(combo: combo) { [weak self] in self?.panel.toggle() }
            registeredCombo = combo
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// Picks up changes from other Macs if it hasn't checked in the last minute.
    func refreshFromCloud() {
        guard syncEnabled else { return }
        let sync = cloudSync
        Task { await sync.fetchIfStale() }
    }

    func syncNow() {
        let sync = cloudSync
        Task { await sync.syncNow() }
    }

    /// Temporarily releases the global shortcut, so the shortcut recorder can capture it.
    func suspendHotKey(_ suspended: Bool) {
        if suspended {
            hotKey = nil
            registeredCombo = nil
        } else {
            applyPreferences()
        }
    }

    func paste(_ item: ClipItem, plainText: Bool = false) {
        pasteService.paste(item, plainText: plainText, into: NSWorkspace.shared.frontmostApplication)
    }

    func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All items except pinned ones will be removed. This can’t be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }
}
