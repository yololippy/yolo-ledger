# iOS App

用于有落 iPhone App 的入口、移动端导航和平台能力适配，iPadOS 暂不支持。后续快捷指令、截图识别等系统能力按确认的方案接入。

由 `apps/xcode/` 中的 `YoloLedgerIOS` target 构建，入口位于 `Sources/YoloLedgerIOS/YoloLedgerIOSApp.swift`。入口组装本地共享模块，将 `EmptyLedgerBookRepository` 注入 `YoloLedgerRootView`。

当前是 M1 中文占位导航；账单、明细、账本、设置通过底部标签切换，尚无真实账目或持久化。

2026-10-28：iOS Simulator 构建通过；在 iOS 27.0 的 iPhone 18 Pro 模拟器上完成实际启动和 1 项 XCUITest 导航测试，点击四个标签并返回账单，页面文字断言全部通过。4 个页面截图保存在该次 `.xcresult` 中。

Bundle ID：`com.yololedger.ios`。`TARGETED_DEVICE_FAMILY=1`，关闭 Mac Catalyst、Designed for iPhone on Mac 与 Vision 兼容入口。用户当前 iPhone 系统记录为 iOS 27；工程临时构建基线为 iOS 17，正式最低支持版本仍待确定。尚未进行 iPhone 真机验证。

可复现命令和验证产物见 [Xcode 工程说明](../xcode/README.md)。
