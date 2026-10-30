import Foundation
import SwiftData
import Testing
import YoloLedgerCore
@testable import YoloLedgerStorage

struct SwiftDataLedgerRepositoryTests {
    @Test func starterChoicesAreStableAndInitializedOnce() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await repository.fetchBooks() == LedgerSeedData.books)
        #expect(try await repository.fetchCategories() == LedgerSeedData.categories)
        _ = try await repository.renameBook(id: LedgerSeedData.defaultBook.id, name: "我的日常")
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchBooks() == [
            LedgerBook(id: LedgerSeedData.defaultBook.id, name: "我的日常"),
        ])
        #expect(try await reopened.fetchCategories() == LedgerSeedData.categories)
        #expect(try await reopened.fetchEntries().isEmpty)
    }

    @Test func createdEntrySurvivesRepositoryLifetimeAndKeepsExactAmount() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let created = try await createFixture(at: directory.storeURL, amount: Int64.max)
        #expect(FileManager.default.fileExists(atPath: directory.storeURL.path))
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let fetched = try #require(await reopened.fetchEntries().first)
        #expect(fetched == created)
        #expect(fetched.amount.minorUnits == Int64.max)
        #expect(fetched.amount.decimalString == "92233720368547758.07")
        #expect(fetched.note == "午餐 🥟\n测试备注")
        #expect(fetched.source == .manual)
    }

    @Test func updatePreservesIdentityAndAuditFieldsAcrossReopen() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let created = try await createFixture(at: directory.storeURL, amount: 1234)
        let updated: LedgerEntry
        let secondBookID = UUID()
        do {
            let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
            _ = try await repository.createBook(name: "旅行", id: secondBookID)
            updated = try await repository.updateEntry(
                id: created.id,
                draft: makeDraft(bookID: secondBookID, kind: .income, amount: 100001, note: "工资到账")
            )
        }
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let fetched = try #require(await reopened.fetchEntries(bookID: secondBookID).first)
        #expect(fetched == updated)
        #expect(fetched.id == created.id)
        #expect(fetched.createdAt == created.createdAt)
        #expect(fetched.source == created.source)
        #expect(fetched.updatedAt >= created.updatedAt)
        #expect(fetched.bookID == secondBookID)
        #expect(fetched.kind == .income)
        #expect(fetched.amount.minorUnits == 100001)
        #expect(try await reopened.fetchEntries(bookID: created.bookID).isEmpty)
    }

    @Test @MainActor func deletedEntryStaysDeletedAfterReopen() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let created = try await createFixture(at: directory.storeURL, amount: 1)
        do {
            let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
            try await repository.deleteEntry(id: created.id)
            await #expect(throws: LedgerError.entryNotFound(created.id)) {
                try await repository.deleteEntry(id: created.id)
            }
        }
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchEntries().isEmpty)
        await #expect(throws: LedgerError.duplicateIdentifier(created.id)) {
            try await reopened.createEntry(makeDraft(amount: 2), id: created.id)
        }

        let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
        let records = try ModelContext(container).fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>())
        let record = try #require(records.first { $0.id == created.id })
        #expect(record.deletedAt != nil)
    }

    @Test @MainActor func newerCloudConflictWinsAndDuplicatesAreRemoved() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        do {
            _ = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        }

        let id = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = olderDate.addingTimeInterval(60)
        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(LedgerSchemaV1.EntryRecord(
                id: id,
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: LedgerSeedData.categories.first { $0.kind == .expense }!.id,
                kindRawValue: LedgerEntryKind.expense.rawValue,
                amountMinorUnits: 100,
                occurredAt: olderDate,
                note: "旧值",
                sourceRawValue: LedgerEntrySource.manual.rawValue,
                createdAt: olderDate,
                updatedAt: olderDate
            ))
            context.insert(LedgerSchemaV1.EntryRecord(
                id: id,
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: LedgerSeedData.categories.first { $0.kind == .expense }!.id,
                kindRawValue: LedgerEntryKind.expense.rawValue,
                amountMinorUnits: 200,
                occurredAt: newerDate,
                note: "新值",
                sourceRawValue: LedgerEntrySource.manual.rawValue,
                createdAt: olderDate,
                updatedAt: newerDate
            ))
            try context.save()
        }

        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let entry = try #require(await repository.fetchEntries().first { $0.id == id })
        #expect(entry.amount.minorUnits == 200)
        #expect(entry.note == "新值")

        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let records = try ModelContext(container).fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>())
            #expect(records.filter { $0.id == id }.count == 1)
        }

        let deletionDate = newerDate.addingTimeInterval(60)
        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let context = ModelContext(container)
            context.insert(LedgerSchemaV1.EntryRecord(
                id: id,
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: LedgerSeedData.categories.first { $0.kind == .expense }!.id,
                kindRawValue: LedgerEntryKind.expense.rawValue,
                amountMinorUnits: 200,
                occurredAt: newerDate,
                note: "新值",
                sourceRawValue: LedgerEntrySource.manual.rawValue,
                createdAt: olderDate,
                updatedAt: deletionDate,
                deletedAt: deletionDate
            ))
            try context.save()
        }

        let afterDeletion = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await afterDeletion.fetchEntries().allSatisfy { $0.id != id })
        let finalContainer = try LocalLedgerStore.makeContainer(at: directory.storeURL)
        let finalRecords = try ModelContext(finalContainer).fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>())
            .filter { $0.id == id }
        #expect(finalRecords.count == 1)
        #expect(finalRecords.first?.deletedAt == deletionDate)
    }

    @Test func multipleBooksFilterAndRenameWithoutChangingEntryReferences() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let second = try await repository.createBook(name: "  旅行  ", id: UUID())
        #expect(second.name == "旅行")
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_100_000)
        let firstEntry = try await repository.createEntry(makeDraft(amount: 101, date: oldDate))
        let secondEntry = try await repository.createEntry(makeDraft(bookID: second.id, amount: 202, date: newDate))
        let renamed = try await repository.renameBook(id: second.id, name: "出游账本")
        #expect(renamed.id == second.id)
        #expect(try await repository.fetchEntries() == [secondEntry, firstEntry])
        #expect(try await repository.fetchEntries(bookID: second.id) == [secondEntry])
        #expect(try await repository.fetchEntries(bookID: firstEntry.bookID) == [firstEntry])
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchBooks().last == renamed)
        #expect(try await reopened.fetchEntries(bookID: second.id) == [secondEntry])
    }

    @Test func invalidReferencesKindsAndDatesDoNotPolluteStoredData() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let original = try await repository.createEntry(makeDraft(amount: 1234))
        let missingBookID = UUID()
        let missingCategoryID = UUID()
        let expenseCategory = LedgerSeedData.categories.first { $0.kind == .expense }!
        let failures: [(LedgerEntryDraft, LedgerError)] = [
            (makeDraft(bookID: missingBookID, amount: 888), .bookNotFound(missingBookID)),
            (makeDraft(categoryID: missingCategoryID, amount: 888), .categoryNotFound(missingCategoryID)),
            (makeDraft(categoryID: expenseCategory.id, kind: .income, amount: 888), .categoryKindMismatch),
            (makeDraft(amount: 888, date: Date(timeIntervalSinceReferenceDate: .infinity)), .invalidDate),
        ]
        for (draft, error) in failures {
            await #expect(throws: error) { try await repository.createEntry(draft) }
            await #expect(throws: error) { try await repository.updateEntry(id: original.id, draft: draft) }
            #expect(try await repository.fetchEntries() == [original])
        }
        _ = try await repository.createBook(name: "失败后仍可保存", id: UUID())
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchEntries() == [original])
    }

    @Test func duplicateAndMissingIdentifiersPropagateDomainErrors() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let draft = makeDraft(amount: 101)
        let id = UUID()
        let original = try await repository.createEntry(draft, id: id)
        await #expect(throws: LedgerError.duplicateIdentifier(id)) {
            try await repository.createEntry(makeDraft(amount: 999), id: id)
        }
        let defaultID = LedgerSeedData.defaultBook.id
        await #expect(throws: LedgerError.duplicateIdentifier(defaultID)) {
            try await repository.createBook(name: "不应覆盖", id: defaultID)
        }
        let missing = UUID()
        await #expect(throws: LedgerError.entryNotFound(missing)) {
            try await repository.updateEntry(id: missing, draft: draft)
        }
        await #expect(throws: LedgerError.entryNotFound(missing)) {
            try await repository.deleteEntry(id: missing)
        }
        await #expect(throws: LedgerError.bookNotFound(missing)) {
            try await repository.renameBook(id: missing, name: "不存在")
        }
        await #expect(throws: LedgerError.bookNotFound(missing)) {
            try await repository.fetchEntries(bookID: missing)
        }
        #expect(try await repository.fetchEntries() == [original])
        #expect(try await repository.fetchBooks() == LedgerSeedData.books)
    }

    @Test func emptyBookNamesAreRejectedWithoutModifyingExistingBooks() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        await #expect(throws: LedgerError.emptyName) {
            try await repository.createBook(name: " \n ", id: UUID())
        }
        await #expect(throws: LedgerError.emptyName) {
            try await repository.renameBook(id: LedgerSeedData.defaultBook.id, name: " \t ")
        }
        let reopened = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        #expect(try await reopened.fetchBooks() == LedgerSeedData.books)
    }

    @Test func concurrentCreatesWithSameIdentifierProduceOneEntry() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        let id = UUID()
        let draft = makeDraft(amount: 1234)
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do {
                        _ = try await repository.createEntry(draft, id: id)
                        return true
                    } catch LedgerError.duplicateIdentifier(id) {
                        return false
                    } catch {
                        Issue.record("Unexpected error: \(error)")
                        return false
                    }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        #expect(successes == 1)
        #expect(try await repository.fetchEntries().count == 1)
    }

    @Test @MainActor func failedMutationRollsBackBeforeNextSuccessfulSave() async throws {
        let directory = TestDirectory()
        defer { directory.remove() }
        let original = try await createFixture(at: directory.storeURL, amount: 1234)
        do {
            let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let record = try #require(context.fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>()).first)
            record.sourceRawValue = "unrecognized-source"
            try context.save()
        }
        let repository = try SwiftDataLedgerRepository(storeURL: directory.storeURL)
        await #expect(throws: LedgerStorageError.invalidStoredValue(entity: "账目", field: "来源、类型或时间")) {
            try await repository.updateEntry(id: original.id, draft: makeDraft(amount: 99999, note: "不应保存"))
        }
        _ = try await repository.createBook(name: "后续合法写入", id: UUID())
        let container = try LocalLedgerStore.makeContainer(at: directory.storeURL)
        let context = ModelContext(container)
        let record = try #require(context.fetch(FetchDescriptor<LedgerSchemaV1.EntryRecord>()).first)
        #expect(record.amountMinorUnits == original.amount.minorUnits)
        #expect(record.note == original.note)
        #expect(record.updatedAt == original.updatedAt)
        #expect(record.sourceRawValue == "unrecognized-source")
    }
}

private struct TestDirectory {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("YoloLedgerRepositoryTests-\(UUID())", isDirectory: true)

    var storeURL: URL { url.appendingPathComponent("ledger.store") }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

private func makeDraft(
    bookID: UUID = LedgerSeedData.defaultBook.id,
    categoryID: UUID? = nil,
    kind: LedgerEntryKind = .expense,
    amount: Int64,
    date: Date = Date(timeIntervalSince1970: 1_700_000_000),
    note: String = ""
) -> LedgerEntryDraft {
    LedgerEntryDraft(
        bookID: bookID,
        categoryID: categoryID ?? LedgerSeedData.categories.first { $0.kind == kind }!.id,
        kind: kind,
        amount: try! LedgerAmount(minorUnits: amount),
        date: date,
        note: note
    )
}

private func createFixture(at url: URL, amount: Int64) async throws -> LedgerEntry {
    let repository = try SwiftDataLedgerRepository(storeURL: url)
    return try await repository.createEntry(makeDraft(amount: amount, note: "午餐 🥟\n测试备注"))
}
