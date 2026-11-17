import AppKit
import Carbon.HIToolbox
import ClipboardCore
import Observation

@MainActor
@Observable
final class QuickPanelModel {
    let store: HistoryStore
    /// What the search field shows. It changes on every keystroke; `query`, which filters the list,
    /// follows it a moment later, so a typed letter appears before the list is searched and redrawn.
    var searchText = "" { didSet { scheduleQuery() } }
    private(set) var query = "" { didSet { selectFirstIfNeeded() } }
    @ObservationIgnored private var pendingQuery: Task<Void, Never>?
    var filter: HistoryFilter = .all { didSet { selectFirstIfNeeded() } }
    var pinnedOnly = false { didSet { selectFirstIfNeeded() } }
    var selectedID: ClipItem.ID? {
        // Selecting another item ends editing; otherwise the keyboard stays in editing mode for an
        // item that is no longer shown, and arrows and Return do nothing until Escape.
        didSet { if editingID != nil && editingID != selectedID { editingID = nil } }
    }
    var editingID: ClipItem.ID?
    /// The image whose text is being read for Copy Text, so its button can show progress.
    var readingTextID: ClipItem.ID?
    /// Bumped each time the panel opens so relative times ("2 min ago") refresh.
    private(set) var now = Date()
    /// Bumped each time the panel opens so the view can refocus the search field.
    private(set) var focusToken = 0
    /// The last item pasted from the panel, and the newest item at that moment. The panel reopens on
    /// that item, unless something new has been copied since; then it starts at the newest item.
    @ObservationIgnored private var lastPastedID: ClipItem.ID?
    @ObservationIgnored private var newestIDAtPaste: ClipItem.ID?

    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    @ObservationIgnored var onCopy: ((ClipItem) -> Void)?
    @ObservationIgnored var onSaveImage: ((ClipItem) -> Void)?
    @ObservationIgnored var onCopyText: ((ClipItem) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?

    init(store: HistoryStore) {
        self.store = store
    }

    /// What the list shows, worked out once per change to the history, search or filters. Every
    /// row asks for its ⌘1–9 badge, and each of those asks used to filter the whole history again,
    /// so a single keystroke searched it dozens of times.
    private struct Snapshot {
        var revision: Int
        var query: String
        var filter: HistoryFilter
        var pinnedOnly: Bool
        var now: Date
        var items: [ClipItem]
        var quickIndices: [ClipItem.ID: Int]
        var sections: [HistorySection]?
    }
    @ObservationIgnored private var snapshot: Snapshot?

    private var currentSnapshot: Snapshot {
        // Reading these registers the observation that redraws the panel when any of them change.
        let revision = store.revision, query = self.query, filter = self.filter, pinnedOnly = self.pinnedOnly, now = self.now
        if let snapshot, snapshot.revision == revision, snapshot.query == query, snapshot.filter == filter,
           snapshot.pinnedOnly == pinnedOnly, snapshot.now == now {
            return snapshot
        }
        let items = store.filtered(filter, pinnedOnly: pinnedOnly, query: query)
        var quickIndices: [ClipItem.ID: Int] = [:]
        for (offset, item) in items.prefix(9).enumerated() { quickIndices[item.id] = offset + 1 }
        let fresh = Snapshot(
            revision: revision, query: query, filter: filter, pinnedOnly: pinnedOnly, now: now,
            items: items, quickIndices: quickIndices
        )
        snapshot = fresh
        return fresh
    }

    var visibleItems: [ClipItem] { currentSnapshot.items }

    var sections: [HistorySection] {
        var current = currentSnapshot
        if let sections = current.sections { return sections }
        let sections = HistorySection.group(current.items, now: now)
        current.sections = sections
        snapshot = current
        return sections
    }

    var selectedItem: ClipItem? { store.item(id: selectedID) }

    /// Position of an item among the visible ones, for its ⌘1–9 badge.
    func quickIndex(of item: ClipItem) -> Int? {
        currentSnapshot.quickIndices[item.id]
    }

    private func scheduleQuery() {
        pendingQuery?.cancel()
        guard searchText != query else { return }
        // Clearing the field shows everything again at once.
        guard !searchText.isEmpty else { return applySearch() }
        pendingQuery = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.applySearch()
        }
    }

