import Foundation
import Observation
import YoloLedgerCore

@MainActor
@Observable
final class LedgerAppModel {
    private(set) var books: [LedgerBook] = []
    private(set) var categories: [LedgerCategory] = []
    private(set) var entries: [LedgerEntry] = []
    private(set) var selectedBookID: UUID?
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var loadError: String?
    private(set) var operationError: String?
    private(set) var syncState: LedgerSyncState
    private(set) var statisticsRevision = 0
    private(set) var referenceDate = Date()
    private(set) var displayedMonth = Date()
    private(set) var selectedDay: Date?

    private let repository: any LedgerRepository
    private let onLocalMutation: @MainActor @Sendable () -> Void
    private var loadGeneration = 0
    private var entryLoadGeneration = 0
    private var recentNotesByCategory: [UUID: [String]] = [:]

    init(
        repository: any LedgerRepository,
        onLocalMutation: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.repository = repository
        self.onLocalMutation = onLocalMutation
        self.syncState = repository.currentSyncState()
    }

    var selectedBook: LedgerBook? { books.first { $0.id == selectedBookID } }
    var selectedEntries: [LedgerEntry] { entries.filter { $0.bookID == selectedBookID } }
    func recentNotes(categoryID: UUID, limit: Int = 20) -> [String] {
        guard limit > 0 else { return [] }
        if let cached = recentNotesByCategory[categoryID] {
            return Array(cached.suffix(limit))
        }
        return Self.recentNotes(in: entries, categoryID: categoryID, limit: limit)
    }

    func loadRecentNotes(categoryID: UUID, limit: Int = 20) async {
        guard limit > 0 else {
            recentNotesByCategory[categoryID] = []
            return
        }
        do {
            recentNotesByCategory[categoryID] = try await repository.fetchRecentNotes(
                categoryID: categoryID,
                limit: limit
            )
        } catch {
            // Note suggestions are optional; entry editing must remain available when they fail.
        }
    }

