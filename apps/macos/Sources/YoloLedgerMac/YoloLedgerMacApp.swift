import SwiftUI
import YoloLedgerStorage
import YoloLedgerUI

@main
struct YoloLedgerMacApp: App {
    var body: some Scene {
        Window("有落", id: "main") {
            YoloLedgerRootView(repository: EmptyLedgerBookRepository())
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 1000, height: 680)
    }
}
