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
    /// Reports every change made on this Mac (not those applied from sync), so sync can upload it:
    /// the IDs of items added or modified, and the IDs of items removed.
    @ObservationIgnored public var onChange: ((_ saved: [ClipItem.ID], _ deleted: [ClipItem.ID]) -> Void)?
    @ObservationIgnored private let now: () -> Date

    public init(persistence: HistoryPersistence? = nil, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
        self.items = persistence?.load() ?? []
        _ = prune()
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
        item.modifiedAt = now()
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            let existing = items.remove(at: index)
            item.id = existing.id
            item.isPinned = existing.isPinned
            if let old = existing.imageFile, old != item.imageFile {
                persistence?.deleteImage(named: old)
            }
        }
        items.insert(item, at: 0)
        pruneAndSave(saved: [item.id])
    }

    /// Moves an item to the top, as if it had just been copied.
    public func touch(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.createdAt = now()
        item.modifiedAt = now()
        items.insert(item, at: 0)
        save(saved: [id])
    }

    public func togglePin(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        items[index].modifiedAt = now()
        pruneAndSave(saved: [id])
    }

    public func updateText(id: ClipItem.ID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        items[index].rtf = nil
        items[index].kind = ContentClassifier.classify(text)
        items[index].contentHash = "text:" + text
        items[index].modifiedAt = now()
        save(saved: [id])
    }

    public func delete(id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        cleanUp([removed])
        save(deleted: [id])
    }

    /// Removes every unpinned item.
    public func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        cleanUp(removed)
        save(deleted: removed.map(\.id))
    }

    /// Applies changes fetched from another Mac. For an item known on both sides the most
    /// recently modified version wins, and the same content copied on two Macs collapses into
    /// the most recent copy (the other copy is reported as deleted, so every Mac drops it).
    /// Images must already be in the image folder under the items' `imageFile` names.
    public func applyRemote(_ remoteItems: [ClipItem], deletedIDs: [ClipItem.ID]) {
        var deletedDuplicates: [ClipItem.ID] = []

        let deleted = Set(deletedIDs)
        let removed = items.filter { deleted.contains($0.id) }
        items.removeAll { deleted.contains($0.id) }
        cleanUp(removed)

        for remote in remoteItems where !deleted.contains(remote.id) {
            if let index = items.firstIndex(where: { $0.id == remote.id }) {
                let local = items[index]
                guard remote.lastModified >= local.lastModified else { continue }
                if let old = local.imageFile, old != remote.imageFile {
                    persistence?.deleteImage(named: old)
                }
                items[index] = remote
            } else if let index = items.firstIndex(where: { $0.contentHash == remote.contentHash }) {
                let local = items[index]
                if remote.createdAt > local.createdAt {
                    items[index] = remote
                    cleanUp([local], keepingImage: remote.imageFile)
                    deletedDuplicates.append(local.id)
                } else {
                    if let name = remote.imageFile, name != local.imageFile {
                        persistence?.deleteImage(named: name)
                    }
                    deletedDuplicates.append(remote.id)
                }
            } else {
                items.append(remote)
            }
        }

        items.sort { $0.createdAt > $1.createdAt }
        let pruned = prune()
        persistence?.save(items)
        let reported = deletedDuplicates + pruned
        if !reported.isEmpty { onChange?([], reported) }
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

    private func pruneAndSave(saved: [ClipItem.ID] = []) {
        let pruned = prune()
        save(saved: saved.filter { id in !pruned.contains(id) }, deleted: pruned)
    }

    /// Applies the retention period and item limit. Returns the IDs it removed.
    private func prune() -> [ClipItem.ID] {
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
        return removed.map(\.id)
    }

    private func cleanUp(_ removed: [ClipItem], keepingImage kept: String? = nil) {
        for name in removed.compactMap(\.imageFile) where name != kept {
            persistence?.deleteImage(named: name)
        }
    }

    private func save(saved: [ClipItem.ID] = [], deleted: [ClipItem.ID] = []) {
        persistence?.save(items)
        if !saved.isEmpty || !deleted.isEmpty { onChange?(saved, deleted) }
    }
}
