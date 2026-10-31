import CryptoKit
import Foundation

public enum LedgerMeowCSVColumn: String, CaseIterable, Codable, Sendable {
    case category = "分类"
    case timestamp = "时间"
    case amount = "金额"
    case account = "账户"
    case book = "账本"
    case currency = "货币"
    case note = "备注"
}

/// The seven decoded source values are retained exactly, including whitespace and embedded newlines.
public struct LedgerMeowSourceFields: Equatable, Hashable, Codable, Sendable {
    public let category: String
    public let timestamp: String
    public let amount: String
    public let account: String
    public let book: String
    public let currency: String
    public let note: String

    public init(
        category: String,
        timestamp: String,
        amount: String,
        account: String,
        book: String,
        currency: String,
        note: String
    ) {
        self.category = category
        self.timestamp = timestamp
        self.amount = amount
        self.account = account
        self.book = book
        self.currency = currency
        self.note = note
    }
}

public struct LedgerMeowImportRecord: Equatable, Sendable {
    /// Physical line on which this RFC 4180 record begins. Quoted fields may span later lines.
    public let sourceLine: Int
    public let fields: LedgerMeowSourceFields
    public let kind: LedgerEntryKind
    public let amount: LedgerAmount
    public let date: Date
    public let importMetadata: LedgerEntryImportMetadata

    public init(
        sourceLine: Int,
        fields: LedgerMeowSourceFields,
        kind: LedgerEntryKind,
        amount: LedgerAmount,
        date: Date,
        importMetadata: LedgerEntryImportMetadata
    ) {
        self.sourceLine = sourceLine
        self.fields = fields
        self.kind = kind
        self.amount = amount
        self.date = date
        self.importMetadata = importMetadata
    }
}

public struct LedgerMeowImportIssue: Error, Equatable, Sendable {
    public enum Code: Error, Equatable, Sendable {
        case invalidUTF8
        case missingHeader
        case invalidHeader
        case malformedCSV
        case invalidFieldCount(expected: Int, actual: Int)
        case missingRequiredField
        case invalidTimestamp
        case invalidAmount
        case zeroAmount
        case amountOverflow
    }

    /// Physical source line. File-level encoding and header failures use line 1.
    public let line: Int
    public let column: LedgerMeowCSVColumn?
    public let code: Code

    public init(line: Int, column: LedgerMeowCSVColumn? = nil, code: Code) {
        self.line = line
        self.column = column
        self.code = code
    }
}

public struct LedgerMeowImportPreview: Equatable, Sendable {
    public let totalRowCount: Int
    public let validRecordCount: Int
    public let invalidRowCount: Int
    public let expenseRecordCount: Int
    public let incomeRecordCount: Int
    /// Additional rows whose seven decoded source values exactly match an earlier valid row.
    public let duplicateContentRecordCount: Int
    /// Nil only if the corresponding exact minor-unit total exceeds Int64.
    public let expenseTotalMinorUnits: Int64?
    public let incomeTotalMinorUnits: Int64?
    public let distinctBookCount: Int
    public let distinctCategoryCount: Int
    public let distinctAccountCount: Int
    public let distinctCurrencyCount: Int

    public init(
        totalRowCount: Int,
        validRecordCount: Int,
        invalidRowCount: Int,
        expenseRecordCount: Int,
        incomeRecordCount: Int,
        duplicateContentRecordCount: Int,
        expenseTotalMinorUnits: Int64?,
        incomeTotalMinorUnits: Int64?,
        distinctBookCount: Int,
        distinctCategoryCount: Int,
        distinctAccountCount: Int,
        distinctCurrencyCount: Int
    ) {
        self.totalRowCount = totalRowCount
        self.validRecordCount = validRecordCount
        self.invalidRowCount = invalidRowCount
        self.expenseRecordCount = expenseRecordCount
        self.incomeRecordCount = incomeRecordCount
        self.duplicateContentRecordCount = duplicateContentRecordCount
        self.expenseTotalMinorUnits = expenseTotalMinorUnits
        self.incomeTotalMinorUnits = incomeTotalMinorUnits
        self.distinctBookCount = distinctBookCount
        self.distinctCategoryCount = distinctCategoryCount
        self.distinctAccountCount = distinctAccountCount
        self.distinctCurrencyCount = distinctCurrencyCount
    }
}

