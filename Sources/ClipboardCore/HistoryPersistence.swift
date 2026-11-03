import Foundation

/// Stores the history as JSON plus one PNG per image item, inside a single folder.
public final class HistoryPersistence: @unchecked Sendable {
    public let directory: URL
    private let queue = DispatchQueue(label: "clipboard.persistence")

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    /// `~/Library/Application Support/Clipstack`, inside the app's container when sandboxed.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clipstack", isDirectory: true)
    }

    /// Moves history saved while the app was called "Clipboard" to the current folder, once.
    /// Sync bookkeeping from then is dropped: it belonged to the old iCloud container.
    public static func migrateLegacyDirectory() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = base.appendingPathComponent("Clipboard", isDirectory: true)
        let current = defaultDirectory()
        guard fm.fileExists(atPath: legacy.appendingPathComponent("history.json").path),
              !fm.fileExists(atPath: current.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: current)
        } catch {
            return
        }
        for file in ["cloudkit-state.json", "cloudkit-records.plist"] {
            try? fm.removeItem(at: current.appendingPathComponent(file))
        }
    }

    var historyURL: URL { directory.appendingPathComponent("history.json") }
    var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }

    public func imageURL(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    /// Reads the saved history. An entry that can't be read (say, one written by a newer version)
    /// is skipped instead of failing the whole file. Whenever anything is skipped, the file is first
    /// copied aside, because the next save replaces it and would otherwise lose that history for good.
    public func load() -> [ClipItem] {
        guard let data = try? Data(contentsOf: historyURL), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try? decoder.decode([LenientItem].self, from: data)
        let items = entries?.compactMap(\.item) ?? []
        if items.count != entries?.count {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = directory.appendingPathComponent("history-unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: historyURL, to: backup)
        }
        return items
    }

    /// Decodes one history entry, or nil when it can't be read.
    private struct LenientItem: Decodable {
        let item: ClipItem?
        init(from decoder: Decoder) throws {
            item = try? ClipItem(from: decoder)
        }
    }

    public func save(_ items: [ClipItem]) {
        queue.async { [historyURL] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(items) else { return }
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    /// Writes PNG data and returns the file name to keep on the item.
    public func storeImage(_ png: Data) -> String? {
        let name = UUID().uuidString + ".png"
        do {
            try png.write(to: imageURL(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    public func deleteImage(named name: String) {
        queue.async { [imagesDirectory] in
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    /// Bytes used by the history file and stored images.
    public func diskUsage() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        let files = [historyURL] + ((try? fm.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)) ?? [])
        for url in files {
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    /// Waits for pending writes; used by tests and before quitting.
    public func flush() {
        queue.sync {}
    }
}
