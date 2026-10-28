# macOS App

用于有落 Mac App 的入口、窗口、菜单、快捷键和桌面布局适配。

由 `apps/xcode/` 中的 `YoloLedgerMac` 原生 macOS target 构建，入口位于 `Sources/YoloLedgerMac/YoloLedgerMacApp.swift`。入口将 `EmptyLedgerBookRepository` 注入共享根页面，与 iPhone 端共享 UI 与核心接口。

当前本地开发设备（2026-10-28 读取）：Mac mini（Mac18,5）、Apple M6、24 GB 内存、arm64，运行 macOS 27.0.1（26A434）。

当前是 M1 侧边栏与内容区骨架，包含账单、明细、账本、设置四个入口，尚无真实账目或持久化。Bundle ID：`com.yololedger.macos`。

2026-10-28：macOS arm64 Debug 构建通过，App 已实际启动。main 使用 native computer-use 实际点击“明细 → 账本 → 设置 → 账单”，逐页核对窗口标题、选中行、空状态或设置说明，并检查最终截图，实际导航验收通过。

Mac XCUITest runner 因 `Timed out while enabling automation mode` 未能开始执行导航测试；上述实际点击是独立验收证据，不能将本次 XCTest 描述为通过。

工程临时构建基线为 macOS 14，正式最低支持版本仍待确定。构建运行命令、产物与验证边界见 [Xcode 工程说明](../xcode/README.md)。