public struct LedgerMeowImportPlan: Equatable, Sendable {
    public let records: [LedgerMeowImportRecord]
    public let issues: [LedgerMeowImportIssue]
    public let preview: LedgerMeowImportPreview

    public init(
        records: [LedgerMeowImportRecord],
        issues: [LedgerMeowImportIssue],
        preview: LedgerMeowImportPreview
    ) {
        self.records = records
        self.issues = issues
        self.preview = preview
    }
}

/// Produces stable keys without relying on Swift's randomized `Hasher`.
public enum LedgerMeowImportIdentity {
    /// `occurrence` is one-based among rows with the exact same seven decoded source values.
    public static func deduplicationKey(
        for fields: LedgerMeowSourceFields,
        occurrence: Int
    ) -> String {
        var canonical = Data()
        let values = [
            LedgerEntryImportFormat.meowLedgerCSVV1.rawValue,
            fields.category,
            fields.timestamp,
            fields.amount,
            fields.account,
            fields.book,
            fields.currency,
            fields.note,
            String(occurrence),
        ]
        for value in values {
            let bytes = Data(value.utf8)
            var length = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { canonical.append(contentsOf: $0) }
            canonical.append(bytes)
        }
        let digest = SHA256.hash(data: canonical)
        return "meow-ledger-csv-v1:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum LedgerMeowCSVParser {
    /// Parses UTF-8 CSV data. A UTF-8 BOM is accepted only at the beginning of the file.
    /// Dates are interpreted as local wall-clock values in the injected calendar and time zone.
    public static func parse(
        data: Data,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> LedgerMeowImportPlan {
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        guard let text = String(data: Data(bytes), encoding: .utf8) else {
            return plan(records: [], issues: [
                LedgerMeowImportIssue(line: 1, code: .invalidUTF8),
            ], parsedDataRowCount: 0)
        }

        let scanned = scan(text)
        guard let header = scanned.records.first else {
            let issues = scanned.issues + [LedgerMeowImportIssue(line: 1, code: .missingHeader)]
            return plan(records: [], issues: issues, parsedDataRowCount: 0)
        }
        let expectedHeader = LedgerMeowCSVColumn.allCases.map(\.rawValue)
        guard header.line == 1, header.fields == expectedHeader else {
            let issues = scanned.issues + [LedgerMeowImportIssue(line: 1, code: .invalidHeader)]
            return plan(records: [], issues: issues, parsedDataRowCount: 0)
        }

        var issues = scanned.issues
        var records: [LedgerMeowImportRecord] = []
        var occurrences: [LedgerMeowSourceFields: Int] = [:]
        let dataRows = Array(scanned.records.dropFirst())

        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = localCalendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false

        for row in dataRows {
            guard row.fields.count == expectedHeader.count else {
                issues.append(LedgerMeowImportIssue(
                    line: row.line,
                    code: .invalidFieldCount(expected: expectedHeader.count, actual: row.fields.count)
                ))
                continue
            }

            let fields = LedgerMeowSourceFields(
                category: row.fields[0],
                timestamp: row.fields[1],
                amount: row.fields[2],
                account: row.fields[3],
                book: row.fields[4],
                currency: row.fields[5],
                note: row.fields[6]
            )
            var rowIssues: [LedgerMeowImportIssue] = []
            for (column, value) in [
                (LedgerMeowCSVColumn.category, fields.category),
                (.timestamp, fields.timestamp),
                (.amount, fields.amount),
                (.book, fields.book),
                (.currency, fields.currency),
            ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rowIssues.append(LedgerMeowImportIssue(
                    line: row.line,
                    column: column,
                    code: .missingRequiredField
                ))
            }

            let parsedDate: Date?
            if fields.timestamp.isEmpty {
                parsedDate = nil
            } else if let candidate = formatter.date(from: fields.timestamp),
                      formatter.string(from: candidate) == fields.timestamp {
                parsedDate = candidate
            } else {
                parsedDate = nil
                rowIssues.append(LedgerMeowImportIssue(
                    line: row.line,
                    column: .timestamp,
                    code: .invalidTimestamp
                ))
            }

            let parsedAmount = parseAmount(fields.amount)
            let kind: LedgerEntryKind?
            let amount: LedgerAmount?
            switch parsedAmount {
            case let .success(value):
                kind = value.kind
                amount = value.amount
            case let .failure(code):
                kind = nil
                amount = nil
                if !fields.amount.isEmpty {
                    rowIssues.append(LedgerMeowImportIssue(
                        line: row.line,
                        column: .amount,
                        code: code
                    ))
                }
            }

            guard rowIssues.isEmpty, let parsedDate, let kind, let amount else {
                issues.append(contentsOf: rowIssues)
                continue
            }

            let occurrence = occurrences[fields, default: 0] + 1
            occurrences[fields] = occurrence
            let key = LedgerMeowImportIdentity.deduplicationKey(
                for: fields,
                occurrence: occurrence
            )
            let metadata = LedgerEntryImportMetadata(
                format: .meowLedgerCSVV1,
                deduplicationKey: key,
                originalCategory: fields.category,
                originalTimestamp: fields.timestamp,
                originalAmount: fields.amount,
                originalAccount: fields.account,
                originalBook: fields.book,
                originalCurrency: fields.currency,
                originalNote: fields.note
            )
            records.append(LedgerMeowImportRecord(
                sourceLine: row.line,
                fields: fields,
                kind: kind,
                amount: amount,
                date: parsedDate,
                importMetadata: metadata
            ))
        }

        let malformedDataLines = Set(scanned.issues.lazy.filter { $0.line > 1 }.map(\.line))
        return plan(
            records: records,
            issues: issues,
            parsedDataRowCount: dataRows.count + malformedDataLines.count
        )
    }

    private struct CSVRecord {
        let line: Int
        let fields: [String]
    }

    private struct CSVScanResult {
        let records: [CSVRecord]
        let issues: [LedgerMeowImportIssue]
    }

    private enum CSVState {
        case startField
        case inUnquotedField
        case inQuotedField
        case afterQuotedField
    }

    private static func scan(_ text: String) -> CSVScanResult {
        var records: [CSVRecord] = []
        var issues: [LedgerMeowImportIssue] = []
        var fields: [String] = []
        var field = ""
        var state = CSVState.startField
        var index = text.startIndex
        var line = 1
        var recordStartLine = 1

        while index < text.endIndex {
            if let newline = newline(at: index, in: text) {
                if state == .inQuotedField {
                    field.append(newline.literal)
                } else {
                    fields.append(field)
                    records.append(CSVRecord(line: recordStartLine, fields: fields))
                    fields.removeAll(keepingCapacity: true)
                    field.removeAll(keepingCapacity: true)
                    state = .startField
                    recordStartLine = line + 1
                }
                line += 1
                index = newline.nextIndex
                continue
            }

            let character = text[index]
            var malformed = false
            switch state {
            case .startField:
                if character == "\"" {
                    state = .inQuotedField
                } else if character == "," {
                    fields.append("")
                } else {
                    field.append(character)
                    state = .inUnquotedField
                }
            case .inUnquotedField:
                if character == "\"" {
                    malformed = true
                } else if character == "," {
                    fields.append(field)
                    field.removeAll(keepingCapacity: true)
                    state = .startField
                } else {
                    field.append(character)
                }
            case .inQuotedField:
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    state = .afterQuotedField
                } else {
                    field.append(character)
                }
            case .afterQuotedField:
                if character == "," {
                    fields.append(field)
                    field.removeAll(keepingCapacity: true)
                    state = .startField
                } else {
                    malformed = true
                }
            }

            if malformed {
                issues.append(LedgerMeowImportIssue(line: recordStartLine, code: .malformedCSV))
                while index < text.endIndex, newline(at: index, in: text) == nil {
                    index = text.index(after: index)
                }
                if index < text.endIndex, let boundary = newline(at: index, in: text) {
                    line += 1
                    index = boundary.nextIndex
                }
                fields.removeAll(keepingCapacity: true)
                field.removeAll(keepingCapacity: true)
                state = .startField
                recordStartLine = line
                continue
            }
            index = text.index(after: index)
        }

        if state == .inQuotedField {
            issues.append(LedgerMeowImportIssue(line: recordStartLine, code: .malformedCSV))
        } else if state != .startField || !fields.isEmpty || !field.isEmpty {
            fields.append(field)
            records.append(CSVRecord(line: recordStartLine, fields: fields))
        }
        return CSVScanResult(records: records, issues: issues)
    }

    private static func newline(
        at index: String.Index,
        in text: String
    ) -> (literal: String, nextIndex: String.Index)? {
        // Swift treats CRLF as one extended grapheme cluster, so test it before lone CR/LF.
        if text[index] == "\r\n" {
            return ("\r\n", text.index(after: index))
        }
        if text[index] == "\n" {
            return ("\n", text.index(after: index))
        }
        guard text[index] == "\r" else { return nil }
        let next = text.index(after: index)
        if next < text.endIndex, text[next] == "\n" {
            return ("\r\n", text.index(after: next))
        }
        return ("\r", next)
    }

    private static func parseAmount(
        _ rawValue: String
    ) -> Result<(kind: LedgerEntryKind, amount: LedgerAmount), LedgerMeowImportIssue.Code> {
        guard rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else { return .failure(.invalidAmount) }

        var magnitude = rawValue
        let kind: LedgerEntryKind
        if magnitude.first == "-" {
            kind = .expense
            magnitude.removeFirst()
        } else {
            kind = .income
            if magnitude.first == "+" { magnitude.removeFirst() }
        }
        guard !magnitude.isEmpty else { return .failure(.invalidAmount) }
        do {
            return .success((kind, try LedgerAmount(input: magnitude)))
        } catch LedgerError.nonPositiveAmount {
            return .failure(.zeroAmount)
        } catch LedgerError.amountOverflow {
            return .failure(.amountOverflow)
        } catch {
            return .failure(.invalidAmount)
        }
    }

    private static func plan(
        records: [LedgerMeowImportRecord],
        issues: [LedgerMeowImportIssue],
        parsedDataRowCount: Int
    ) -> LedgerMeowImportPlan {
        let invalidLines = Set(issues.lazy.filter { $0.line > 1 }.map(\.line))
        let expenseRecords = records.filter { $0.kind == .expense }
        let incomeRecords = records.filter { $0.kind == .income }
        let duplicateCount = records.count - Set(records.map(\.fields)).count
        let preview = LedgerMeowImportPreview(
            totalRowCount: parsedDataRowCount,
            validRecordCount: records.count,
            invalidRowCount: invalidLines.count,
            expenseRecordCount: expenseRecords.count,
            incomeRecordCount: incomeRecords.count,
            duplicateContentRecordCount: duplicateCount,
            expenseTotalMinorUnits: exactTotal(expenseRecords),
            incomeTotalMinorUnits: exactTotal(incomeRecords),
            distinctBookCount: Set(records.map(\.fields.book)).count,
            distinctCategoryCount: Set(records.map(\.fields.category)).count,
            distinctAccountCount: Set(records.map(\.fields.account)).count,
            distinctCurrencyCount: Set(records.map(\.fields.currency)).count
        )
        return LedgerMeowImportPlan(records: records, issues: issues, preview: preview)
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
