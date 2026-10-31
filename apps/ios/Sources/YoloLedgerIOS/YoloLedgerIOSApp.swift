import SwiftUI
import YoloLedgerCore

@main
struct YoloLedgerIOSApp: App {
    var body: some Scene {
        WindowGroup {
            YoloLedgerIOSRoot()
        }
    }
}

@MainActor
private struct YoloLedgerIOSRoot: View {
    @State private var bootstrap = LedgerAppBootstrap()
    @State private var pendingScreenshotProposal = ScreenshotImportStore.load()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LedgerAppContent(
            bootstrap: bootstrap,
            pendingScreenshotProposal: $pendingScreenshotProposal
        )
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let proposal = ScreenshotImportStore.load() {
                pendingScreenshotProposal = proposal
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScreenshotImportStore.pendingDidChange)) { _ in
            reloadPendingScreenshot()
        }
        .onChange(of: pendingScreenshotProposal?.id) { _, proposalID in
            if proposalID == nil { ScreenshotImportStore.clear() }
        }
    }

    private func reloadPendingScreenshot() {
        guard let proposal = ScreenshotImportStore.load(),
              proposal.id != pendingScreenshotProposal?.id
        else { return }
        pendingScreenshotProposal = proposal
    }
}
