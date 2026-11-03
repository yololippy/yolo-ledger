import Foundation
import Testing
import YoloLedgerCore
@testable import YoloLedgerUI

@MainActor
struct LedgerFolderSyncControllerTests {
    @Test
    func presentationCoversUnconfiguredSyncingSuccessAndFailure() {
        let controller = LedgerFolderSyncController()
        let folderName = "\(YoloLedgerProduct.displayName)同步"
        #expect(!controller.isConfigured)
        #expect(controller.detail.contains("iCloud Drive"))
        #expect(controller.compactStatus == "仅存储在本机")

        controller.update(folderName: folderName, state: .syncing)
        #expect(controller.isConfigured)
        #expect(controller.isSynchronizing)
        #expect(controller.title == folderName)
        #expect(controller.compactStatus == "正在同步…")

        let report = LedgerFolderSyncReport(
            importedRecordCount: 3,
            exportedRecordCount: 5,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        controller.reportSuccessfulSync(folderName: folderName, report: report)
        #expect(controller.successfulSyncRevision == 1)
        #expect(controller.detail.contains("导入 3 条"))
        #expect(controller.detail.contains("导出 5 条"))
        #expect(controller.compactStatus == "已同步")

        controller.update(folderName: folderName, state: .failed(message: "权限已撤销。"))
        #expect(controller.detail.contains("本地账目不受影响"))
        #expect(controller.compactStatus == "同步失败")

        controller.update(folderName: folderName, state: .idle(lastReport: nil))
        #expect(controller.compactStatus == "同步已开启")

        controller.update(folderName: folderName, state: .idle(lastReport: report))
        #expect(controller.compactStatus == "已同步")
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
