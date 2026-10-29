import Foundation
import SwiftData
import Testing
@testable import YoloLedgerStorage

struct LocalLedgerStoreTests {
    @Test func diskStoreUsesExplicitURLAndDisablesCloudKit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YoloLedgerStorageTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("ledger.store")
        let container = try LocalLedgerStore.makeContainer(at: storeURL)
        let configuration = try #require(container.configurations.first)
        #expect(configuration.url == storeURL)
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(!configuration.isStoredInMemoryOnly)
        #expect(FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test func nonFileURLIsRejected() throws {
        let storeURL = try #require(URL(string: "https://example.invalid/ledger.store"))
        #expect(throws: LedgerStorageError.invalidStoreURL) {
            try LocalLedgerStore.makeContainer(at: storeURL)
        }
    }

    @Test func filesystemFailureDoesNotReplaceExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YoloLedgerStorageTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockingFile = directory.appendingPathComponent("existing-file")
        let original = Data("existing user file".utf8)
        try original.write(to: blockingFile)
        #expect(throws: (any Error).self) {
            try LocalLedgerStore.makeContainer(at: blockingFile.appendingPathComponent("ledger.store"))
        }
        #expect(try Data(contentsOf: blockingFile) == original)
    }

    @Test func corruptDatabaseIsReportedWithoutClearingOriginalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YoloLedgerStorageTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("ledger.store")
        let original = Data("not a valid sqlite database".utf8)
        try original.write(to: storeURL)
        #expect(throws: (any Error).self) {
            try LocalLedgerStore.makeContainer(at: storeURL)
        }
        #expect(try Data(contentsOf: storeURL) == original)
    }

    @Test @MainActor func versionOneStoreReopensWithSavedData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YoloLedgerStorageTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("ledger.store")
        let id = UUID()
        do {
            let container = try LocalLedgerStore.makeContainer(at: storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(LedgerSchemaV1.BookRecord(id: id, name: "磁盘账本", sortOrder: 0))
            try context.save()
        }
        let reopened = try LocalLedgerStore.makeContainer(at: storeURL)
        let context = ModelContext(reopened)
        let records = try context.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
        #expect(records.count == 1)
        #expect(records.first?.id == id)
        #expect(records.first?.name == "磁盘账本")
    }

    @Test @MainActor func existingStoreIsSnapshottedOnceBeforeSchemaUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YoloLedgerStorageTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("ledger.store")
        let id = UUID()

        do {
            let container = try LocalLedgerStore.makeContainer(at: storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(LedgerSchemaV1.BookRecord(id: id, name: "升级前账本", sortOrder: 0))
            try context.save()
        }

        let markerURL = StoreUpgradeSnapshot.schemaMarkerURL(for: storeURL)
        try Data("0.9.0\n".utf8).write(to: markerURL, options: .atomic)
        _ = try LocalLedgerStore.makeContainer(at: storeURL)

        let snapshotURL = StoreUpgradeSnapshot.snapshotStoreURL(
            for: storeURL,
            targetSchemaVersion: LocalLedgerStore.currentSchemaVersion
        )
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(try String(contentsOf: markerURL, encoding: .utf8) == "1.0.0\n")
        #expect(try fetchBooks(from: snapshotURL).map(\.name) == ["升级前账本"])

        do {
            let container = try LocalLedgerStore.makeContainer(at: storeURL)
            let context = ModelContext(container)
            let book = try #require(context.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>()).first)
            book.name = "升级后账本"
            try context.save()
        }
        try Data("0.9.0\n".utf8).write(to: markerURL, options: .atomic)
        _ = try LocalLedgerStore.makeContainer(at: storeURL)

        #expect(try fetchBooks(from: snapshotURL).map(\.name) == ["升级前账本"])
        let current = try LocalLedgerStore.makeContainer(at: storeURL)
        let currentBooks = try ModelContext(current).fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
        #expect(currentBooks.map(\.name) == ["升级后账本"])
    }
}

@MainActor
private func fetchBooks(from storeURL: URL) throws -> [LedgerSchemaV1.BookRecord] {
    let schema = Schema(versionedSchema: LedgerSchemaV1.self)
    let configuration = ModelConfiguration(
        "UpgradeSnapshotVerification",
        schema: schema,
        url: storeURL,
        allowsSave: false,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: schema,
        migrationPlan: LedgerMigrationPlan.self,
        configurations: [configuration]
    )
    return try ModelContext(container).fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
}
