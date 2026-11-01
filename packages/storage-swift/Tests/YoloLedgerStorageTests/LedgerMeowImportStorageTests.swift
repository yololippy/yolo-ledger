import Foundation
import SwiftData
import Testing
import YoloLedgerCore
@testable import YoloLedgerStorage

struct LedgerMeowImportStorageTests {
    @Test @MainActor func versionOneStoreMigratesWithoutLosingExistingData() async throws {
        let directory = MeowImportTestDirectory()
        defer { directory.remove() }
        let entryID = UUID()
        do {
            let schema = Schema(versionedSchema: LedgerSchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(
                    "LegacyV1",
                    schema: schema,
                    url: directory.storeURL,
                    cloudKitDatabase: .none
                )]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(LedgerSchemaV1.BookRecord(
                id: LedgerSeedData.defaultBook.id,
                name: LedgerSeedData.defaultBook.name,
                sortOrder: 0,
                createdAt: .distantPast,
                updatedAt: .distantPast
            ))
            let category = LedgerSeedData.categories[0]
            context.insert(LedgerSchemaV1.CategoryRecord(
                id: category.id,
                name: category.name,
                kindRawValue: category.kind.rawValue,
                sortOrder: 0,
                createdAt: .distantPast,
                updatedAt: .distantPast
            ))
            context.insert(LedgerSchemaV1.EntryRecord(
                id: entryID,
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: category.id,
                kindRawValue: LedgerEntryKind.expense.rawValue,
                amountMinorUnits: 1_234,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                note: "迁移前账目",
                sourceRawValue: LedgerEntrySource.manual.rawValue,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_002)
            ))
            context.insert(LedgerSchemaV1.StoreMetadata(key: "starter-choices-v1"))
            context.insert(LedgerSchemaV1.StoreMetadata(key: "starter-categories-v2"))
            try context.save()
        }
        try Data("1.1.0\n".utf8).write(
            to: StoreUpgradeSnapshot.schemaMarkerURL(for: directory.storeURL),
            options: .atomic
        )

        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let migrated = try #require(try await repository.fetchEntries().first { $0.id == entryID })
        #expect(migrated.note == "迁移前账目")
        #expect(migrated.amount.minorUnits == 1_234)
        #expect(migrated.importMetadata == nil)

