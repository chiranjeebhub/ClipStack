import AppKit
import Carbon.HIToolbox
import ClipboardCore
import Observation

@MainActor
@Observable
final class QuickPanelModel {
    let store: HistoryStore
    var query = "" { didSet { selectFirstIfNeeded() } }
    var filter: HistoryFilter = .all { didSet { selectFirstIfNeeded() } }
    var pinnedOnly = false { didSet { selectFirstIfNeeded() } }
    var selectedID: ClipItem.ID?
    var editingID: ClipItem.ID?
    /// Bumped each time the panel opens so relative times ("2 min ago") refresh.
    private(set) var now = Date()
    /// Bumped each time the panel opens so the view can refocus the search field.
    private(set) var focusToken = 0

    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    @ObservationIgnored var onCopy: ((ClipItem) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?

    init(store: HistoryStore) {
        self.store = store
    }

    var visibleItems: [ClipItem] { store.filtered(filter, pinnedOnly: pinnedOnly, query: query) }
    var sections: [HistorySection] { HistorySection.group(visibleItems, now: now) }
    var selectedItem: ClipItem? { store.item(id: selectedID) }

    /// Position of an item among the visible ones, for its ⌘1–9 badge.
    func quickIndex(of item: ClipItem) -> Int? {
        guard let index = visibleItems.prefix(9).firstIndex(where: { $0.id == item.id }) else { return nil }
        return index + 1
    }

    func prepareForShowing() {
        query = ""
        filter = .all
        pinnedOnly = false
        editingID = nil
        now = Date()
        selectedID = visibleItems.first?.id
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
        onPaste?(item, plainText)
    }

    func copy(_ item: ClipItem) {
        onCopy?(item)
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

    func cycleFilter(forward: Bool) {
        let all = HistoryFilter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }

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
        case kVK_LeftArrow where query.isEmpty, kVK_RightArrow where query.isEmpty:
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
        case "p":
            togglePin()
            return true
        case "c" where query.isEmpty:
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