    /// Filters the list by what's in the search field now, without waiting.
    private func applySearch() {
        pendingQuery?.cancel()
        pendingQuery = nil
        if query != searchText { query = searchText }
    }

    func prepareForShowing() {
        searchText = ""
        applySearch()
        filter = .all
        pinnedOnly = false
        editingID = nil
        now = Date()
        let items = visibleItems
        if let lastPastedID, items.first?.id == newestIDAtPaste, items.contains(where: { $0.id == lastPastedID }) {
            selectedID = lastPastedID
        } else {
            selectedID = items.first?.id
        }
        focusToken += 1
    }

    private func selectFirstIfNeeded() {
        let items = visibleItems
        if !items.contains(where: { $0.id == selectedID }) {
            selectedID = items.first?.id
        }
    }

    func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    func paste(_ item: ClipItem? = nil, plainText: Bool = false) {
        guard let item = item ?? selectedItem else { return }
        lastPastedID = item.id
        newestIDAtPaste = store.items.first?.id
        onPaste?(item, plainText)
    }

    func copy(_ item: ClipItem) {
        onCopy?(item)
    }

    func saveImage(_ item: ClipItem) {
        onSaveImage?(item)
    }

    /// Copies the text recognized in an image item.
    func copyText(from item: ClipItem) {
        guard item.recognizedText != "" else { return }
        onCopyText?(item)
    }

    func togglePin(_ item: ClipItem? = nil) {
        guard let item = item ?? selectedItem else { return }
        store.togglePin(id: item.id)
    }

    func delete(_ item: ClipItem? = nil) {
        guard let item = item ?? selectedItem else { return }
        let items = visibleItems
        let index = items.firstIndex { $0.id == item.id } ?? 0
        store.delete(id: item.id)
        let remaining = visibleItems
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    /// Steps through the filter bar with ←/→ or Tab: All, Text, Links, Images, Files, then the pin
    /// button (pinned items of every type), wrapping at both ends. Landing on a type turns pinned-only off.
    func cycleFilter(forward: Bool) {
        let stops: [HistoryFilter?] = HistoryFilter.allCases + [nil]
        let current = pinnedOnly && filter == .all ? stops.count - 1 : (stops.firstIndex(of: filter) ?? 0)
        let next = stops[(current + (forward ? 1 : stops.count - 1)) % stops.count]
        pinnedOnly = next == nil
        filter = next ?? .all
    }

    private static let listKeys: Set<Int> = [
        kVK_DownArrow, kVK_UpArrow, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_LeftArrow, kVK_RightArrow,
    ]

    /// Returns true when the key was handled and should not reach the search field.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if editingID != nil {
            if Int(event.keyCode) == kVK_Escape {
                editingID = nil
                return true
            }
            return false
        }

        // A key that acts on the list must see the search just typed, not the one before it.
        if flags.contains(.command) || Self.listKeys.contains(Int(event.keyCode)) { applySearch() }

        switch Int(event.keyCode) {
        case kVK_DownArrow:
            moveSelection(by: 1)
            return true
        case kVK_UpArrow:
            moveSelection(by: -1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            paste(plainText: flags.contains(.option))
            return true
        case kVK_Escape:
            onClose?()
            return true
        case kVK_Tab:
            cycleFilter(forward: !flags.contains(.shift))
            return true
        // ←/→ switch filters while the search field is empty; once there's text they move the caret.
        case kVK_LeftArrow where searchText.isEmpty, kVK_RightArrow where searchText.isEmpty:
            cycleFilter(forward: Int(event.keyCode) == kVK_RightArrow)
            return true
        case kVK_Delete where flags.contains(.command):
            delete()
            return true
        default:
            break
        }

        guard flags.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if let digit = Int(characters), (1...9).contains(digit) {
            let items = visibleItems
            if digit <= items.count { paste(items[digit - 1], plainText: flags.contains(.option)) }
            return true
        }
        switch characters {
        case "p" where flags.contains(.shift):
            pinnedOnly.toggle()
            return true
        case "p":
            togglePin()
            return true
        case "c" where searchText.isEmpty:
            if let item = selectedItem { copy(item) }
            return true
        case "e":
            if let item = selectedItem, [.text, .code, .link, .color].contains(item.kind) { editingID = item.id }
            return true
        default:
            return false
        }
    }
}
