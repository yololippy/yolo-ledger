import Foundation
import Observation
import YoloLedgerCore

/// Observable presentation and action bridge for user-selected folder synchronization.
/// Platform permission and persistence remain in the App target.
@MainActor
@Observable
public final class LedgerFolderSyncController {
    public private(set) var folderName: String?
    public private(set) var state: LedgerFolderSyncState
    public private(set) var successfulSyncRevision = 0
    public private(set) var isFolderImporterPresented = false

    @ObservationIgnored private var selectFolderAction: (@MainActor @Sendable (URL) async -> Void)?
    @ObservationIgnored private var synchronizeAction: (@MainActor @Sendable () async -> Void)?
    @ObservationIgnored private var stopAction: (@MainActor @Sendable () -> Void)?
    @ObservationIgnored private var localMutationAction: (@MainActor @Sendable () -> Void)?

    public init(folderName: String? = nil, state: LedgerFolderSyncState = .notConfigured) {
        self.folderName = folderName
        self.state = state
    }

    public func installActions(
        selectFolder: @escaping @MainActor @Sendable (URL) async -> Void,
        synchronize: @escaping @MainActor @Sendable () async -> Void,
        stop: @escaping @MainActor @Sendable () -> Void,
        localMutation: @escaping @MainActor @Sendable () -> Void
    ) {
        selectFolderAction = selectFolder
        synchronizeAction = synchronize
        stopAction = stop
        localMutationAction = localMutation
    }

    public func requestFolderSelection() {
        isFolderImporterPresented = true
    }

    public func dismissFolderImporter() {
        isFolderImporterPresented = false
    }

    public func handleFolderSelection(_ result: Result<URL, any Error>) async {
        isFolderImporterPresented = false
        switch result {
        case let .success(url):
            await selectFolderAction?(url)
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                update(folderName: folderName, state: .failed(message: Self.message(for: error)))
            }
        }
    }

    public func synchronizeNow() async {
        await synchronizeAction?()
    }

    public func stopUsingFolder() {
        stopAction?()
    }

    public func localDataDidChange() {
        localMutationAction?()
    }

    public func update(folderName: String?, state: LedgerFolderSyncState) {
        self.folderName = folderName
        self.state = state
    }

    public func reportSuccessfulSync(folderName: String, report: LedgerFolderSyncReport) {
        self.folderName = folderName
        state = .succeeded(report)
        successfulSyncRevision &+= 1
    }

    public var isConfigured: Bool { folderName != nil }

    public var title: String {
        guard let folderName else { return "文件夹同步" }
        return folderName
    }

    public var detail: String {
        switch state {
        case .notConfigured:
            "选择 iCloud Drive 或普通可写文件夹，在设备间交换账目。"
        case let .idle(lastReport):
            lastReport.map(Self.reportText) ?? "文件夹已配置，等待首次同步。"
        case .syncing:
            "正在交换变更；本机记账可继续使用。"
        case let .succeeded(report):
            Self.reportText(report)
        case let .failed(message):
            "\(message) 本地账目不受影响，可更换文件夹或稍后重试。"
        }
    }

    public var statusSymbol: String {
        switch state {
        case .notConfigured: "folder.badge.plus"
        case .idle: "folder"
        case .syncing: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    public var isSynchronizing: Bool {
        if case .syncing = state { return true }
        return false
    }

    private static func reportText(_ report: LedgerFolderSyncReport) -> String {
        "上次成功：\(report.completedAt.formatted(date: .abbreviated, time: .shortened))；导入 \(report.importedRecordCount) 条，导出 \(report.exportedRecordCount) 条。"
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "无法使用所选文件夹。"
    }
}
