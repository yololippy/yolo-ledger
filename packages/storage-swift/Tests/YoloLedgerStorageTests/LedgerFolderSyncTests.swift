import Foundation
import SwiftData
import Testing
import YoloLedgerCore
@testable import YoloLedgerStorage

struct LedgerFolderSyncTests {
    @Test @MainActor func twoStoresExchangeCreateUpdateAndDeletion() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let deviceA = UUID()
        let deviceB = UUID()
        let entryID = UUID()
        let repositoryA = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        let repositoryB = try SwiftDataLedgerRepository(storeURL: fixture.storeBURL)
        let updateStream = repositoryA.updates()
        let updateTask = Task {
            for await _ in updateStream { return true }
            return false
        }

        _ = try await repositoryA.createEntry(syncDraft(amount: 1_234, note: "A 新增"), id: entryID)
        let firstReport = try await repositoryA.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceA)
        #expect(await updateTask.value)
        #expect(firstReport.importedRecordCount == 0)
        #expect(firstReport.exportedRecordCount == LedgerSeedData.books.count + LedgerSeedData.categories.count + 1)

        let importReport = try await repositoryB.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceB)
        #expect(importReport.importedRecordCount == 1)
        #expect(try await repositoryB.fetchEntries().map(\.id) == [entryID])

        _ = try await repositoryB.updateEntry(
            id: entryID,
            draft: syncDraft(amount: 9_876, note: "B 修改")
        )
        _ = try await repositoryB.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceB)
        let updateReport = try await repositoryA.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceA)
        #expect(updateReport.importedRecordCount == 1)
        let updated = try #require(try await repositoryA.fetchEntries().first)
        #expect(updated.amount.minorUnits == 9_876)
        #expect(updated.note == "B 修改")

        try await repositoryB.deleteEntry(id: entryID)
        _ = try await repositoryB.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceB)
        let deletionReport = try await repositoryA.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceA)
        #expect(deletionReport.importedRecordCount == 1)
        #expect(try await repositoryA.fetchEntries().isEmpty)

        let reopenedA = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        #expect(try await reopenedA.fetchEntries().isEmpty)
        let records = try allEntryRecords(at: fixture.storeAURL)
        #expect(records.first { $0.id == entryID }?.deletedAt != nil)
    }

    @Test func offlineAddsFromBothDevicesConverge() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let repositoryA = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        let repositoryB = try SwiftDataLedgerRepository(storeURL: fixture.storeBURL)
        let deviceA = UUID()
        let deviceB = UUID()
        let aID = UUID()
        let bID = UUID()

        _ = try await repositoryA.createEntry(syncDraft(amount: 101, note: "仅 A 离线新增"), id: aID)
        _ = try await repositoryB.createEntry(syncDraft(amount: 202, note: "仅 B 离线新增"), id: bID)

        _ = try await repositoryA.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceA)
        _ = try await repositoryB.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceB)
        _ = try await repositoryA.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceA)

        #expect(Set(try await repositoryA.fetchEntries().map(\.id)) == [aID, bID])
        #expect(Set(try await repositoryB.fetchEntries().map(\.id)) == [aID, bID])
    }

    @Test @MainActor func sameTimeConflictIsDeterministicAndTombstoneWins() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let sourceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let sourceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let deviceC = UUID()
        let deviceD = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000.987_654)
        let tieID = UUID()
        let tombstoneID = UUID()

        try LedgerFolderSnapshotIO.write(
            conflictSnapshot(
                deviceID: sourceA,
                timestamp: timestamp,
                tieID: tieID,
                tieNote: "aaa",
                tombstoneID: tombstoneID,
                tombstoneDate: nil
            ),
            to: fixture.exchangeURL
        )
        try LedgerFolderSnapshotIO.write(
            conflictSnapshot(
                deviceID: sourceB,
                timestamp: timestamp,
                tieID: tieID,
                tieNote: "zzz",
                tombstoneID: tombstoneID,
                tombstoneDate: timestamp
            ),
            to: fixture.exchangeURL
        )

        let repositoryC = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        let repositoryD = try SwiftDataLedgerRepository(storeURL: fixture.storeBURL)
        _ = try await repositoryC.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceC)
        _ = try await repositoryD.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceD)

        let entriesC = try await repositoryC.fetchEntries()
        let entriesD = try await repositoryD.fetchEntries()
        #expect(entriesC == entriesD)
        #expect(entriesC.first { $0.id == tieID }?.note == "zzz")
        #expect(entriesC.allSatisfy { $0.id != tombstoneID })

        let persisted = try allEntryRecords(at: fixture.storeBURL)
        #expect(persisted.first { $0.id == tombstoneID }?.deletedAt == timestamp)
    }

    @Test func subsecondUpdateOrderSurvivesReadableJSONRoundTrip() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let olderDevice = UUID()
        let newerDevice = UUID()
        let entryID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try LedgerFolderSnapshotIO.write(
            singleEntrySnapshot(
                deviceID: olderDevice,
                entryID: entryID,
                note: "zzz older",
                updatedAt: base.addingTimeInterval(0.1)
            ),
            to: fixture.exchangeURL
        )
        try LedgerFolderSnapshotIO.write(
            singleEntrySnapshot(
                deviceID: newerDevice,
                entryID: entryID,
                note: "aaa newer",
                updatedAt: base.addingTimeInterval(0.9)
            ),
            to: fixture.exchangeURL
        )

        let repository = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        _ = try await repository.synchronize(folderURL: fixture.exchangeURL, deviceID: UUID())
        #expect(try await repository.fetchEntries().first { $0.id == entryID }?.note == "aaa newer")

        let json = try String(
            contentsOf: LedgerFolderSnapshotIO.snapshotFileURL(
                in: fixture.exchangeURL,
                deviceID: newerDevice
            ),
            encoding: .utf8
        )
        #expect(json.contains(".900000"))
    }

    @Test func corruptSnapshotDoesNotModifyLocalStoreOrWriteOwnSnapshot() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        let localID = UUID()
        let deviceID = UUID()
        _ = try await repository.createEntry(syncDraft(amount: 303, note: "本地保留"), id: localID)
        let before = try await repository.fetchEntries()

        let corruptID = UUID()
        let corruptURL = LedgerFolderSnapshotIO.snapshotFileURL(
            in: fixture.exchangeURL,
            deviceID: corruptID
        )
        try FileManager.default.createDirectory(
            at: corruptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not-json".utf8).write(to: corruptURL)

        do {
            _ = try await repository.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceID)
            Issue.record("Expected corrupt snapshot to fail")
        } catch let error as LedgerFolderSyncError {
            guard case .invalidSnapshot = error else {
                Issue.record("Unexpected folder sync error: \(error)")
                return
            }
        }
        #expect(try await repository.fetchEntries() == before)
        #expect(!FileManager.default.fileExists(
            atPath: LedgerFolderSnapshotIO.snapshotFileURL(
                in: fixture.exchangeURL,
                deviceID: deviceID
            ).path
        ))
    }

    @Test func unsupportedFormatDoesNotModifyLocalStore() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
        let localID = UUID()
        _ = try await repository.createEntry(syncDraft(amount: 505, note: "版本失败后保留"), id: localID)
        let before = try await repository.fetchEntries()
        let foreignDeviceID = UUID()
        let url = LedgerFolderSnapshotIO.snapshotFileURL(
            in: fixture.exchangeURL,
            deviceID: foreignDeviceID
        )
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {
          "formatVersion": 999,
          "schemaVersion": "\(LocalLedgerStore.currentSchemaVersion)",
          "deviceID": "\(foreignDeviceID.uuidString)",
          "generatedAt": "2027-01-15T08:00:00.000000000Z",
          "books": [],
          "categories": [],
          "entries": []
        }
        """
        try Data(json.utf8).write(to: url)

        do {
            _ = try await repository.synchronize(folderURL: fixture.exchangeURL, deviceID: UUID())
            Issue.record("Expected unsupported format to fail")
        } catch let error as LedgerFolderSyncError {
            #expect(error == .unsupportedFormatVersion(file: url.lastPathComponent, found: 999))
        }
        #expect(try await repository.fetchEntries() == before)
    }

    @Test func atomicSnapshotHasNoTemporaryRemainderAndReopenKeepsImportedData() async throws {
        let fixture = FolderSyncTestFixture()
        defer { fixture.remove() }
        let deviceA = UUID()
        let deviceB = UUID()
        let entryID = UUID()
        do {
            let repositoryA = try SwiftDataLedgerRepository(storeURL: fixture.storeAURL)
            _ = try await repositoryA.createEntry(syncDraft(amount: 404, note: "原子快照"), id: entryID)
            _ = try await repositoryA.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceA)
        }
        do {
            let repositoryB = try SwiftDataLedgerRepository(storeURL: fixture.storeBURL)
            _ = try await repositoryB.synchronize(folderURL: fixture.exchangeURL, deviceID: deviceB)
        }

        let devicesURL = LedgerFolderSnapshotIO.snapshotFileURL(
            in: fixture.exchangeURL,
            deviceID: deviceA
        ).deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: devicesURL.path)
        #expect(names.filter { $0.hasSuffix(".json") }.count == 2)
        #expect(names.allSatisfy { !$0.hasSuffix(".tmp") })
        #expect(try LedgerFolderSnapshotIO.readAll(from: fixture.exchangeURL).count == 2)

        let reopenedB = try SwiftDataLedgerRepository(storeURL: fixture.storeBURL)
        #expect(try await reopenedB.fetchEntries().map(\.id) == [entryID])
    }
}

private struct FolderSyncTestFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("YoloLedgerFolderSyncTests-\(UUID())", isDirectory: true)

    var exchangeURL: URL { rootURL.appendingPathComponent("exchange", isDirectory: true) }
    var storeAURL: URL { rootURL.appendingPathComponent("A/ledger.store") }
    var storeBURL: URL { rootURL.appendingPathComponent("B/ledger.store") }

    init() {
        try! FileManager.default.createDirectory(at: exchangeURL, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}

private func syncDraft(amount: Int64, note: String) -> LedgerEntryDraft {
    LedgerEntryDraft(
        bookID: LedgerSeedData.defaultBook.id,
        categoryID: LedgerSeedData.categories.first { $0.kind == .expense }!.id,
        kind: .expense,
        amount: try! LedgerAmount(minorUnits: amount),
        date: Date(timeIntervalSince1970: 1_700_000_000),
        note: note,
        source: .manual
    )
}

@MainActor
private func allEntryRecords(at storeURL: URL) throws -> [LedgerSchemaV1.EntryRecord] {
    let container = try LocalLedgerStore.makeContainer(at: storeURL)
    return try ModelContext(container).fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>())
}

private func snapshotBase(deviceID: UUID, entries: [LedgerFolderSnapshot.Entry]) -> LedgerFolderSnapshot {
    let timestamp = Date(timeIntervalSinceReferenceDate: 0)
    let category = LedgerSeedData.categories.first { $0.kind == .expense }!
    return LedgerFolderSnapshot(
        formatVersion: LedgerFolderSnapshot.currentFormatVersion,
        schemaVersion: LocalLedgerStore.currentSchemaVersion,
        deviceID: deviceID,
        generatedAt: Date(timeIntervalSince1970: 1_800_000_100),
        books: [LedgerFolderSnapshot.Book(
            id: LedgerSeedData.defaultBook.id,
            name: LedgerSeedData.defaultBook.name,
            sortOrder: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )],
        categories: [LedgerFolderSnapshot.Category(
            id: category.id,
            name: category.name,
            kindRawValue: category.kind.rawValue,
            sortOrder: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil
        )],
        entries: entries
    )
}

private func singleEntrySnapshot(
    deviceID: UUID,
    entryID: UUID,
    note: String,
    updatedAt: Date
) -> LedgerFolderSnapshot {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let category = LedgerSeedData.categories.first { $0.kind == .expense }!
    return snapshotBase(deviceID: deviceID, entries: [LedgerFolderSnapshot.Entry(
        id: entryID,
        bookID: LedgerSeedData.defaultBook.id,
        categoryID: category.id,
        kindRawValue: LedgerEntryKind.expense.rawValue,
        amountMinorUnits: 100,
        occurredAt: createdAt,
        note: note,
        sourceRawValue: LedgerEntrySource.manual.rawValue,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: nil
    )])
}

private func conflictSnapshot(
    deviceID: UUID,
    timestamp: Date,
    tieID: UUID,
    tieNote: String,
    tombstoneID: UUID,
    tombstoneDate: Date?
) -> LedgerFolderSnapshot {
    let category = LedgerSeedData.categories.first { $0.kind == .expense }!
    let makeEntry: (UUID, String, Date?) -> LedgerFolderSnapshot.Entry = { id, note, deletedAt in
        LedgerFolderSnapshot.Entry(
            id: id,
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: category.id,
            kindRawValue: LedgerEntryKind.expense.rawValue,
            amountMinorUnits: 100,
            occurredAt: timestamp,
            note: note,
            sourceRawValue: LedgerEntrySource.manual.rawValue,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: deletedAt
        )
    }
    return snapshotBase(deviceID: deviceID, entries: [
        makeEntry(tieID, tieNote, nil),
        makeEntry(tombstoneID, tombstoneDate == nil ? "zzz live" : "aaa deleted", tombstoneDate),
    ])
}
