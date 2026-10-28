import SwiftUI
import YoloLedgerStorage
import YoloLedgerUI

@main
struct YoloLedgerIOSApp: App {
    var body: some Scene {
        WindowGroup {
            YoloLedgerRootView(repository: EmptyLedgerBookRepository())
        }
    }
}
