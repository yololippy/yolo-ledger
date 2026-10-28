import Foundation
import SwiftData
import Testing
import YoloLedgerCore
@testable import YoloLedgerStorage

struct CategorySeedUpgradeTests {
    @Test @MainActor func legacyEightCategoryDatabaseUpgradesAndPersistsWithoutChangingUserData() async throws {
        let directory = CategoryUpgradeDirectory()
        defer { directory.remove() }
        try makeLegacyV1Fixture(at: directory.storeURL)
        let before = try persistedSnapshot(at: directory.storeURL)
        #expect(before.categories.count == 8)
        #expect(before.markers == ["starter-choices-v1"])

        do {
            let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
            #expect(try await repository.fetchCategories() == LedgerSeedData.categories)
        }
        let saved = try persistedSnapshot(at: directory.storeURL)
        #expect(saved.categories.count == 17)
        #expect(saved.books == before.books)
        #expect(saved.entries == before.entries)
        #expect(saved.markers == ["starter-choices-v1", "starter-categories-v2"])
        #expect(saved.categories.first { $0.id == frozenID(105) }?.name == "其它")
        #expect(saved.categories.first { $0.id == frozenID(104) }?.name == "日用")
        for suffix in [201, 202, 203] {
            let original = try #require(before.categories.first { $0.id == frozenID(suffix) })
            let upgraded = try #require(saved.categories.first { $0.id == original.id })
            #expect(upgraded.name == original.name)
            #expect(upgraded.kind == original.kind)
        }
        for (order, category) in LedgerSeedData.categories.enumerated() {
            #expect(saved.categories.first { $0.id == category.id }?.sortOrder == order)
        }

        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchCategories() == LedgerSeedData.categories)
        #expect(try await reopened.fetchEntries() == before.entries)
        #expect(try persistedSnapshot(at: directory.storeURL) == saved)
    }

    @Test @MainActor func newAndUpgradedInstallationsExposeTheSameCategoryChoices() async throws {
        let legacy = CategoryUpgradeDirectory()
        let fresh = CategoryUpgradeDirectory()
        defer { legacy.remove(); fresh.remove() }
        try makeLegacyV1Fixture(at: legacy.storeURL)
        let upgraded = try SwiftDataLedgerRepository(storeURL: legacy.storeURL)
        let newInstall = try SwiftDataLedgerRepository(storeURL: fresh.storeURL)
        let categories = try await upgraded.fetchCategories()
        #expect(try await newInstall.fetchCategories() == categories)
        #expect(categories.filter { $0.kind == .expense }.map(\.name) == [
            "餐饮", "交通", "购物", "宠物", "住房", "零食", "旅行",
            "通讯", "医疗", "Pos", "其它", "礼金", "运动", "日用",
        ])
        #expect(categories.filter { $0.kind == .income }.map(\.name) == ["工资", "奖金", "其他收入"])
        #expect(try persistedSnapshot(at: fresh.storeURL).markers == ["starter-choices-v1", "starter-categories-v2"])
    }

    @Test @MainActor func userNamesCustomCategoriesAndReferencingEntriesArePreserved() async throws {
        let directory = CategoryUpgradeDirectory()
        defer { directory.remove() }
        try makeLegacyV1Fixture(at: directory.storeURL, customized: true)
        let before = try persistedSnapshot(at: directory.storeURL)
        do {
            let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
            let categories = try await repository.fetchCategories()
            #expect(categories.first { $0.id == frozenID(105) }?.name == "我的杂项")
            #expect(categories.first { $0.id == frozenID(102) }?.name == "我的通勤")
            #expect(categories.first { $0.id == frozenID(106) }?.name == "家庭宠物护理")
        }
        let after = try persistedSnapshot(at: directory.storeURL)
        #expect(after.categories.count == 18)
        #expect(after.books == before.books)
        #expect(after.entries == before.entries)
        #expect(after.categories.first { $0.id == frozenID(9901) } == before.categories.first { $0.id == frozenID(9901) })
        #expect(after.markers.contains("user-metadata"))
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let systemIDs = Set(LedgerSeedData.categories.map(\.id))
        #expect(try await repository.fetchCategories().filter { systemIDs.contains($0.id) }.map(\.id)
            == LedgerSeedData.categories.map(\.id))
        #expect(try persistedSnapshot(at: directory.storeURL) == after)
    }

    @Test @MainActor func failedUpgradeSaveRollsBackAndWritableOpenRetries() async throws {
        let directory = CategoryUpgradeDirectory()
        defer { directory.remove() }
        try makeLegacyV1Fixture(at: directory.storeURL)
        let before = try persistedSnapshot(at: directory.storeURL)
        do {
            let container = try readOnlyContainer(at: directory.storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            #expect(throws: (any Error).self) { try LedgerSeedBootstrap.initialize(in: context) }
            #expect(!context.hasChanges)
            #expect(try context.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>()).count == 8)
            #expect(try context.fetch(FetchDescriptor<LedgerSchemaV1.StoreMetadata>()).map(\.key) == ["starter-choices-v1"])
        }
        #expect(try persistedSnapshot(at: directory.storeURL) == before)
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await repository.fetchCategories() == LedgerSeedData.categories)
        #expect(try persistedSnapshot(at: directory.storeURL).markers.contains("starter-categories-v2"))
    }

    @Test @MainActor func completedUpgradeDoesNotSaveAgainOrOverwriteLaterUserChanges() async throws {
        let directory = CategoryUpgradeDirectory()
        defer { directory.remove() }
        try makeLegacyV1Fixture(at: directory.storeURL)
        do { _ = try SwiftDataLedgerRepository(storeURL: directory.storeURL) }
        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let category = try #require(context.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>())
                .first { $0.id == frozenID(105) })
            // After this upgrade, even a user choosing the old spelling is no longer a seed default.
            category.name = "其他支出"
            category.sortOrder = 500
            try context.save()
        }
        let beforeReopen = try persistedSnapshot(at: directory.storeURL)
        do {
            let container = try readOnlyContainer(at: directory.storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try LedgerSeedBootstrap.initialize(in: context)
            #expect(!context.hasChanges)
        }
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchCategories().first { $0.id == frozenID(105) }?.name == "其他支出")
        #expect(try persistedSnapshot(at: directory.storeURL) == beforeReopen)
    }
}

