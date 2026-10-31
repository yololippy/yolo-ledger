import Testing
@testable import YoloLedgerCore

struct YoloLedgerProductTests {
    @Test func derivedNamesFollowTheProductName() {
        #expect(YoloLedgerProduct.displayName == "有落记账")
        #expect(YoloLedgerProduct.englishName == "YoloLedger")
        #expect(YoloLedgerProduct.displayNameWithEnglish == "有落记账 · YoloLedger")
        #expect(YoloLedgerProduct.syncDirectoryName == "有落记账同步数据")
        #expect(YoloLedgerProduct.screenshotShortcutName == "有落记账截图")
        #expect(YoloLedgerProduct.applicationSupportDirectoryName == "YoloLedger")
    }
}