    private static func recentNotes(
        in entries: [LedgerEntry],
        categoryID: UUID,
        limit: Int
    ) -> [String] {
        var seen = Set<String>()
        let sortedEntries = entries.filter { $0.categoryID == categoryID }.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt < right.updatedAt }
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            if left.date != right.date { return left.date < right.date }
            return left.id.uuidString < right.id.uuidString
        }

        var notes: [String] = []
        for entry in sortedEntries {
            let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            let key = note.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { continue }
            notes.append(note)
        }
        return Array(notes.suffix(limit))
    }

    var monthEntries: [LedgerEntry] {
        guard let range = try? LedgerDateRanges.range(for: .month, containing: displayedMonth) else { return [] }
        return selectedEntries.filter { range.contains($0.date) }
    }

    func monthSummary() throws -> LedgerSummary {
        try monthSummary(containing: displayedMonth)
    }

    func monthSummary(containing date: Date) throws -> LedgerSummary {
        let range = try LedgerDateRanges.range(for: .month, containing: date)
        return try LedgerSummary(entries: selectedEntries, dateRange: range)
    }

    var calendarEntries: [LedgerEntry] {
        guard let selectedDay, let range = try? LedgerDateRanges.range(for: .day, containing: selectedDay) else { return monthEntries }
        return monthEntries.filter { range.contains($0.date) }
    }

    func selectDay(_ date: Date) {
        selectedDay = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ? nil : date
    }

    func moveMonth(by offset: Int) async {
        guard let date = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        await selectMonth(date)
    }

    func selectMonth(_ date: Date) async {
        guard let range = try? LedgerDateRanges.range(for: .month, containing: date) else { return }
        displayedMonth = range.start
        selectedDay = nil
        await refreshVisibleEntries()
    }

    func daySummary(_ day: Date) throws -> LedgerSummary {
        try LedgerSummary(entries: selectedEntries, dateRange: LedgerDateRanges.range(for: .day, containing: day))
    }

    func selectBook(_ id: UUID) async {
        guard books.contains(where: { $0.id == id }) else { return }
        selectedBookID = id
        selectedDay = nil
        await refreshVisibleEntries()
    }

    func categoryName(_ id: UUID) -> String {
        categories.first { $0.id == id }?.name ?? "未找到分类"
    }

    func bookName(_ id: UUID) -> String {
        books.first { $0.id == id }?.name ?? "未找到账本"
    }

    func refresh() async {
        syncState = repository.currentSyncState()
        loadGeneration &+= 1
        let generation = loadGeneration
        entryLoadGeneration &+= 1
        let entryGeneration = entryLoadGeneration
        isLoading = true
        loadError = nil
        referenceDate = Date()
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            async let booksRequest = repository.fetchBooks()
            async let categoriesRequest = repository.fetchCategories()
            let (books, categories) = try await (booksRequest, categoriesRequest)
            let targetBookID = books.contains(where: { $0.id == selectedBookID })
                ? selectedBookID
                : books.first?.id
            let entryRange = try Self.entryWindow(containing: displayedMonth)
            let entries: [LedgerEntry] = if let targetBookID {
                try await repository.fetchEntries(bookID: targetBookID, dateRange: entryRange)
            } else {
                []
            }
            try Task.checkCancellation()
            guard generation == loadGeneration, entryGeneration == entryLoadGeneration else { return }
            self.books = books
            self.categories = categories
            self.entries = entries
            selectedBookID = targetBookID
            recentNotesByCategory.removeAll(keepingCapacity: true)
            syncState = repository.currentSyncState()
            hasLoaded = true
            statisticsRevision &+= 1
        } catch is CancellationError {
            // A newer refresh or the next appearance will own the snapshot.
        } catch {
            guard generation == loadGeneration else { return }
            loadError = Self.message(for: error)
        }
    }

    func refreshVisibleEntries() async {
        guard let selectedBookID else {
            entries = []
            return
        }
        entryLoadGeneration &+= 1
        let generation = entryLoadGeneration
        let displayedMonth = displayedMonth
        do {
            let range = try Self.entryWindow(containing: displayedMonth)
            let entries = try await repository.fetchEntries(
                bookID: selectedBookID,
                dateRange: range
            )
            try Task.checkCancellation()
            guard generation == entryLoadGeneration,
                  self.selectedBookID == selectedBookID,
                  Calendar.current.isDate(self.displayedMonth, equalTo: displayedMonth, toGranularity: .month)
            else { return }
            self.entries = entries
        } catch is CancellationError {
            // A newer book or month selection owns the visible snapshot.
        } catch {
            guard generation == entryLoadGeneration else { return }
            operationError = Self.message(for: error)
        }
    }

    func observeRepositoryUpdates() async {
        for await _ in repository.updates() {
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func saveEntry(_ draft: LedgerEntryDraft, editingID: UUID?, creationID: UUID) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        operationError = nil
        defer { isSaving = false }

        do {
            try LedgerValidation.validate(draft, books: books, categories: categories)
            let saved: LedgerEntry
            if let editingID {
                saved = try await repository.updateEntry(id: editingID, draft: draft)
            } else {
                saved = try await repository.createEntry(draft, id: creationID)
            }
            entries.removeAll { $0.id == saved.id }
            entries.append(saved)
            sortEntries()
            recentNotesByCategory.removeValue(forKey: saved.categoryID)
            selectedBookID = saved.bookID
            if let month = try? LedgerDateRanges.range(for: .month, containing: saved.date) { displayedMonth = month.start }
            if let selectedDay, !Calendar.current.isDate(selectedDay, inSameDayAs: saved.date) { self.selectedDay = nil }
            await refresh()
            if let message = loadError { loadError = "账目已保存，但刷新失败：\(message)" }
            onLocalMutation()
            // The write succeeded even if the subsequent read could not refresh.
            return true
        } catch {
            operationError = Self.message(for: error)
            return false
        }
    }

    func deleteEntry(_ id: UUID) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        operationError = nil
        defer { isSaving = false }

        do {
            try await repository.deleteEntry(id: id)
            entries.removeAll { $0.id == id }
            recentNotesByCategory.removeAll(keepingCapacity: true)
            await refresh()
            if let message = loadError { loadError = "账目已删除，但刷新失败：\(message)" }
            onLocalMutation()
            return true
        } catch {
            operationError = Self.message(for: error)
            return false
        }
    }

    func saveBook(name: String, editingID: UUID?, creationID: UUID) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        operationError = nil
        defer { isSaving = false }

        do {
            let normalized = try LedgerValidation.normalizedName(name)
            let saved: LedgerBook
            if let editingID {
                saved = try await repository.renameBook(id: editingID, name: normalized)
            } else {
                saved = try await repository.createBook(name: normalized, id: creationID)
            }
            if let index = books.firstIndex(where: { $0.id == saved.id }) {
                books[index] = saved
            } else {
                books.append(saved)
            }
            if editingID == nil { selectedBookID = saved.id }
            await refresh()
            if let message = loadError { loadError = "账本已保存，但刷新失败：\(message)" }
            onLocalMutation()
            return true
        } catch {
            operationError = Self.message(for: error)
            return false
        }
    }

    static func message(for error: any Error) -> String {
        if let error = error as? any LocalizedError, let description = error.errorDescription {
            return description
        }
        return "操作未完成，请稍后重试。"
    }

    private func sortEntries() {
        entries.sort { left, right in
            if left.date != right.date { return left.date > right.date }
            if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
            return left.id.uuidString < right.id.uuidString
        }
    }

    /// Preload the displayed month and its two animated neighbors without retaining all history.
    private static func entryWindow(containing date: Date) throws -> LedgerDateRange {
        let calendar = Calendar.current
        let month = try LedgerDateRanges.range(for: .month, containing: date, calendar: calendar)
        guard let start = calendar.date(byAdding: .month, value: -1, to: month.start),
              let end = calendar.date(byAdding: .month, value: 2, to: month.start)
        else { throw LedgerError.invalidDateRange }
        return try LedgerDateRange(start: start, end: end)
    }
}

extension LedgerEntryKind {
    var title: String { self == .expense ? "支出" : "收入" }
}
