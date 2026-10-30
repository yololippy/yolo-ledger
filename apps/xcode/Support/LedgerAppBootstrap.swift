import Foundation
import Observation
import SwiftUI
import YoloLedgerCore
import YoloLedgerStorage
import YoloLedgerUI

@MainActor
@Observable
final class LedgerAppBootstrap {
    private(set) var repository: (any LedgerRepository)?
    private(set) var failure: String?
    private(set) var isOpening = false
    #if DEBUG
    private var failsOnce = ProcessInfo.processInfo.arguments.contains("--ui-test-fail-open-once")
    #endif

    func open() {
        guard repository == nil, !isOpening else { return }
        isOpening = true
        failure = nil
        defer { isOpening = false }
        do {
            let configuration = try storeConfiguration()
            #if DEBUG
            if failsOnce {
                failsOnce = false
                throw LaunchError.injectedFailure
            }
            #endif
            repository = try SwiftDataLedgerRepository(
                storeURL: configuration.url,
                syncMode: configuration.syncMode
            )
        } catch {
            let detail = (error as? any LocalizedError)?.errorDescription ?? "请检查本机存储空间或稍后重试。"
            failure = "本地账库无法打开。\(detail)"
        }
    }

    private func storeConfiguration() throws -> (url: URL, syncMode: LedgerSyncMode) {
        let standard = try SwiftDataLedgerRepository.defaultStoreURL()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--ui-test-store") {
            guard args.indices.contains(index + 1), let id = UUID(uuidString: args[index + 1]) else {
                throw LaunchError.invalidTestStore
            }
            let url = standard.deletingLastPathComponent()
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("ledger.store", isDirectory: false)
            return (url, .local)
        }
        #endif
        return (standard, YoloLedgerICloud.syncMode)
    }
}

private enum LaunchError: LocalizedError {
    case injectedFailure, invalidTestStore
    var errorDescription: String? {
        switch self {
        case .injectedFailure: "测试启动失败，请点击重试。"
        case .invalidTestStore: "测试账库标识无效。"
        }
    }
}

@MainActor
struct LedgerAppContent: View {
    let bootstrap: LedgerAppBootstrap
    @Binding private var pendingScreenshotProposal: LedgerScreenshotProposal?

    init(
        bootstrap: LedgerAppBootstrap,
        pendingScreenshotProposal: Binding<LedgerScreenshotProposal?> = .constant(nil)
    ) {
        self.bootstrap = bootstrap
        _pendingScreenshotProposal = pendingScreenshotProposal
    }

    var body: some View {
        ZStack {
            if let repository = bootstrap.repository {
                YoloLedgerRootView(
                    repository: repository,
                    pendingScreenshotProposal: $pendingScreenshotProposal
                )
            } else if let failure = bootstrap.failure {
                ContentUnavailableView {
                    Label("无法打开本地账库", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(failure).accessibilityIdentifier("startup.error")
                } actions: {
                    Button("重试") { bootstrap.open() }
                        .accessibilityIdentifier("startup.retry")
                }
            } else {
                ProgressView("正在打开本地账库")
            }
        }
        .ledgerTheme(.pastel)
        .task {
            bootstrap.open()
            await ICloudDocumentsBootstrap.prepareIfNeeded()
        }
    }
}

private enum ICloudDocumentsBootstrap {
    private static let completionKey = "icloud-documents-bootstrap-v1"

    static func prepareIfNeeded() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-store") { return }
        #endif
        guard !UserDefaults.standard.bool(forKey: completionKey) else { return }

        let prepared = await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let containerURL = fileManager.url(
                forUbiquityContainerIdentifier: YoloLedgerICloud.containerIdentifier
            ) else { return false }

            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            let welcomeURL = documentsURL.appendingPathComponent("关于有落.txt", isDirectory: false)
            do {
                try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: welcomeURL.path) {
                    let content = """
                    有落 · YoloLedger

                    此目录用于保存你主动创建的账单导出、备份和后续附件。
                    日常记账数据由有落在本机保存，并通过 iCloud 自动同步。
                    """
                    try Data(content.utf8).write(to: welcomeURL, options: .atomic)
                }
                return true
            } catch {
                return false
            }
        }.value

        if prepared { UserDefaults.standard.set(true, forKey: completionKey) }
    }
}
