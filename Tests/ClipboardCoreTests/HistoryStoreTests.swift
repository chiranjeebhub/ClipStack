import XCTest
@testable import ClipboardCore

final class HistoryStoreTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(persistence: HistoryPersistence? = nil) -> HistoryStore {
        HistoryStore(persistence: persistence, now: { [unowned self] in self.now })
    }

    private func text(_ value: String, ago seconds: TimeInterval = 0, app: String? = nil) -> ClipItem {
        ClipItem(kind: ContentClassifier.classify(value), text: value, sourceAppName: app,
                 createdAt: now.addingTimeInterval(-seconds), contentHash: "text:" + value)
    }

    func testNewestFirst() {
        let store = makeStore()
        store.add(text("one"))
        store.add(text("two"))
        XCTAssertEqual(store.items.map(\.text), ["two", "one"])
    }

    func testDuplicateMovesToTopAndKeepsPin() {
        let store = makeStore()
        store.add(text("one"))
        store.togglePin(id: store.items[0].id)
        let originalID = store.items[0].id
        store.add(text("two"))
        store.add(text("one"))
        XCTAssertEqual(store.items.map(\.text), ["one", "two"])
        XCTAssertEqual(store.items[0].id, originalID)
        XCTAssertTrue(store.items[0].isPinned)
    }

    func testMaxItemsKeepsPinned() {
        let store = makeStore()
        store.maxItems = 2
        store.add(text("pinned"))
        store.togglePin(id: store.items[0].id)
        store.add(text("a"))
        store.add(text("b"))
        store.add(text("c"))
        XCTAssertEqual(store.items.map(\.text), ["c", "b", "pinned"])
    }

    func testRetentionDropsOldUnpinned() {
        let store = makeStore()
        store.retention = .forever
        store.add(text("old", ago: 10 * 86_400))
        store.add(text("old pinned", ago: 10 * 86_400))
        store.togglePin(id: store.items[0].id)
        store.add(text("new"))
        store.retention = .week
        XCTAssertEqual(store.items.map(\.text), ["new", "old pinned"])
    }

    func testFilterAndSearch() {
        let store = makeStore()
        store.add(text("hello world", app: "Notes"))
        store.add(text("https://example.com", app: "Safari"))
        store.add(text("#FF0000", app: "Figma"))
        XCTAssertEqual(store.filtered(.links).map(\.text), ["https://example.com"])
        XCTAssertEqual(store.filtered(.text).map(\.text), ["#FF0000", "hello world"])
        XCTAssertEqual(store.filtered(query: "WORLD").map(\.text), ["hello world"])
        XCTAssertEqual(store.filtered(query: "safari").map(\.text), ["https://example.com"])
        XCTAssertEqual(store.filtered(query: "hello notes").count, 1)
        XCTAssertEqual(store.filtered(pinnedOnly: true).count, 0)
        store.togglePin(id: store.items.first { $0.kind == .link }!.id)
        XCTAssertEqual(store.filtered(.links, pinnedOnly: true).map(\.text), ["https://example.com"])
        XCTAssertEqual(store.filtered(.text, pinnedOnly: true).count, 0)
    }

    func testClearKeepsPinned() {
        let store = makeStore()
        store.add(text("keep"))
        store.togglePin(id: store.items[0].id)
        store.add(text("drop"))
        store.clearUnpinned()
        XCTAssertEqual(store.items.map(\.text), ["keep"])
    }

    func testEditReclassifies() {
        let store = makeStore()
        store.add(text("draft"))
        store.updateText(id: store.items[0].id, text: "https://example.com")
        XCTAssertEqual(store.items[0].kind, .link)
    }

    func testPersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = HistoryPersistence(directory: directory)
        let store = makeStore(persistence: persistence)
        store.add(text("saved", app: "Notes"))
        store.togglePin(id: store.items[0].id)
        persistence.flush()

        let reloaded = makeStore(persistence: HistoryPersistence(directory: directory))
        XCTAssertEqual(reloaded.items.map(\.text), ["saved"])
        XCTAssertEqual(reloaded.items.first?.sourceAppName, "Notes")
        XCTAssertEqual(reloaded.items.first?.isPinned, true)
    }

    func testSections() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let items = [text("now"), text("yesterday", ago: 86_400), text("last week", ago: 7 * 86_400)]
        let sections = HistorySection.group(items, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Earlier"])
    }

    func testChangesAreReported() {
        let store = makeStore()
        var saved: [UUID] = [], deleted: [UUID] = []
        store.onChange = { saved += $0; deleted += $1 }
        store.add(text("one"))
        let id = store.items[0].id
        store.togglePin(id: id)
        store.delete(id: id)
        XCTAssertEqual(saved, [id, id])
        XCTAssertEqual(deleted, [id])
    }

    func testPruneReportsDeletions() {
        let store = makeStore()
        store.maxItems = 1
        var deleted: [UUID] = []
        store.onChange = { deleted += $1 }
        store.add(text("old"))
        let oldID = store.items[0].id
        store.add(text("new"))
        XCTAssertEqual(deleted, [oldID])
    }

    func testRemoteNewerVersionWins() {
        let store = makeStore()
        store.add(text("note"))
        var remote = store.items[0]
        remote.isPinned = true
        remote.modifiedAt = now.addingTimeInterval(60)
        store.applyRemote([remote], deletedIDs: [])
        XCTAssertTrue(store.items[0].isPinned)

        var stale = remote
        stale.isPinned = false
        stale.modifiedAt = now.addingTimeInterval(-60)
        store.applyRemote([stale], deletedIDs: [])
        XCTAssertTrue(store.items[0].isPinned)
    }

    func testRemoteInsertsSortedAndDeletes() {
        let store = makeStore()
        store.add(text("local"))
        let localID = store.items[0].id
        let older = text("from other mac", ago: 300)
        store.applyRemote([older], deletedIDs: [])
        XCTAssertEqual(store.items.map(\.text), ["local", "from other mac"])

        var reported: [UUID] = []
        store.onChange = { _, deleted in reported += deleted }
        store.applyRemote([], deletedIDs: [localID])
        XCTAssertEqual(store.items.map(\.text), ["from other mac"])
        XCTAssertTrue(reported.isEmpty, "remote deletions aren't echoed back")
    }

    func testRemoteDuplicateKeepsNewestCopy() {
        let store = makeStore()
        store.add(text("same", ago: 100))
        let localID = store.items[0].id
        var deleted: [UUID] = []
        store.onChange = { deleted += $1 }

        let newer = text("same")
        store.applyRemote([newer], deletedIDs: [])
        XCTAssertEqual(store.items.map(\.id), [newer.id])
        XCTAssertEqual(deleted, [localID])

        let older = text("same", ago: 500)
        store.applyRemote([older], deletedIDs: [])
        XCTAssertEqual(store.items.map(\.id), [newer.id])
        XCTAssertEqual(deleted, [localID, older.id])
    }

    func testDecodesHistoryWithoutModifiedAt() throws {
        let json = #"[{"id":"5D7A7C55-6B39-4C64-9F0B-2F7F5C1A0001","kind":"text","text":"hi","createdAt":"2026-10-20T08:00:00Z","isPinned":false,"contentHash":"text:hi"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([ClipItem].self, from: Data(json.utf8))
        XCTAssertNil(items[0].modifiedAt)
        XCTAssertEqual(items[0].lastModified, items[0].createdAt)
    }

    func testTitles() {
        XCTAssertEqual(text("  first line\nsecond").title, "first line")
        let image = ClipItem(kind: .image, imageWidth: 1440, imageHeight: 900, contentHash: "i")
        XCTAssertEqual(image.title, "Image · 1440 × 900")
        let files = ClipItem(kind: .file, fileURLs: [URL(fileURLWithPath: "/a/one.pdf"), URL(fileURLWithPath: "/a/two.pdf")], contentHash: "f")
        XCTAssertEqual(files.title, "one.pdf and 1 more")
    }
}