private struct CategoryUpgradeDirectory {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("YoloLedgerCategoryUpgrade-\(UUID())", isDirectory: true)
    var storeURL: URL { url.appendingPathComponent("ledger.store") }
    func remove() { try? FileManager.default.removeItem(at: url) }
}

// Frozen legacy values: deliberately independent of the current Core seed list.
private let legacyCategories: [(Int, String, LedgerEntryKind)] = [
    (101, "餐饮", .expense), (102, "交通", .expense), (103, "购物", .expense),
    (104, "日用", .expense), (105, "其他支出", .expense),
    (201, "工资", .income), (202, "奖金", .income), (203, "其他收入", .income),
]

private func frozenID(_ suffix: Int) -> UUID {
    let digits = String(suffix)
    return UUID(uuidString: "A20E127A-36F6-401A-A6E3-" + String(repeating: "0", count: 12 - digits.count) + digits)!
}

@MainActor
private func makeLegacyV1Fixture(at url: URL, customized: Bool = false) throws {
    let container = try LocalLedgerStore.makeContainer(at: url)
    let context = ModelContext(container)
    context.autosaveEnabled = false
    context.insert(LedgerSchemaV1.BookRecord(id: frozenID(1), name: "用户改名账本", sortOrder: 0))
    for (order, value) in legacyCategories.enumerated() {
        let (suffix, defaultName, kind) = value
        let name = customized && suffix == 105 ? "我的杂项" : customized && suffix == 102 ? "我的通勤" : defaultName
        context.insert(LedgerSchemaV1.CategoryRecord(
            id: frozenID(suffix), name: name, kindRawValue: kind.rawValue, sortOrder: order
        ))
    }
    context.insert(LedgerSchemaV1.StoreMetadata(key: "starter-choices-v1"))
    let originalChoices: [(Int, Int, LedgerEntryKind)] = [(105, 12345, .expense), (104, 999, .expense), (201, 100001, .income)]
    for (offset, choice) in originalChoices.enumerated() {
        insertFrozenEntry(in: context, suffix: 8001 + offset, bookSuffix: 1,
                          categorySuffix: choice.0, amount: Int64(choice.1), kind: choice.2, offset: offset)
    }
    if customized {
        context.insert(LedgerSchemaV1.BookRecord(id: frozenID(9001), name: "自定义账本", sortOrder: 23))
        context.insert(LedgerSchemaV1.CategoryRecord(
            id: frozenID(9901), name: "自定义项目", kindRawValue: "expense", sortOrder: 90
        ))
        context.insert(LedgerSchemaV1.CategoryRecord(
            id: frozenID(106), name: "家庭宠物护理", kindRawValue: "expense", sortOrder: 91
        ))
        context.insert(LedgerSchemaV1.StoreMetadata(key: "user-metadata"))
        insertFrozenEntry(in: context, suffix: 8004, bookSuffix: 9001,
                          categorySuffix: 9901, amount: 4567, kind: .expense, offset: 3)
    }
    try context.save()
}

