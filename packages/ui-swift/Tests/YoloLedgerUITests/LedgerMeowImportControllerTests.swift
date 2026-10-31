import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct LedgerMeowImportControllerTests {
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    @Test
    func combinesMultipleFilesUsingTheInjectedLocalTimeZone() {
        let controller = LedgerMeowImportController()
        controller.prepare(
            documents: [
                document(
                    name: "第一批.csv",
                    rows: [
                        "餐饮,2026-10-30 12:00:00,-12.50,现金,日常,CNY,午饭",
                        "工资,2026-10-30 18:00:00,+1000.00,银行卡,日常,CNY,十月工资",
                    ]
                ),
                document(
                    name: "第二批.csv",
                    rows: [
                        "购物,2026-10-31 09:00:00,-20.00,支付宝,旅行,CNY,雨伞",
                        "餐饮,2026-10-30 12:00:00,-12.50,现金,日常,CNY,午饭",
                    ]
                ),
            ],
            calendar: calendar,
            timeZone: timeZone
        )

        let preview = controller.selection?.preview
        #expect(preview?.fileCount == 2)
        #expect(preview?.totalRowCount == 4)
        #expect(preview?.validRecordCount == 4)
        #expect(preview?.invalidRowCount == 0)
        #expect(preview?.duplicateContentRecordCount == 1)
        #expect(preview?.expenseRecordCount == 3)
        #expect(preview?.expenseTotalMinorUnits == 4_500)
        #expect(preview?.incomeRecordCount == 1)
        #expect(preview?.incomeTotalMinorUnits == 100_000)
        #expect(preview?.distinctBookCount == 2)
        #expect(preview?.distinctCategoryCount == 3)
        #expect(preview?.distinctAccountCount == 3)
        #expect(preview?.distinctCurrencyCount == 1)
        #expect(localComponents(preview?.earliestDate) == DateComponents(year: 2026, month: 10, day: 30, hour: 12))
        #expect(localComponents(preview?.latestDate) == DateComponents(year: 2026, month: 10, day: 31, hour: 9))
        #expect(controller.selection?.canImport == true)
    }

    @Test
    func anyParseIssueBlocksTheImportAndDoesNotExposeRawRowText() async {
        let recorder = MeowImportActionRecorder()
        let controller = LedgerMeowImportController()
        controller.installImportAction { plans in
            recorder.callCount += 1
            return LedgerMeowImportResult(
                importedRecordCount: plans.flatMap(\.records).count,
                skippedDuplicateRecordCount: 0,
                backupName: "backup"
            )
        }
        controller.prepare(
            documents: [document(
                name: "错误样本.csv",
                rows: ["餐饮,2026-10-30 12:00:00,不是金额,现金,日常,CNY,不应展示的私密备注"]
            )],
            calendar: calendar,
            timeZone: timeZone
        )

        #expect(controller.selection?.canImport == false)
        #expect(controller.selection?.preview.invalidRowCount == 1)
        #expect(controller.selection?.issues.first?.line == 2)
        #expect(controller.selection?.issues.first?.description == "金额：金额格式不正确")
        #expect(!controller.selection!.issues.first!.description.contains("私密备注"))
        await controller.importSelection()
        #expect(recorder.callCount == 0)
        #expect(controller.result == nil)
    }

    @Test
    func importPreventsDuplicateSubmissionAndPublishesTheSafeResult() async {
        let recorder = MeowImportActionRecorder()
        let controller = preparedController()
        controller.installImportAction { plans in
            recorder.callCount += 1
            try await Task.sleep(for: .milliseconds(80))
            return LedgerMeowImportResult(
                importedRecordCount: plans.flatMap(\.records).count,
                skippedDuplicateRecordCount: 1,
                backupName: "ledger-before-meow-import.store"
            )
        }

        let first = Task { await controller.importSelection() }
        while !controller.isImporting { await Task.yield() }
        await controller.importSelection()
        await first.value

        #expect(recorder.callCount == 1)
        #expect(controller.successfulImportRevision == 1)
        #expect(controller.result?.importedRecordCount == 1)
        #expect(controller.result?.skippedDuplicateRecordCount == 1)
        #expect(controller.result?.backupName == "ledger-before-meow-import.store")
        #expect(controller.failureMessage == nil)
    }

    @Test
    func failedImportKeepsThePreviewAndUsesAGenericMessage() async {
        let controller = preparedController()
        controller.installImportAction { _ in
            throw PrivateImportFailure(message: "用户真实目录与账目内容")
        }
        let originalSelection = controller.selection

        await controller.importSelection()

        #expect(controller.selection == originalSelection)
        #expect(controller.result == nil)
        #expect(controller.successfulImportRevision == 0)
        #expect(controller.failureMessage?.contains("原数据保持不变") == true)
        #expect(controller.failureMessage?.contains("真实目录") == false)
    }

    @Test
    func reselectAndCancelResetPresentationWithoutImporting() {
        let controller = preparedController()
        #expect(controller.isReviewPresented)

        controller.requestFileSelection()
        #expect(controller.isFileImporterPresented)
        #expect(!controller.isReviewPresented)

        controller.dismissFileImporter()
        controller.cancelReview()
        #expect(!controller.isFileImporterPresented)
        #expect(controller.selection == nil)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = timeZone
        return calendar
    }

    private func preparedController() -> LedgerMeowImportController {
        let controller = LedgerMeowImportController()
        controller.prepare(
            documents: [document(
                name: "单文件.csv",
                rows: ["餐饮,2026-10-30 12:00:00,-12.50,现金,日常,CNY,午饭"]
            )],
            calendar: calendar,
            timeZone: timeZone
        )
        return controller
    }

    private func document(name: String, rows: [String]) -> LedgerMeowImportDocument {
        LedgerMeowImportDocument(
            name: name,
            data: Data((["分类,时间,金额,账户,账本,货币,备注"] + rows).joined(separator: "\n").utf8)
        )
    }

    private func localComponents(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        return calendar.dateComponents([.year, .month, .day, .hour], from: date)
    }
}

@MainActor
private final class MeowImportActionRecorder {
    var callCount = 0
}

private struct PrivateImportFailure: Error {
    let message: String
}
