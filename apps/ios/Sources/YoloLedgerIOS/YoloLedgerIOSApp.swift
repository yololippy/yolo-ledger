import SwiftUI
import YoloLedgerCore

@main
struct YoloLedgerIOSApp: App {
    @State private var bootstrap: LedgerAppBootstrap

    init() {
        let bootstrap = LedgerAppBootstrap()
        _bootstrap = State(initialValue: bootstrap)
        FolderSyncBackgroundTasks.register(bootstrap: bootstrap)
    }

    var body: some Scene {
        WindowGroup {
            YoloLedgerIOSRoot(bootstrap: bootstrap)
        }
    }
}

@MainActor
private struct YoloLedgerIOSRoot: View {
    let bootstrap: LedgerAppBootstrap
    @State private var pendingScreenshotProposal: LedgerScreenshotProposal? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LedgerAppContent(
            bootstrap: bootstrap,
            pendingScreenshotProposal: $pendingScreenshotProposal
        )
        .preferredColorScheme(.light)
        .task {
            reloadPendingScreenshot()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadPendingScreenshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotImportStore.pendingDidChange)) { _ in
            reloadPendingScreenshot()
        }
    }

    private func reloadPendingScreenshot() {
        guard let proposal = ScreenshotImportStore.take(),
              proposal.id != pendingScreenshotProposal?.id
        else { return }
        pendingScreenshotProposal = proposal
    }
}
