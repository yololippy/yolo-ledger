import Foundation
import XCTest
import YoloLedgerCore

final class LedgerMeowImportTests: XCTestCase {
    private let header = "分类,时间,金额,账户,账本,货币,备注\r\n"

    func testBOMCRLFExpenseIncomeAndPreviewRemainExact() throws {
        let plan = parse(
            "餐饮,2026-10-30 08:15:00,-12.34,现金,日常,CNY,早餐\r\n" +
            "工资,2026-10-31 09:00:00,88.00,银行卡,工作,CNY,月度收入\r\n",
            includesBOM: true
        )

        XCTAssertEqual(plan.issues, [])
        XCTAssertEqual(plan.records.count, 2)
        XCTAssertEqual(plan.records.map(\.kind), [.expense, .income])
        XCTAssertEqual(plan.records.map(\.amount.minorUnits), [1_234, 8_800])
        XCTAssertEqual(plan.preview.totalRowCount, 2)
        XCTAssertEqual(plan.preview.validRecordCount, 2)
        XCTAssertEqual(plan.preview.invalidRowCount, 0)
        XCTAssertEqual(plan.preview.expenseRecordCount, 1)
        XCTAssertEqual(plan.preview.incomeRecordCount, 1)
        XCTAssertEqual(plan.preview.expenseTotalMinorUnits, 1_234)
        XCTAssertEqual(plan.preview.incomeTotalMinorUnits, 8_800)
        XCTAssertEqual(plan.preview.distinctBookCount, 2)
        XCTAssertEqual(plan.preview.distinctCategoryCount, 2)
        XCTAssertEqual(plan.preview.distinctAccountCount, 2)
        XCTAssertEqual(plan.preview.distinctCurrencyCount, 1)
    }

    func testRFC4180QuotedCommaEscapedQuoteAndEmbeddedCRLFArePreserved() throws {
        let plan = parse(
            "餐饮,2026-10-31 12:30:00,-12.34,\"现金,备用\",日常,CNY,\"午餐 \"\"双人餐\"\"\r\n已报销\"\r\n" +
            "工资,2026-10-31 13:00:00,20.00,,工作,CNY,\r\n"
        )

        XCTAssertTrue(plan.issues.isEmpty)
        XCTAssertEqual(plan.records.count, 2)
        XCTAssertEqual(plan.records[0].fields.account, "现金,备用")
        XCTAssertEqual(plan.records[0].fields.note, "午餐 \"双人餐\"\r\n已报销")
        XCTAssertEqual(plan.records[0].sourceLine, 2)
        XCTAssertEqual(plan.records[1].sourceLine, 4)
        XCTAssertEqual(plan.records[1].fields.account, "")
        XCTAssertEqual(plan.records[1].fields.note, "")
    }

    func testStrictValidationReportsEachBadSourceLineAndContinues() {
        let plan = parse(
            "餐饮,2026-10-31 08:00:00,-1.00,现金,日常,CNY\r\n" +
            ",2026-10-31 08:00:00,-1.00,现金,日常,CNY,缺分类\r\n" +
            "餐饮,2026-02-30 08:00:00,-1.00,现金,日常,CNY,坏日期\r\n" +
            "餐饮,2026-10-31 08:00:00,12.345,现金,日常,CNY,坏金额\r\n" +
            "餐饮,2026-10-31 08:00:00,0.00,现金,日常,CNY,零金额\r\n" +
            "餐饮,2026-10-31 08:00:00,-92233720368547758.08,现金,日常,CNY,溢出金额\r\n" +
            "餐\"饮,2026-10-31 08:00:00,-1.00,现金,日常,CNY,坏引号\r\n" +
            "交通,2026-10-31 09:00:00,-2.00,,日常,CNY,\r\n"
        )

        XCTAssertEqual(plan.records.count, 1)
        XCTAssertEqual(plan.records[0].fields.category, "交通")
        XCTAssertEqual(plan.preview.totalRowCount, 8)
        XCTAssertEqual(plan.preview.validRecordCount, 1)
        XCTAssertEqual(plan.preview.invalidRowCount, 7)
        XCTAssertTrue(plan.issues.contains {
            $0.line == 2 && $0.code == .invalidFieldCount(expected: 7, actual: 6)
        })
        XCTAssertTrue(plan.issues.contains {
            $0.line == 3 && $0.column == .category && $0.code == .missingRequiredField
        })
        XCTAssertTrue(plan.issues.contains {
            $0.line == 4 && $0.column == .timestamp && $0.code == .invalidTimestamp
        })
        XCTAssertTrue(plan.issues.contains {
            $0.line == 5 && $0.column == .amount && $0.code == .invalidAmount
        })
        XCTAssertTrue(plan.issues.contains {
            $0.line == 6 && $0.column == .amount && $0.code == .zeroAmount
        })
        XCTAssertTrue(plan.issues.contains {
            $0.line == 7 && $0.column == .amount && $0.code == .amountOverflow
        })
        XCTAssertTrue(plan.issues.contains { $0.line == 8 && $0.code == .malformedCSV })
    }

