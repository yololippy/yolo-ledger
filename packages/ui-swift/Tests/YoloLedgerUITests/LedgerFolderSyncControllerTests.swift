import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct LedgerFolderSyncControllerTests {
    @Test
    func presentationCoversUnconfiguredSyncingSuccessAndFailure() {
        let controller = LedgerFolderSyncController()
        #expect(!controller.isConfigured)
        #expect(controller.detail.contains("iCloud Drive"))

        controller.update(folderName: "有落同步", state: .syncing)
        #expect(controller.isConfigured)
        #expect(controller.isSynchronizing)
        #expect(controller.title == "有落同步")

        let report = LedgerFolderSyncReport(
            importedRecordCount: 3,
            exportedRecordCount: 5,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        controller.reportSuccessfulSync(folderName: "有落同步", report: report)
        #expect(controller.successfulSyncRevision == 1)
        #expect(controller.detail.contains("导入 3 条"))
        #expect(controller.detail.contains("导出 5 条"))

        controller.update(folderName: "有落同步", state: .failed(message: "权限已撤销。"))
        #expect(controller.detail.contains("本地账目不受影响"))
    }

    @Test
    func actionsAreForwardedWithoutPlatformDependencies() async {
        let recorder = FolderSyncActionRecorder()
        let controller = LedgerFolderSyncController()
        controller.installActions(
            selectFolder: { url in recorder.selectedURL = url },
            synchronize: { recorder.syncCount += 1 },
            stop: { recorder.stopCount += 1 },
            localMutation: { recorder.mutationCount += 1 }
        )

        controller.requestFolderSelection()
        #expect(controller.isFolderImporterPresented)
        let url = URL(fileURLWithPath: "/tmp/yolo-ledger-folder-sync-test", isDirectory: true)
        await controller.handleFolderSelection(.success(url))
        #expect(!controller.isFolderImporterPresented)
        #expect(recorder.selectedURL == url)

        await controller.synchronizeNow()
        controller.localDataDidChange()
        controller.stopUsingFolder()
        #expect(recorder.syncCount == 1)
        #expect(recorder.mutationCount == 1)
        #expect(recorder.stopCount == 1)
    }
}

@MainActor
private final class FolderSyncActionRecorder {
    var selectedURL: URL?
    var syncCount = 0
    var stopCount = 0
    var mutationCount = 0
}
