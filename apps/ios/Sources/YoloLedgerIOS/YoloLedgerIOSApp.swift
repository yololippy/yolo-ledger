import SwiftUI

@main
struct YoloLedgerIOSApp: App {
    @State private var bootstrap = LedgerAppBootstrap()

    var body: some Scene {
        WindowGroup {
            LedgerAppContent(bootstrap: bootstrap)
        }
    }
}