    func testInjectedTimeZoneControlsLocalWallClockInterpretation() throws {
        let body = "餐饮,2026-10-31 08:00:00,-1.00,现金,日常,CNY,时区测试\r\n"
        let shanghai = parse(body, timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai")))
        let utc = parse(body, timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
        let shanghaiDate = try XCTUnwrap(shanghai.records.first?.date)
        let utcDate = try XCTUnwrap(utc.records.first?.date)

        XCTAssertEqual(utcDate.timeIntervalSince(shanghaiDate), 8 * 60 * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertEqual(calendar.component(.hour, from: shanghaiDate), 8)
    }

    func testDuplicateRowsGetDistinctButRepeatableOccurrenceKeys() throws {
        let duplicate = "餐饮,2026-10-31 08:00:00,-1.00,现金,日常,CNY,同一来源行\r\n"
        let body = duplicate + duplicate +
            "餐饮,2026-10-31 08:00:00,-1.00,现金,日常,CNY,另一条合法账单\r\n"
        let first = parse(body)
        let second = parse(body)
        let firstKeys = first.records.map(\.importMetadata.deduplicationKey)
        let secondKeys = second.records.map(\.importMetadata.deduplicationKey)

        XCTAssertEqual(first.preview.duplicateContentRecordCount, 1)
        XCTAssertEqual(firstKeys, secondKeys)
        guard firstKeys.count == 3 else {
            XCTFail("Expected three valid records, got \(firstKeys.count)")
            return
        }
        XCTAssertEqual(
            firstKeys[0],
            "meow-ledger-csv-v1:f31e3b1e2c313770a98c28c0525e010cc38cad5295dc7e8a2f06cf29787e3eed"
        )
        XCTAssertNotEqual(firstKeys[0], firstKeys[1])
        XCTAssertTrue(firstKeys.allSatisfy { $0.hasPrefix("meow-ledger-csv-v1:") })
        XCTAssertTrue(firstKeys.allSatisfy { $0.count == 83 })
    }

    func testImportMetadataSurvivesDraftEntryAndCodableRoundTrip() throws {
        let record = try XCTUnwrap(parse(
            "购物,2026-10-31 10:00:00,-3.21,储值账户,家庭账本,CNY,保真备注\r\n"
        ).records.first)
        let draft = LedgerEntryDraft(
            bookID: UUID(),
            categoryID: UUID(),
            kind: record.kind,
            amount: record.amount,
            date: record.date,
            note: record.fields.note,
            source: .meowLedgerImport,
            importMetadata: record.importMetadata
        )
        let entry = LedgerEntry(id: UUID(), draft: draft, createdAt: record.date, updatedAt: record.date)
        let encoded = try JSONEncoder().encode(record.importMetadata)

        XCTAssertEqual(entry.source, .meowLedgerImport)
        XCTAssertEqual(entry.importMetadata, record.importMetadata)
        XCTAssertEqual(entry.draft.importMetadata, record.importMetadata)
        XCTAssertEqual(try JSONDecoder().decode(LedgerEntryImportMetadata.self, from: encoded), record.importMetadata)
        XCTAssertEqual(record.importMetadata.originalAccount, "储值账户")
        XCTAssertEqual(record.importMetadata.originalCurrency, "CNY")
    }

    func testInvalidUTF8AndWrongHeaderAreFileLevelIssuesWithoutDataLeakage() {
        let invalidUTF8 = LedgerMeowCSVParser.parse(
            data: Data([0xFF, 0xFE]),
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let wrongHeader = LedgerMeowCSVParser.parse(
            data: Data("时间,分类\r\n".utf8),
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(invalidUTF8.issues, [LedgerMeowImportIssue(line: 1, code: .invalidUTF8)])
        XCTAssertTrue(invalidUTF8.records.isEmpty)
        XCTAssertEqual(wrongHeader.issues, [LedgerMeowImportIssue(line: 1, code: .invalidHeader)])
        XCTAssertTrue(wrongHeader.records.isEmpty)
    }

    func testExistingDraftDefaultsRemainBackwardCompatible() throws {
        let draft = LedgerEntryDraft(
            bookID: UUID(),
            categoryID: UUID(),
            kind: .expense,
            amount: try LedgerAmount(input: "1.00"),
            date: Date()
        )

        XCTAssertEqual(draft.source, .manual)
        XCTAssertNil(draft.importMetadata)
    }

    private func parse(
        _ body: String,
        includesBOM: Bool = false,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    ) -> LedgerMeowImportPlan {
        var data = Data()
        if includesBOM { data.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        data.append(Data((header + body).utf8))
        return LedgerMeowCSVParser.parse(
            data: data,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
    }
}
