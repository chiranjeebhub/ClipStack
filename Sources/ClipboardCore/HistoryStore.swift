import Foundation
import Observation

@Observable
public final class HistoryStore {
    /// Newest first.
    public private(set) var items: [ClipItem] = []
    /// Maximum number of unpinned items kept.
    public var maxItems: Int = 1000 { didSet { pruneAndSave() } }
    public var retention: Retention = .month { didSet { pruneAndSave() } }

    @ObservationIgnored public let persistence: HistoryPersistence?
    @ObservationIgnored private let now: () -> Date

    public init(persistence: HistoryPersistence? = nil, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
        self.items = persistence?.load() ?? []
        prune()
    }

    public var pinnedCount: Int { items.filter(\.isPinned).count }

    public func item(id: ClipItem.ID?) -> ClipItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    /// Adds a new copy. Copying the same content again moves the existing entry to the top
    /// and keeps its pin, rather than creating a duplicate.
    public func add(_ newItem: ClipItem) {
        var item = newItem
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            let existing = items.remove(at: index)
            item.id = existing.id
            item.isPinned = existing.isPinned
            if let old = existing.imageFile, old != item.imageFile {
                persistence?.deleteImage(named: old)
            }
        }
        items.insert(item, at: 0)
        pruneAndSave()
    }

    /// Moves an item to the top, as if it had just been copied.
    public func touch(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.createdAt = now()
        items.insert(item, at: 0)
        save()
    }

    public func togglePin(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        pruneAndSave()
    }

    public func updateText(id: ClipItem.ID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        items[index].rtf = nil
        items[index].kind = ContentClassifier.classify(text)
        items[index].contentHash = "text:" + text
        save()
    }

    public func delete(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        cleanUp([removed])
        save()
    }

    /// Removes every unpinned item.
    public func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        cleanUp(removed)
        save()
    }

    public func filtered(_ filter: HistoryFilter = .all, query: String = "") -> [ClipItem] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        return items.filter { item in
            guard filter.matches(item) else { return false }
            guard !terms.isEmpty else { return true }
            let haystack = item.searchableText.lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: - Housekeeping

    private func pruneAndSave() {
        prune()
        save()
    }

    private func prune() {
        var removed: [ClipItem] = []
        if retention != .forever {
            let cutoff = now().addingTimeInterval(-Double(retention.rawValue) * 86_400)
            removed += items.filter { !$0.isPinned && $0.createdAt < cutoff }
            items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        }
        var unpinnedSeen = 0
        items.removeAll { item in
            guard !item.isPinned else { return false }
            unpinnedSeen += 1
            if unpinnedSeen > maxItems {
                removed.append(item)
                return true
            }
            return false
        }
        cleanUp(removed)
    }

    private func cleanUp(_ removed: [ClipItem]) {
        for name in removed.compactMap(\.imageFile) {
            persistence?.deleteImage(named: name)
        }
    }

    private func save() {
        persistence?.save(items)
    }
}