private func insertFrozenEntry(
    in context: ModelContext, suffix: Int, bookSuffix: Int, categorySuffix: Int,
    amount: Int64, kind: LedgerEntryKind, offset: Int
) {
    context.insert(LedgerSchemaV1.EntryRecord(
        id: frozenID(suffix), bookID: frozenID(bookSuffix), categoryID: frozenID(categorySuffix),
        kindRawValue: kind.rawValue, amountMinorUnits: amount,
        occurredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset)),
        note: "旧版账目 \(offset)", sourceRawValue: "manual",
        createdAt: Date(timeIntervalSince1970: 1_700_100_000 + Double(offset)),
        updatedAt: Date(timeIntervalSince1970: 1_700_200_000 + Double(offset))
    ))
}

private struct PersistedCategory: Equatable {
    let id: UUID
    let name: String
    let kind: String
    let sortOrder: Int
}

private struct PersistedBook: Equatable {
    let id: UUID
    let name: String
    let sortOrder: Int
}

private struct PersistedSeedSnapshot: Equatable {
    let books: [PersistedBook]
    let categories: [PersistedCategory]
    let entries: [LedgerEntry]
    let markers: Set<String>
}

@MainActor
private func persistedSnapshot(at url: URL) throws -> PersistedSeedSnapshot {
    let container = try LocalLedgerStore.makeContainer(at: url)
    let context = ModelContext(container)
    let books = try context.fetch(FetchDescriptor<LedgerSchemaV1.BookRecord>())
        .map { PersistedBook(id: $0.id, name: $0.name, sortOrder: $0.sortOrder) }
        .sorted { $0.id.uuidString < $1.id.uuidString }
    let categories = try context.fetch(FetchDescriptor<LedgerSchemaV1.CategoryRecord>())
        .map { PersistedCategory(id: $0.id, name: $0.name, kind: $0.kindRawValue, sortOrder: $0.sortOrder) }
        .sorted { $0.id.uuidString < $1.id.uuidString }
    let entries = try context.fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>()).map { record in
        LedgerEntry(
            id: record.id,
            draft: LedgerEntryDraft(
                bookID: record.bookID, categoryID: record.categoryID,
                kind: LedgerEntryKind(rawValue: record.kindRawValue)!,
                amount: try LedgerAmount(minorUnits: record.amountMinorUnits),
                date: record.occurredAt, note: record.note,
                source: LedgerEntrySource(rawValue: record.sourceRawValue)!
            ),
            createdAt: record.createdAt, updatedAt: record.updatedAt
        )
    }.sorted { $0.date > $1.date }
    let markers = Set(try context.fetch(FetchDescriptor<LedgerSchemaV1.StoreMetadata>()).map(\.key))
    return PersistedSeedSnapshot(books: books, categories: categories, entries: entries, markers: markers)
}

@MainActor
private func readOnlyContainer(at url: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: LedgerSchemaV1.self)
    return try ModelContainer(
        for: schema,
        migrationPlan: LedgerMigrationPlan.self,
        configurations: [ModelConfiguration("YoloLedgerLocal", schema: schema, url: url,
                                            allowsSave: false, cloudKitDatabase: .none)]
    )
}
