import AppKit
import CloudKit
import ClipboardCore
import Observation
import Security

/// What Settings shows about iCloud sync.
@MainActor
@Observable
final class CloudSyncStatus {
    enum State: Equatable {
        case off
        case unavailable(String)
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    var state: State = .off
}

/// Syncs the history to the user's private CloudKit database with `CKSyncEngine`, one record per item.
/// Pinned items and history then come back after a reinstall and appear on other Macs.
///
/// Requires the app to be signed with the iCloud entitlement (see `scripts/build-signed.sh`).
actor CloudSync: CKSyncEngineDelegate {
    static let containerID = "iCloud.com.chiranjeebhub.clipstack"
    private static let zoneID = CKRecordZone.ID(zoneName: "History", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "ClipItem"
    /// CloudKit records hold at most 1 MB of fields (assets aside); larger text isn't synced.
    private static let maxFieldBytes = 900_000

    private let store: HistoryStore
    private let status: CloudSyncStatus
    private let imagesDirectory: URL
    private let stateURL: URL
    private let systemFieldsURL: URL

    private var engine: CKSyncEngine?
    /// Each item's last known server record metadata (change tag etc.), so saves don't conflict.
    private var systemFields: [String: Data] = [:]
    private var lastFetch = Date.distantPast
    /// Changes made before the engine is running (it starts asynchronously at launch).
    private var bufferedSaves = Set<ClipItem.ID>()
    private var bufferedDeletes = Set<ClipItem.ID>()

    init(store: HistoryStore, status: CloudSyncStatus, directory: URL, imagesDirectory: URL) {
        self.store = store
        self.status = status
        self.imagesDirectory = imagesDirectory
        stateURL = directory.appendingPathComponent("cloudkit-state.json")
        systemFieldsURL = directory.appendingPathComponent("cloudkit-records.plist")
    }

    /// True when this build carries the iCloud entitlement. Ad-hoc builds don't, and touching
    /// CloudKit without it crashes, so sync stays off for them.
    nonisolated static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
    }

    // MARK: - Lifecycle

    func start() async {
        guard engine == nil else { return }
        guard Self.isEntitled else {
            await setStatus(.unavailable("This build isn’t signed for iCloud. Build it with scripts/build-signed.sh."))
            return
        }
        let container = CKContainer(identifier: Self.containerID)
        do {
            switch try await container.accountStatus() {
            case .available:
                break
            case .noAccount:
                await setStatus(.unavailable("Sign in to iCloud in System Settings to sync."))
                return
            case .restricted, .temporarilyUnavailable, .couldNotDetermine:
                await setStatus(.unavailable("iCloud isn’t available right now."))
                return
            @unknown default:
                await setStatus(.unavailable("iCloud isn’t available right now."))
                return
            }
        } catch {
            await setStatus(.failed(error.localizedDescription))
            return
        }

        let savedState = loadState()
        systemFields = loadSystemFields()
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: savedState,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        if savedState == nil {
            // First sync on this Mac: create the zone and upload what's already here.
            // Everything already in iCloud is fetched automatically.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            await uploadAll()
        }
        enqueue(saved: Array(bufferedSaves), deleted: Array(bufferedDeletes))
        bufferedSaves = []
        bufferedDeletes = []
        await setStatus(.syncing)
        await fetchNow()
    }

    /// Turns sync off and forgets this Mac's sync state. The history itself stays, here and in iCloud.
    func stop() async {
        engine = nil
        systemFields = [:]
        bufferedSaves = []
        bufferedDeletes = []
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: systemFieldsURL)
        await setStatus(.off)
    }

