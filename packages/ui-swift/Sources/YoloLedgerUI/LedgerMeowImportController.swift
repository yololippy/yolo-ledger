import Foundation
import Observation
import YoloLedgerCore

public struct LedgerMeowImportDocument: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public struct LedgerMeowImportFileIssue: Equatable, Sendable, Identifiable {
    public let fileName: String
    public let line: Int
    public let column: LedgerMeowCSVColumn?
    public let code: LedgerMeowImportIssue.Code

    public var id: String {
        "\(fileName):\(line):\(column?.rawValue ?? "-"):\(description)"
    }

    public init(
        fileName: String,
        line: Int,
        column: LedgerMeowCSVColumn?,
        code: LedgerMeowImportIssue.Code
    ) {
        self.fileName = fileName
        self.line = line
        self.column = column
        self.code = code
    }

    public var description: String {
        let field = column.map { "\($0.rawValue)：" } ?? ""
        return field + Self.description(for: code)
    }

    private static func description(for code: LedgerMeowImportIssue.Code) -> String {
        switch code {
        case .invalidUTF8: "文件编码不是 UTF-8"
        case .missingHeader: "缺少表头"
        case .invalidHeader: "表头格式不正确"
        case .malformedCSV: "CSV 结构不正确"
        case .invalidFieldCount: "列数不正确"
        case .missingRequiredField: "必填内容为空"
        case .invalidTimestamp: "时间格式不正确"
        case .invalidAmount: "金额格式不正确"
        case .zeroAmount: "金额不能为零"
        case .amountOverflow: "金额超出支持范围"
        }
    }
}

public struct LedgerMeowCombinedPreview: Equatable, Sendable {
    public let fileCount: Int
    public let totalRowCount: Int
    public let validRecordCount: Int
    public let invalidRowCount: Int
    public let duplicateContentRecordCount: Int
    public let expenseRecordCount: Int
    public let incomeRecordCount: Int
    public let expenseTotalMinorUnits: Int64?
    public let incomeTotalMinorUnits: Int64?
    public let distinctBookCount: Int
    public let distinctCategoryCount: Int
    public let distinctAccountCount: Int
    public let distinctCurrencyCount: Int
    public let earliestDate: Date?
    public let latestDate: Date?
}

public struct LedgerMeowImportSelection: Equatable, Sendable {
    public let fileNames: [String]
    public let plans: [LedgerMeowImportPlan]
    public let issues: [LedgerMeowImportFileIssue]
    public let preview: LedgerMeowCombinedPreview

    public var records: [LedgerMeowImportRecord] {
        plans.flatMap(\.records)
    }

    public var canImport: Bool {
        issues.isEmpty && !records.isEmpty
    }
}

public struct LedgerMeowImportResult: Equatable, Sendable {
    public let importedRecordCount: Int
    public let skippedDuplicateRecordCount: Int
    public let createdBookCount: Int
    public let createdCategoryCount: Int
    public let importedExpenseCount: Int
    public let importedIncomeCount: Int
    public let importedExpenseTotalText: String
    public let importedIncomeTotalText: String
    public let backupName: String

    public init(
        importedRecordCount: Int,
        skippedDuplicateRecordCount: Int,
        createdBookCount: Int = 0,
        createdCategoryCount: Int = 0,
        importedExpenseCount: Int = 0,
        importedIncomeCount: Int = 0,
        importedExpenseTotalText: String = "¥0.00",
        importedIncomeTotalText: String = "¥0.00",
        backupName: String
    ) {
        self.importedRecordCount = importedRecordCount
        self.skippedDuplicateRecordCount = skippedDuplicateRecordCount
        self.createdBookCount = createdBookCount
        self.createdCategoryCount = createdCategoryCount
        self.importedExpenseCount = importedExpenseCount
        self.importedIncomeCount = importedIncomeCount
        self.importedExpenseTotalText = importedExpenseTotalText
        self.importedIncomeTotalText = importedIncomeTotalText
        self.backupName = backupName
    }
}

@MainActor
@Observable
public final class LedgerMeowImportController {
    public typealias ImportAction = @MainActor @Sendable ([LedgerMeowImportPlan]) async throws -> LedgerMeowImportResult
    public typealias DocumentSelectionAction = @MainActor @Sendable () async throws -> [LedgerMeowImportDocument]

    public private(set) var selection: LedgerMeowImportSelection?
    public private(set) var isReadingFiles = false
    public private(set) var isImporting = false
    public private(set) var result: LedgerMeowImportResult?
    public private(set) var failureMessage: String?
    public private(set) var successfulImportRevision = 0
    public var isFileImporterPresented = false
    public var isReviewPresented = false

    private var importAction: ImportAction?
    private var documentSelectionAction: DocumentSelectionAction?

    public init() {}

    public func installImportAction(_ action: @escaping ImportAction) {
        importAction = action
    }

