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
    @ObservationIgnored private(set) lazy var panel = QuickPanelController(environment: self)
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var registeredCombo: KeyCombo?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    /// Mirrors the "Pause Recording" preference so menus update immediately.
    var isPaused: Bool = Preferences.isPaused {
        didSet { Preferences.isPaused = isPaused }
    }

    init() {
        Preferences.registerDefaults()
        store = HistoryStore(persistence: HistoryPersistence(directory: HistoryPersistence.defaultDirectory()))
        monitor = PasteboardMonitor(store: store)
        pasteService = PasteService(store: store, monitor: monitor)
    }

    func start() {
        applyPreferences()
        monitor.start()
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
        let combo = Preferences.hotKey
        if combo != registeredCombo {
            hotKey = nil
            hotKey = HotKey(combo: combo) { [weak self] in self?.panel.toggle() }
            registeredCombo = combo
        }
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