        let current = try LocalLedgerStore.makeContainer(at: directory.storeURL)
        let record = try #require(ModelContext(current)
            .fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())
            .first { $0.id == entryID })
        #expect(record.importDeduplicationKey == nil)
        #expect(FileManager.default.fileExists(atPath: StoreUpgradeSnapshot.snapshotStoreURL(
            for: directory.storeURL,
            targetSchemaVersion: LocalLedgerStore.currentSchemaVersion
        ).path))
    }

    @Test @MainActor func importCreatesExactMappingsMetadataReportAndRecoverableBackup() async throws {
        let directory = MeowImportTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let manualID = UUID()
        _ = try await repository.createEntry(meowManualDraft(note: "原有有落记录"), id: manualID)
        let plan = parseMeowRows([
            "古董,2026-10-30 08:15:00,-12.34,现金账户,旧日常账本,CNY,早市购买",
            "古董,2026-10-31 09:00:00,+88.00,海外卡,旧日常账本,USD,出售所得",
        ])

        let report = try await repository.importMeowLedger(plans: [plan])
        #expect(report.submittedRecordCount == 2)
        #expect(report.importedEntryCount == 2)
        #expect(report.skippedDuplicateCount == 0)
        #expect(report.createdBookCount == 1)
        #expect(report.createdCategoryCount == 2)
        #expect(report.importedExpenseCount == 1)
        #expect(report.importedIncomeCount == 1)
        #expect(report.importedExpenseTotalMinorUnits == Decimal(1_234))
        #expect(report.importedIncomeTotalMinorUnits == Decimal(8_800))
        #expect(FileManager.default.fileExists(atPath: report.backupURL.path))
        #expect(FileManager.default.fileExists(
            atPath: report.backupURL.appendingPathComponent("manifest.json").path
        ))

        let books = try await repository.fetchBooks()
        let categories = try await repository.fetchCategories()
        let entries = try await repository.fetchEntries()
        #expect(books.contains { $0.name == "旧日常账本" })
        #expect(categories.contains { $0.name == "古董" && $0.kind == .expense })
        #expect(categories.contains { $0.name == "古董" && $0.kind == .income })
        #expect(entries.contains { $0.id == manualID && $0.note == "原有有落记录" })
        let imported = entries.filter { $0.source == .meowLedgerImport }
        #expect(imported.count == 2)
        #expect(Set(imported.compactMap { $0.importMetadata?.originalAccount }) == ["现金账户", "海外卡"])
        #expect(Set(imported.compactMap { $0.importMetadata?.originalCurrency }) == ["CNY", "USD"])
        #expect(Set(imported.compactMap { $0.importMetadata?.originalBook }) == ["旧日常账本"])
        #expect(Set(imported.compactMap { $0.importMetadata?.originalCategory }) == ["古董"])
        #expect(Set(imported.compactMap { $0.importMetadata?.originalAmount }) == ["-12.34", "+88.00"])
        #expect(Set(imported.compactMap { $0.importMetadata?.originalTimestamp }) == [
            "2026-10-30 08:15:00", "2026-10-31 09:00:00",
        ])

        let originalImported = try #require(imported.first)
        let edited = try await repository.updateEntry(
            id: originalImported.id,
            draft: LedgerEntryDraft(
                bookID: originalImported.bookID,
                categoryID: originalImported.categoryID,
                kind: originalImported.kind,
                amount: originalImported.amount,
                date: originalImported.date,
                note: "有落内修改后的备注"
            )
        )
        #expect(edited.source == .meowLedgerImport)
        #expect(edited.importMetadata == originalImported.importMetadata)
        #expect(edited.importMetadata?.originalNote == originalImported.importMetadata?.originalNote)

        let backupEntries = try readV2Entries(
            from: report.backupURL.appendingPathComponent(directory.storeURL.lastPathComponent)
        )
        #expect(backupEntries.map(\.id) == [manualID])

        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchEntries().filter { $0.source == .meowLedgerImport }.count == 2)
        #expect(try await reopened.fetchEntries().allSatisfy {
            $0.source != .meowLedgerImport || $0.importMetadata != nil
        })
    }

    @Test func anyIssueRejectsTheWholeMultiFileBatchWithoutBackupOrWrites() async throws {
        let directory = MeowImportTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let valid = parseMeowRows([
            "餐饮,2026-10-30 08:15:00,-12.34,现金,待回滚账本,CNY,不应写入",
        ])
        let invalid = parseMeowRows([
            "购物,not-a-date,-3.00,现金,待回滚账本,CNY,错误行",
        ])
        let beforeBooks = try await repository.fetchBooks()
        let beforeCategories = try await repository.fetchCategories()

        await #expect(throws: LedgerMeowImportStorageError.planContainsIssues(
            planIndex: 1,
            issueCount: invalid.issues.count
        )) {
            try await repository.importMeowLedger(plans: [valid, invalid])
        }
        #expect(try await repository.fetchEntries().isEmpty)
        #expect(try await repository.fetchBooks() == beforeBooks)
        #expect(try await repository.fetchCategories() == beforeCategories)
        #expect(!FileManager.default.fileExists(
            atPath: directory.url.appendingPathComponent("ImportSnapshots").path
        ))
    }

    @Test func duplicateRowsAndRepeatedFilesAreIdempotentAcrossBatches() async throws {
        let directory = MeowImportTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let duplicatePlan = parseMeowRows([
            "餐饮,2026-10-30 08:15:00,-12.34,现金,历史账本,CNY,完全相同",
            "餐饮,2026-10-30 08:15:00,-12.34,现金,历史账本,CNY,完全相同",
        ])
        let overlappingFile = parseMeowRows([
            "餐饮,2026-10-30 08:15:00,-12.34,现金,历史账本,CNY,完全相同",
            "交通,2026-11-01 10:00:00,-5.00,公交卡,历史账本,CNY,跨文件新增",
        ])

        let first = try await repository.importMeowLedger(plans: [duplicatePlan, overlappingFile])
        #expect(first.submittedRecordCount == 4)
        #expect(first.importedEntryCount == 3)
        #expect(first.skippedDuplicateCount == 1)
        let firstEntries = try await repository.fetchEntries()
        #expect(firstEntries.count == 3)
        #expect(Set(firstEntries.compactMap { $0.importMetadata?.deduplicationKey }).count == 3)

        let repeated = try await repository.importMeowLedger(plans: [duplicatePlan])
        #expect(repeated.importedEntryCount == 0)
        #expect(repeated.skippedDuplicateCount == 2)
        #expect(try await repository.fetchEntries().count == 3)
    }

    @Test func backupFailureLeavesAllExistingDataUntouched() async throws {
        let directory = MeowImportTestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let original = try await repository.createEntry(meowManualDraft(note: "必须保留"))
        let blockingURL = directory.url.appendingPathComponent("ImportSnapshots")
        try Data("blocking file".utf8).write(to: blockingURL)
        let plan = parseMeowRows([
            "未知分类,2026-10-30 08:15:00,-12.34,现金,未知账本,CNY,不应落库",
        ])

        await #expect(throws: (any Error).self) {
            try await repository.importMeowLedger(plans: [plan])
        }
        #expect(try await repository.fetchEntries() == [original])
        #expect(try await repository.fetchBooks() == LedgerSeedData.books)
        #expect(try await repository.fetchCategories() == LedgerSeedData.categories)
    }

    @Test func folderSyncRoundTripRetainsEveryImportMetadataField() async throws {
        let directory = MeowImportTestDirectory()
        defer { directory.remove() }
        let repositoryA = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let repositoryB = try SwiftDataLedgerRepository(storeURL: directory.storeBURL)
        let plan = parseMeowRows([
            "独有分类,2026-10-30 08:15:00,-12.34,现金账户,旧账本,HKD,同步保真",
        ])
        _ = try await repositoryA.makeMeowImportHandler()([plan])
        _ = try await repositoryB.importMeowLedger(plans: [plan])
        let importedA = try #require(try await repositoryA.fetchEntries().first)
        let independentlyImportedB = try #require(try await repositoryB.fetchEntries().first)
        #expect(independentlyImportedB.id == importedA.id)
        _ = try await repositoryA.synchronize(folderURL: directory.exchangeURL, deviceID: UUID())
        _ = try await repositoryB.synchronize(folderURL: directory.exchangeURL, deviceID: UUID())

        let importedB = try #require(try await repositoryB.fetchEntries().first)
        #expect(try await repositoryB.fetchEntries().count == 1)
        #expect(importedB.id == importedA.id)
        #expect(importedB.importMetadata == importedA.importMetadata)
        #expect(importedB.source == .meowLedgerImport)
        let raw = try ModelContext(LocalLedgerStore.makeContainer(at: directory.storeBURL))
            .fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())
        let record = try #require(raw.first { $0.id == importedA.id })
        #expect(record.importOriginalAccount == "现金账户")
        #expect(record.importOriginalCurrency == "HKD")
        #expect(record.importOriginalBook == "旧账本")
        #expect(record.importOriginalCategory == "独有分类")
    }
}