    public func installDocumentSelectionAction(_ action: @escaping DocumentSelectionAction) {
        documentSelectionAction = action
    }

    public func requestFileSelection() {
        guard !isReadingFiles, !isImporting else { return }
        failureMessage = nil
        result = nil
        isReviewPresented = false
        if let documentSelectionAction {
            isReadingFiles = true
            isReviewPresented = true
            Task {
                do {
                    let documents = try await documentSelectionAction()
                    prepare(documents: documents, calendar: .current, timeZone: .current)
                } catch {
                    selection = nil
                    failureMessage = "无法读取所选 CSV 文件，请确认文件仍可访问后重新选择。"
                }
                isReadingFiles = false
            }
            return
        }
        isFileImporterPresented = true
    }

    public func dismissFileImporter() {
        isFileImporterPresented = false
    }

    public func handleFileSelection(
        _ result: Result<[URL], any Error>,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) async {
        isFileImporterPresented = false
        switch result {
        case let .success(urls):
            guard !urls.isEmpty else { return }
            isReadingFiles = true
            isReviewPresented = true
            failureMessage = nil
            self.result = nil
            do {
                let documents = try await Task.detached(priority: .userInitiated) {
                    try Self.readDocuments(at: urls)
                }.value
                prepare(documents: documents, calendar: calendar, timeZone: timeZone)
            } catch {
                selection = nil
                failureMessage = "无法读取所选 CSV 文件，请确认文件仍可访问后重新选择。"
                isReviewPresented = true
            }
            isReadingFiles = false
        case .failure:
            failureMessage = "没有完成文件选择，请重新选择喵喵记账导出的 CSV。"
            isReviewPresented = true
        }
    }

    public func prepare(
        documents: [LedgerMeowImportDocument],
        calendar: Calendar,
        timeZone: TimeZone
    ) {
        let parsed = documents.map { document in
            (
                document.name,
                LedgerMeowCSVParser.parse(
                    data: document.data,
                    calendar: calendar,
                    timeZone: timeZone
                )
            )
        }
        let plans = parsed.map(\.1)
        let records = plans.flatMap(\.records)
        let issues = parsed.flatMap { fileName, plan in
            plan.issues.map {
                LedgerMeowImportFileIssue(
                    fileName: fileName,
                    line: $0.line,
                    column: $0.column,
                    code: $0.code
                )
            }
        }
        let expenseRecords = records.filter { $0.kind == .expense }
        let incomeRecords = records.filter { $0.kind == .income }
        let dates = records.map(\.date)
        selection = LedgerMeowImportSelection(
            fileNames: parsed.map(\.0),
            plans: plans,
            issues: issues,
            preview: LedgerMeowCombinedPreview(
                fileCount: documents.count,
                totalRowCount: plans.reduce(0) { $0 + $1.preview.totalRowCount },
                validRecordCount: records.count,
                invalidRowCount: Set(issues.map { "\($0.fileName):\($0.line)" }).count,
                duplicateContentRecordCount: records.count - Set(records.map(\.fields)).count,
                expenseRecordCount: expenseRecords.count,
                incomeRecordCount: incomeRecords.count,
                expenseTotalMinorUnits: Self.exactTotal(expenseRecords),
                incomeTotalMinorUnits: Self.exactTotal(incomeRecords),
                distinctBookCount: Set(records.map(\.fields.book)).count,
                distinctCategoryCount: Set(records.map(\.fields.category)).count,
                distinctAccountCount: Set(records.map(\.fields.account)).count,
                distinctCurrencyCount: Set(records.map(\.fields.currency)).count,
                earliestDate: dates.min(),
                latestDate: dates.max()
            )
        )
        failureMessage = nil
        result = nil
        isReviewPresented = true
    }

    public func importSelection() async {
        guard !isImporting,
              let selection,
              selection.canImport,
              let importAction
        else { return }
        isImporting = true
        failureMessage = nil
        result = nil
        do {
            let result = try await importAction(selection.plans)
            self.result = result
            successfulImportRevision += 1
        } catch {
            failureMessage = "导入未完成，本地原数据保持不变。请检查存储空间后重试。"
        }
        isImporting = false
    }

    public func cancelReview() {
        guard !isImporting else { return }
        isReviewPresented = false
        selection = nil
        result = nil
        failureMessage = nil
    }

    private nonisolated static func readDocuments(at urls: [URL]) throws -> [LedgerMeowImportDocument] {
        try urls.map { url in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return LedgerMeowImportDocument(
                name: url.lastPathComponent,
                data: try Data(contentsOf: url, options: .mappedIfSafe)
            )
        }
    }

    private static func exactTotal(_ records: [LedgerMeowImportRecord]) -> Int64? {
        var total: Int64 = 0
        for record in records {
            let result = total.addingReportingOverflow(record.amount.minorUnits)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }
}
