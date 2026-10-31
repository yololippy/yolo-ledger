import Foundation
import XCTest
import YoloLedgerCore

final class LedgerFolderSyncTests: XCTestCase {
    func testSynchronizerReceivesAuthorizedFolderAndStableDeviceIdentifier() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/yolo-ledger-sync", isDirectory: true)
        let deviceID = UUID(uuidString: "86B52AA1-3E26-4F74-954C-C189AD7211D7")!
        let report = LedgerFolderSyncReport(
            importedRecordCount: 3,
            exportedRecordCount: 5,
            completedAt: Date(timeIntervalSince1970: 1_798_000_000)
        )
        let synchronizer = RecordingFolderSynchronizer(report: report)

        let result = try await synchronizer.synchronize(folderURL: folderURL, deviceID: deviceID)
        let request = await synchronizer.receivedRequest()

        XCTAssertEqual(result, report)
        XCTAssertEqual(request?.folderURL, folderURL)
        XCTAssertEqual(request?.deviceID, deviceID)
    }

    func testReportPreservesExchangeCountsAndCompletionTime() {
        let completedAt = Date(timeIntervalSinceReferenceDate: 123_456)
        let report = LedgerFolderSyncReport(
            importedRecordCount: 12,
            exportedRecordCount: 7,
            completedAt: completedAt
        )

        XCTAssertEqual(report.importedRecordCount, 12)
        XCTAssertEqual(report.exportedRecordCount, 7)
        XCTAssertEqual(report.completedAt, completedAt)
    }

    func testStatesRepresentConfigurationProgressSuccessAndFailure() {
        let report = LedgerFolderSyncReport(
            importedRecordCount: 1,
            exportedRecordCount: 2,
            completedAt: Date(timeIntervalSince1970: 1_798_000_000)
        )
        let states: [LedgerFolderSyncState] = [
            .notConfigured,
            .idle(lastReport: nil),
            .idle(lastReport: report),
            .syncing,
            .succeeded(report),
            .failed(message: "文件夹暂时不可用"),
        ]

        XCTAssertEqual(Set(states.map(describe)), Set([
            "notConfigured",
            "idleWithoutReport",
            "idleWithReport",
            "syncing",
            "succeeded",
            "failed:文件夹暂时不可用",
        ]))
    }

    private func describe(_ state: LedgerFolderSyncState) -> String {
        switch state {
        case .notConfigured:
            "notConfigured"
        case .idle(lastReport: nil):
            "idleWithoutReport"
        case .idle(lastReport: .some):
            "idleWithReport"
        case .syncing:
            "syncing"
        case .succeeded:
            "succeeded"
        case let .failed(message):
            "failed:\(message)"
        }
    }
}

private actor RecordingFolderSynchronizer: LedgerFolderSyncing {
    struct Request: Equatable, Sendable {
        let folderURL: URL
        let deviceID: UUID
    }

    private let report: LedgerFolderSyncReport
    private var request: Request?

    init(report: LedgerFolderSyncReport) {
        self.report = report
    }

    func synchronize(folderURL: URL, deviceID: UUID) async throws -> LedgerFolderSyncReport {
        request = Request(folderURL: folderURL, deviceID: deviceID)
        return report
    }

    func receivedRequest() -> Request? {
        request
    }
}
