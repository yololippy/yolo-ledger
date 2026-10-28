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
}