private struct MeowImportTestDirectory {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("YoloLedgerMeowImportTests-\(UUID())", isDirectory: true)
    var storeURL: URL { url.appendingPathComponent("ledger.store") }
    var storeBURL: URL { url.appendingPathComponent("B/ledger.store") }
    var exchangeURL: URL { url.appendingPathComponent("Exchange", isDirectory: true) }

    init() {
        try! FileManager.default.createDirectory(at: exchangeURL, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

private func parseMeowRows(_ rows: [String]) -> LedgerMeowImportPlan {
    var calendar = Calendar(identifier: .gregorian)
    let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    calendar.timeZone = timeZone
    let csv = "分类,时间,金额,账户,账本,货币,备注\r\n"
        + rows.joined(separator: "\r\n")
        + "\r\n"
    return LedgerMeowCSVParser.parse(
        data: Data(csv.utf8),
        calendar: calendar,
        timeZone: timeZone
    )
}

private func meowManualDraft(note: String) -> LedgerEntryDraft {
    LedgerEntryDraft(
        bookID: LedgerSeedData.defaultBook.id,
        categoryID: LedgerSeedData.categories.first { $0.kind == .expense }!.id,
        kind: .expense,
        amount: try! LedgerAmount(minorUnits: 100),
        date: Date(timeIntervalSince1970: 1_700_000_000),
        note: note
    )
}

@MainActor
private func readV2Entries(from storeURL: URL) throws -> [LedgerSchemaV3.EntryRecord] {
    let schema = Schema(versionedSchema: LedgerSchemaV3.self)
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(
            "ImportBackupVerification",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )]
    )
    return try ModelContext(container).fetch(FetchDescriptor<LedgerSchemaV3.EntryRecord>())
}
