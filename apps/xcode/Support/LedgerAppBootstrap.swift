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
            let url = try storeURL()
            #if DEBUG
            if failsOnce {
                failsOnce = false
                throw LaunchError.injectedFailure
            }
            #endif
            repository = try SwiftDataLedgerRepository(storeURL: url)
        } catch {
            let detail = (error as? any LocalizedError)?.errorDescription ?? "请检查本机存储空间或稍后重试。"
            failure = "本地账库无法打开。\(detail)"
        }
    }

    private func storeURL() throws -> URL {
        let standard = try SwiftDataLedgerRepository.defaultStoreURL()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--ui-test-store") {
            guard args.indices.contains(index + 1), let id = UUID(uuidString: args[index + 1]) else {
                throw LaunchError.invalidTestStore
            }
            return standard.deletingLastPathComponent()
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("ledger.store", isDirectory: false)
        }
        #endif
        return standard
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
    var body: some View {
        ZStack {
            if let repository = bootstrap.repository {
                YoloLedgerRootView(repository: repository)
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
        .task { bootstrap.open() }
    }
}
