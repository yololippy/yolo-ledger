import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct LedgerAppModelTests {
    @Test
    func initialLoadUsesRepositoryAndCanRetryFailure() async {
        let repository = TestLedgerRepository()
        await repository.setReadFailure(true)
        let model = LedgerAppModel(repository: repository)
        await model.refresh()
        #expect(!model.hasLoaded)
        #expect(model.loadError != nil)
        #expect(!model.isLoading)

        await repository.setReadFailure(false)
        await model.refresh()
        #expect(model.hasLoaded)
        #expect(model.loadError == nil)
        #expect(model.selectedBookID == LedgerSeedData.defaultBook.id)
        #expect(model.categories == LedgerSeedData.categories)
    }

    @Test
    func savingEditingAndDeletingRefreshesSharedEntriesAndSummary() async throws {
        let model = LedgerAppModel(repository: TestLedgerRepository())
        await model.refresh()
        let id = UUID()
        #expect(await model.saveEntry(try draft("12.34"), editingID: nil, creationID: id))
        #expect(model.selectedEntries.map(\.id) == [id])
        #expect(try model.monthSummary().expenseMinorUnits == 1234)

        #expect(await model.saveEntry(try draft("23.45"), editingID: id, creationID: UUID()))
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.amount.minorUnits == 2345)
        #expect(try model.monthSummary().expenseMinorUnits == 2345)

        #expect(await model.deleteEntry(id))
        #expect(model.selectedEntries.isEmpty)
        #expect(try model.monthSummary() == .zero)
    }

    @Test
    func failedWriteDoesNotReplaceSavedValues() async throws {
        let repository = TestLedgerRepository()
        let model = LedgerAppModel(repository: repository)
        await model.refresh()
        let id = UUID()
        #expect(await model.saveEntry(try draft("12.34"), editingID: nil, creationID: id))
        await repository.setWriteFailure(true)

        #expect(!(await model.saveEntry(try draft("99.00"), editingID: id, creationID: UUID())))
        #expect(model.operationError != nil)
        #expect(model.entries.first?.amount.minorUnits == 1234)
        #expect(!(await model.deleteEntry(id)))
        #expect(model.entries.map(\.id) == [id])
        #expect(!model.isSaving)
    }

    @Test
    func successfulWriteWithFailedRefreshIsStillSuccessfulAndNotReissued() async throws {
        let repository = TestLedgerRepository()
        let model = LedgerAppModel(repository: repository)
        await model.refresh()
        await repository.failReadsAfterNextWrite()
        let id = UUID()

        #expect(await model.saveEntry(try draft("12.34"), editingID: nil, creationID: id))
        #expect(model.operationError == nil)
        #expect(model.loadError?.contains("已保存") == true)
        #expect(model.entries.map(\.id) == [id])
        #expect(await repository.createCount == 1)

        await repository.setReadFailure(false)
        await model.refresh()
        #expect(model.loadError == nil)
        #expect(model.entries.map(\.id) == [id])
        #expect(await repository.createCount == 1)
    }

    @Test
    func aPendingSaveRejectsDuplicateSubmission() async throws {
        let repository = TestLedgerRepository()
        let model = LedgerAppModel(repository: repository)
        await model.refresh()
        await repository.holdNextCreate()
        let content = try draft("12.34")
        let first = Task { await model.saveEntry(content, editingID: nil, creationID: UUID()) }
        guard await repository.waitForCreateGate() else {
            Issue.record("The first create did not enter its controlled delay.")
            await repository.releaseCreate()
            _ = await first.value
            return
        }

        #expect(model.isSaving)
        #expect(!(await model.saveEntry(content, editingID: nil, creationID: UUID())))
        await repository.releaseCreate()
        #expect(await first.value)
        #expect(await repository.createCount == 1)
        #expect(model.entries.count == 1)
        #expect(!model.isSaving)
    }

    @Test
    func bookCreationRenameAndSelectionScopesAllEntriesAndTotals() async throws {
        let model = LedgerAppModel(repository: TestLedgerRepository())
        await model.refresh()
        let original = LedgerSeedData.defaultBook.id
        #expect(await model.saveEntry(try draft("10.00"), editingID: nil, creationID: UUID()))
        let newBook = UUID()
        #expect(await model.saveBook(name: "  旅行  ", editingID: nil, creationID: newBook))
        #expect(model.selectedBook?.name == "旅行")
        #expect(model.selectedEntries.isEmpty)
        #expect(try model.monthSummary() == .zero)

        #expect(await model.saveBook(name: "旅行新名", editingID: newBook, creationID: UUID()))
        #expect(model.selectedBook?.id == newBook)
        #expect(model.selectedBook?.name == "旅行新名")
        #expect(model.books.count == 2)

        model.selectBook(original)
        #expect(model.selectedEntries.count == 1)
        #expect(try model.monthSummary().expenseMinorUnits == 1000)
        #expect(await model.saveBook(name: "旅行再命名", editingID: newBook, creationID: UUID()))
        #expect(model.selectedBookID == original)
        await model.refresh()
        #expect(model.selectedBookID == original)
    }

    @Test
    func cancelledOlderRefreshCannotReplaceNewSnapshot() async {
        let repository = TestLedgerRepository()
        let model = LedgerAppModel(repository: repository)
        await model.refresh()
        await repository.holdNextBookRead()
        let older = Task { await model.refresh() }
        guard await repository.waitForBookReadGate() else {
            Issue.record("The first book read did not enter its controlled delay.")
            await repository.releaseBookRead()
            await older.value
            return
        }
        older.cancel()
        let newest = LedgerBook(id: UUID(), name: "新快照")
        await repository.replaceBooks([newest])
        await model.refresh()
        await repository.releaseBookRead()
        await older.value

        #expect(model.books == [newest])
        #expect(model.selectedBookID == newest.id)
        #expect(model.loadError == nil)
        #expect(!model.isLoading)
    }

    private func draft(_ amount: String) throws -> LedgerEntryDraft {
        LedgerEntryDraft(
            bookID: LedgerSeedData.defaultBook.id,
            categoryID: LedgerSeedData.categories[0].id,
            kind: .expense,
            amount: try LedgerAmount(input: amount),
            date: Date(), note: "测试备注"
        )
    }

    @Test
    func calendarScopesDaysAndMonthsAndRefreshPreservesBrowsing() async throws {
        let model = LedgerAppModel(repository: TestLedgerRepository())
        await model.refresh()
        let month = try LedgerDateRanges.range(for: .month, containing: Date())
        let firstDay = Calendar.current.date(byAdding: .hour, value: 12, to: month.start)!
        let secondDay = Calendar.current.date(byAdding: .day, value: 1, to: firstDay)!
        for (date, amount) in [(firstDay, "3.00"), (secondDay, "7.00")] {
            var content = try draft(amount)
            content = LedgerEntryDraft(bookID: content.bookID, categoryID: content.categoryID, kind: content.kind, amount: content.amount, date: date, note: "日期筛选")
            #expect(await model.saveEntry(content, editingID: nil, creationID: UUID()))
        }
        #expect(model.monthEntries.count == 2)
        model.selectDay(firstDay)
        #expect(model.calendarEntries.count == 1)
        #expect(try model.daySummary(firstDay).expenseMinorUnits == 300)
        model.selectDay(secondDay)
        #expect(model.calendarEntries.first?.amount.minorUnits == 700)
        model.moveMonth(by: -1)
        let previous = model.displayedMonth
        #expect(model.selectedDay == nil)
        #expect(model.monthEntries.isEmpty)
        await model.refresh()
        #expect(model.displayedMonth == previous)
        model.moveMonth(by: 1)
        #expect(try model.monthSummary().expenseMinorUnits == 1000)
        model.selectDay(firstDay)
        model.selectDay(firstDay)
        #expect(model.calendarEntries.count == 2)
    }

    @Test
    func selectingMonthNormalizesToMonthStartAndClearsDayFilter() throws {
        let model = LedgerAppModel(repository: TestLedgerRepository())
        let calendar = Calendar.current
        let target = calendar.date(from: DateComponents(year: 2024, month: 2, day: 20, hour: 18))!
        model.selectDay(Date())
        model.selectMonth(target)

        let expected = try LedgerDateRanges.range(for: .month, containing: target).start
        #expect(model.displayedMonth == expected)
        #expect(model.selectedDay == nil)
    }

    @Test
    func recentNotesUseFIFOOrderAndDiscardTheOldestPastTheLimit() async throws {
        let repository = TestLedgerRepository()
        let model = LedgerAppModel(repository: repository)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let categoryID = LedgerSeedData.categories[0].id
        let otherCategoryID = LedgerSeedData.categories[1].id
        let notes = ["午饭", "打车", "   ", "  午饭\n", "买菜"]
        let entries = try notes.enumerated().map { index, note in
            let content = LedgerEntryDraft(
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: categoryID,
                kind: .expense,
                amount: try LedgerAmount(input: "10.00"),
                date: base,
                note: note
            )
            let timestamp = base.addingTimeInterval(TimeInterval(index))
            return LedgerEntry(
                id: UUID(),
                draft: content,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
        let otherCategoryEntry = LedgerEntry(
            id: UUID(),
            draft: LedgerEntryDraft(
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: otherCategoryID,
                kind: .expense,
                amount: try LedgerAmount(input: "20.00"),
                date: base,
                note: "地铁"
            ),
            createdAt: base,
            updatedAt: base
        )
        await repository.replaceEntries(entries + [otherCategoryEntry])
        await model.refresh()

        #expect(model.recentNotes(categoryID: categoryID) == ["午饭", "打车", "买菜"])
        #expect(model.recentNotes(categoryID: otherCategoryID) == ["地铁"])
        #expect(model.recentNotes(categoryID: categoryID, limit: 2) == ["打车", "买菜"])
        #expect(model.recentNotes(categoryID: categoryID, limit: 0).isEmpty)

        let manyEntries = try (0..<22).map { index in
            let content = LedgerEntryDraft(
                bookID: LedgerSeedData.defaultBook.id,
                categoryID: categoryID,
                kind: .expense,
                amount: try LedgerAmount(input: "10.00"),
                date: base,
                note: "备注 \(index)"
            )
            let timestamp = base.addingTimeInterval(TimeInterval(index))
            return LedgerEntry(
                id: UUID(),
                draft: content,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
        await repository.replaceEntries(manyEntries)
        await model.refresh()

        #expect(model.recentNotes(categoryID: categoryID).count == 20)
        #expect(model.recentNotes(categoryID: categoryID).first == "备注 2")
        #expect(model.recentNotes(categoryID: categoryID).last == "备注 21")
    }

    @Test
    func savingFromAnotherMonthOrDayMakesTheSavedRecordVisible() async throws {
        let model = LedgerAppModel(repository: TestLedgerRepository())
        await model.refresh()
        model.moveMonth(by: -2)
        model.selectDay(model.displayedMonth)
        let id = UUID()
        #expect(await model.saveEntry(try draft("15.00"), editingID: nil, creationID: id))
        #expect(model.selectedDay == nil)
        #expect(model.calendarEntries.map(\.id) == [id])
        let older = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let original = try draft("25.00")
        let changed = LedgerEntryDraft(bookID: original.bookID, categoryID: original.categoryID, kind: original.kind, amount: original.amount, date: older, note: "移到上月")
        model.selectDay(Date())
        #expect(await model.saveEntry(changed, editingID: id, creationID: UUID()))
        #expect(model.selectedDay == nil)
        #expect(model.calendarEntries.map(\.id) == [id])
        #expect(try model.monthSummary().expenseMinorUnits == 2500)
    }
}

private actor TestLedgerRepository: LedgerRepository {
    private var books = LedgerSeedData.books
    private var entries: [LedgerEntry] = []
    private var readFailure = false
    private var writeFailure = false
    private var failAfterWrite = false
    private var holdsCreate = false
    private var holdsBookRead = false
    private var createGate: CheckedContinuation<Void, Never>?
    private var readGate: CheckedContinuation<Void, Never>?
    private(set) var createCount = 0

    func setReadFailure(_ value: Bool) { readFailure = value }
    func setWriteFailure(_ value: Bool) { writeFailure = value }
    func failReadsAfterNextWrite() { failAfterWrite = true }
    func holdNextCreate() { holdsCreate = true }
    func holdNextBookRead() { holdsBookRead = true }
    func replaceBooks(_ value: [LedgerBook]) { books = value }
    func replaceEntries(_ value: [LedgerEntry]) { entries = value }
    func releaseCreate() { createGate?.resume(); createGate = nil }
    func releaseBookRead() { readGate?.resume(); readGate = nil }

    func waitForCreateGate() async -> Bool {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while createGate == nil, clock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return createGate != nil
    }

    func waitForBookReadGate() async -> Bool {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while readGate == nil, clock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return readGate != nil
    }

    func fetchBooks() async throws -> [LedgerBook] {
        if readFailure { throw TestRepositoryError.readFailed }
        let result = books
        if holdsBookRead {
            holdsBookRead = false
            await withCheckedContinuation { readGate = $0 }
        }
        return result
    }

    func fetchCategories() async throws -> [LedgerCategory] {
        if readFailure { throw TestRepositoryError.readFailed }
        return LedgerSeedData.categories
    }

    func fetchEntries(bookID: UUID?) async throws -> [LedgerEntry] {
        if readFailure { throw TestRepositoryError.readFailed }
        return entries.filter { bookID == nil || $0.bookID == bookID }
    }

    func createEntry(_ draft: LedgerEntryDraft, id: UUID) async throws -> LedgerEntry {
        createCount += 1
        if holdsCreate {
            holdsCreate = false
            await withCheckedContinuation { createGate = $0 }
        }
        if writeFailure { throw TestRepositoryError.writeFailed }
        guard !entries.contains(where: { $0.id == id }) else { throw LedgerError.duplicateIdentifier(id) }
        let entry = LedgerEntry(id: id, draft: draft, createdAt: Date(), updatedAt: Date())
        entries.append(entry)
        if failAfterWrite { readFailure = true; failAfterWrite = false }
        return entry
    }

    func updateEntry(id: UUID, draft: LedgerEntryDraft) async throws -> LedgerEntry {
        if writeFailure { throw TestRepositoryError.writeFailed }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw LedgerError.entryNotFound(id) }
        let entry = LedgerEntry(id: id, draft: draft, createdAt: entries[index].createdAt, updatedAt: Date())
        entries[index] = entry
        return entry
    }

    func deleteEntry(id: UUID) async throws {
        if writeFailure { throw TestRepositoryError.writeFailed }
        entries.removeAll { $0.id == id }
    }

    func createBook(name: String, id: UUID) async throws -> LedgerBook {
        if writeFailure { throw TestRepositoryError.writeFailed }
        let book = LedgerBook(id: id, name: name)
        books.append(book)
        return book
    }

    func renameBook(id: UUID, name: String) async throws -> LedgerBook {
        if writeFailure { throw TestRepositoryError.writeFailed }
        guard let index = books.firstIndex(where: { $0.id == id }) else { throw LedgerError.bookNotFound(id) }
        let book = LedgerBook(id: id, name: name)
        books[index] = book
        return book
    }
}

private enum TestRepositoryError: LocalizedError {
    case readFailed, writeFailed
    var errorDescription: String? {
        switch self {
        case .readFailed: "读取暂时失败。"
        case .writeFailed: "保存暂时失败。"
        }
    }
}
