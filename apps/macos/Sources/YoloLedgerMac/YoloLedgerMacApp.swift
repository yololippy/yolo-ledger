import SwiftUI

@main
struct YoloLedgerMacApp: App {
    @State private var bootstrap = LedgerAppBootstrap()

    var body: some Scene {
        Window("有落", id: "main") {
            LedgerAppContent(bootstrap: bootstrap)
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 1000, height: 680)
    }
}