    /// Queues local changes for upload; the engine sends them shortly after.
    func enqueue(saved: [ClipItem.ID], deleted: [ClipItem.ID]) {
        guard let engine else {
            bufferedSaves.formUnion(saved)
            bufferedSaves.subtract(deleted)
            bufferedDeletes.formUnion(deleted)
            return
        }
        var changes = saved.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: $0)) }
        changes += deleted.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID(for: $0)) }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    /// Fetches now unless it fetched in the last minute. Called when the panel opens,
    /// as a backstop for a missed push notification.
    func fetchIfStale() async {
        guard Date().timeIntervalSince(lastFetch) > 60 else { return }
        await fetchNow()
    }

    func syncNow() async {
        guard let engine else { return }
        await setStatus(.syncing)
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            lastFetch = Date()
            await setStatus(.upToDate(Date()))
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func fetchNow() async {
        guard let engine else { return }
        lastFetch = Date()
        do {
            try await engine.fetchChanges()
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func uploadAll() async {
        let ids = await MainActor.run { store.items.map(\.id) }
        enqueue(saved: ids, deleted: [])
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                // The zone was removed, e.g. from iCloud settings. Keep the history on this Mac.
                systemFields = [:]
                saveSystemFields()
            }

        case .fetchedRecordZoneChanges(let changes):
            await applyFetched(changes)

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent, engine: syncEngine)

        case .willFetchChanges, .willSendChanges:
            await setStatus(.syncing)

        case .didFetchChanges, .didSendChanges:
            if syncEngine.state.pendingRecordZoneChanges.isEmpty {
                await setStatus(.upToDate(Date()))
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.record(for: recordID)
        }
    }

    // MARK: - Events

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) async {
        switch change.changeType {
        case .signIn:
            await uploadAll()
        case .signOut, .switchAccounts:
            // Don't mix one account's history into another's: start over with the new account.
            await stop()
            await start()
        @unknown default:
            break
        }
    }

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        var items: [ClipItem] = []
        for modification in changes.modifications {
            let record = modification.record
            guard record.recordType == Self.recordType else { continue }
            rememberSystemFields(of: record)
            if let item = item(from: record) { items.append(item) }
        }
        var deleted: [ClipItem.ID] = []
        for deletion in changes.deletions {
            systemFields[deletion.recordID.recordName] = nil
            if let id = UUID(uuidString: deletion.recordID.recordName) { deleted.append(id) }
        }
        saveSystemFields()
        guard !items.isEmpty || !deleted.isEmpty else { return }
        let store = self.store
        let fetchedItems = items, fetchedDeletions = deleted
        await MainActor.run { store.applyRemote(fetchedItems, deletedIDs: fetchedDeletions) }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async {
        for record in sent.savedRecords {
            rememberSystemFields(of: record)
        }
        for id in sent.deletedRecordIDs {
            systemFields[id.recordName] = nil
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        var newerOnServer: [ClipItem] = []

        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Another Mac saved this item since we last saw it. Keep whichever is newer.
                guard let serverRecord = failure.error.serverRecord else { continue }
                rememberSystemFields(of: serverRecord)
                let serverModified = serverRecord["modifiedAt"] as? Date ?? .distantPast
                let localModified = failure.record["modifiedAt"] as? Date ?? .distantPast
                if serverModified >= localModified {
                    if let item = item(from: serverRecord) { newerOnServer.append(item) }
                } else {
                    retry.append(.saveRecord(recordID))
                }
            case .zoneNotFound, .userDeletedZone:
                needsZone = true
                systemFields[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // Deleted on the server since we last saw it; save it as a new record.
                systemFields[recordID.recordName] = nil
                retry.append(.saveRecord(recordID))
            default:
                // Network and rate-limit errors are retried by the engine itself.
                break
            }
        }
        saveSystemFields()

        if needsZone {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        if !retry.isEmpty {
            engine.state.add(pendingRecordZoneChanges: retry)
        }
        if !newerOnServer.isEmpty {
            let store = self.store
            let serverItems = newerOnServer
            await MainActor.run { store.applyRemote(serverItems, deletedIDs: []) }
        }
    }

    // MARK: - Records

    private func recordID(for id: ClipItem.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: Self.zoneID)
    }

    /// Builds the record to upload. Returning nil drops the change (the item no longer exists, or is too big).
    private func record(for recordID: CKRecord.ID) async -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        let store = self.store
        guard let item = await MainActor.run(body: { store.item(id: id) }) else { return nil }

        let record = restoredRecord(for: recordID) ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record["kind"] = item.kind.rawValue
        record["text"] = item.text
        let textBytes = item.text?.utf8.count ?? 0
        guard textBytes <= Self.maxFieldBytes else { return nil }
        if let rtf = item.rtf, textBytes + rtf.count <= Self.maxFieldBytes {
            record["rtf"] = rtf
        } else {
            record["rtf"] = nil
        }
        record["imageFile"] = item.imageFile
        record["imageWidth"] = item.imageWidth
        record["imageHeight"] = item.imageHeight
        if let name = item.imageFile {
            record["image"] = CKAsset(fileURL: imagesDirectory.appendingPathComponent(name))
        } else {
            record["image"] = nil
        }
        record["filePaths"] = item.fileURLs?.map(\.path)
        record["sourceBundleID"] = item.sourceBundleID
        record["sourceAppName"] = item.sourceAppName
        record["createdAt"] = item.createdAt
        record["modifiedAt"] = item.lastModified
        record["isPinned"] = item.isPinned ? 1 : 0
        record["contentHash"] = item.contentHash
        return record
    }

    private func item(from record: CKRecord) -> ClipItem? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let kindName = record["kind"] as? String, let kind = ClipKind(rawValue: kindName),
              let createdAt = record["createdAt"] as? Date,
              let contentHash = record["contentHash"] as? String else { return nil }

        var imageFile = record["imageFile"] as? String
        if let name = imageFile {
            let destination = imagesDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                if let asset = record["image"] as? CKAsset, let source = asset.fileURL {
                    try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
                    if (try? FileManager.default.copyItem(at: source, to: destination)) == nil { imageFile = nil }
                } else {
                    imageFile = nil
                }
            }
        }
        if kind == .image && imageFile == nil { return nil }

        return ClipItem(
            id: id,
            kind: kind,
            text: record["text"] as? String,
            rtf: record["rtf"] as? Data,
            imageFile: imageFile,
            imageWidth: record["imageWidth"] as? Int,
            imageHeight: record["imageHeight"] as? Int,
            fileURLs: (record["filePaths"] as? [String])?.map { URL(fileURLWithPath: $0) },
            sourceBundleID: record["sourceBundleID"] as? String,
            sourceAppName: record["sourceAppName"] as? String,
            createdAt: createdAt,
            modifiedAt: record["modifiedAt"] as? Date,
            isPinned: (record["isPinned"] as? Int ?? 0) != 0,
            contentHash: contentHash
        )
    }

    // MARK: - Persistence of sync bookkeeping

    private func rememberSystemFields(of record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        systemFields[record.recordID.recordName] = archiver.encodedData
    }

    private func restoredRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let data = systemFields[recordID.recordName],
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard engine != nil, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func loadSystemFields() -> [String: Data] {
        guard let data = try? Data(contentsOf: systemFieldsURL) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private func saveSystemFields() {
        guard let data = try? PropertyListEncoder().encode(systemFields) else { return }
        try? data.write(to: systemFieldsURL, options: .atomic)
    }

    private func setStatus(_ state: CloudSyncStatus.State) async {
        let status = self.status
        await MainActor.run { status.state = state }
    }
}
