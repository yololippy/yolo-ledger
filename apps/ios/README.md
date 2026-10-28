# iPhone App

`Sources/YoloLedgerIOS/YoloLedgerIOSApp.swift` 是 iPhone 原生入口，由 `YoloLedgerIOS` target 构建。入口持有共享 App 启动状态，打开真实 SwiftData 本地磁盘仓库，再注入共享页面。

当前支持收入／支出新增、详情、编辑、确认删除、基础账本管理与切换，以及当前月收支汇总。默认账本与分类由存储层初始化；尚无 iCloud 同步，iPadOS 暂不支持。

Bundle ID：`com.yololedger.ios`。`TARGETED_DEVICE_FAMILY=1`，关闭 Mac Catalyst、Designed for iPhone on Mac 和 Vision 兼容入口。工程临时构建基线为 iOS 17，正式最低支持版本仍待确定。

iPhone 流程测试使用 DEBUG 参数 `--ui-test-store <UUID>`，每个用例生成独立磁盘账库，重启使用同一 UUID，不清理日常数据。构建、测试命令和本次结果见 [Xcode 工程说明](../xcode/README.md)。iPhone 真机尚未验证。

2026-10-28：iPhone 18 Pro / iOS 27.0 模拟器构建通过，四页导航、账本／收入／切换隔离、打开失败重试三个流程通过；新增、编辑、重启保留、确认删除及删除后再次重启的完整生命周期单独复验通过。4 个场景分次通过，报告与截图位置记录在工程说明中。
