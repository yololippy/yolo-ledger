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
    private(set) var referenceDate = Date()
    private(set) var displayedMonth = Date()
    private(set) var selectedDay: Date?

    private let repository: any LedgerRepository
    private var loadGeneration = 0

    init(repository: any LedgerRepository) {
        self.repository = repository
    }

    var selectedBook: LedgerBook? { books.first { $0.id == selectedBookID } }
    var selectedEntries: [LedgerEntry] { entries.filter { $0.bookID == selectedBookID } }
    var monthEntries: [LedgerEntry] {
        guard let range = try? LedgerDateRanges.range(for: .month, containing: displayedMonth) else { return [] }
        return selectedEntries.filter { range.contains($0.date) }
    }

    func monthSummary() throws -> LedgerSummary {
        let range = try LedgerDateRanges.range(for: .month, containing: displayedMonth)
        return try LedgerSummary(entries: selectedEntries, dateRange: range)
    }

    var calendarEntries: [LedgerEntry] {
        guard let selectedDay, let range = try? LedgerDateRanges.range(for: .day, containing: selectedDay) else { return monthEntries }
        return monthEntries.filter { range.contains($0.date) }
    }

    func selectDay(_ date: Date) {
        selectedDay = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } == true ? nil : date
    }

    func moveMonth(by offset: Int) {
        guard let date = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        selectMonth(date)
    }

    func selectMonth(_ date: Date) {
        guard let range = try? LedgerDateRanges.range(for: .month, containing: date) else { return }
        displayedMonth = range.start
        selectedDay = nil
    }

    func daySummary(_ day: Date) throws -> LedgerSummary {
        try LedgerSummary(entries: selectedEntries, dateRange: LedgerDateRanges.range(for: .day, containing: day))
    }

    func selectBook(_ id: UUID) {
        guard books.contains(where: { $0.id == id }) else { return }
        selectedBookID = id
    }

    func categoryName(_ id: UUID) -> String {
        categories.first { $0.id == id }?.name ?? "未找到分类"
    }

    func bookName(_ id: UUID) -> String {
        books.first { $0.id == id }?.name ?? "未找到账本"
    }

    func refresh() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        loadError = nil
        referenceDate = Date()
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let books = try await repository.fetchBooks()
            let categories = try await repository.fetchCategories()
            let entries = try await repository.fetchEntries(bookID: nil)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            self.books = books
            self.categories = categories
            self.entries = entries
            if !books.contains(where: { $0.id == selectedBookID }) {
                selectedBookID = books.first?.id
            }
            hasLoaded = true
        } catch is CancellationError {
            // A newer refresh or the next appearance will own the snapshot.
        } catch {
            guard generation == loadGeneration else { return }
            loadError = Self.message(for: error)
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
            selectedBookID = saved.bookID
            if let month = try? LedgerDateRanges.range(for: .month, containing: saved.date) { displayedMonth = month.start }
            if let selectedDay, !Calendar.current.isDate(selectedDay, inSameDayAs: saved.date) { self.selectedDay = nil }
            await refresh()
            if let message = loadError { loadError = "账目已保存，但刷新失败：\(message)" }
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
            await refresh()
            if let message = loadError { loadError = "账目已删除，但刷新失败：\(message)" }
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
}

extension LedgerEntryKind {
    var title: String { self == .expense ? "支出" : "收入" }
}
