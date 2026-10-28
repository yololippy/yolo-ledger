# 应用入口

本仓库只有有落一个软件，平台入口直接放在 `apps/` 下。

- [macos/](macos/README.md)：Mac 原生 App 入口及桌面适配。
- [ios/](ios/README.md)：iPhone 原生 App 入口及移动平台适配。
- [xcode/](xcode/README.md)：统一工程、构建配置、共享启动组装及验证说明。

当前已从 M1 空仓库切换到 M2 的 `SwiftDataLedgerRepository`。两个 App 入口各自长期持有一个启动状态与磁盘仓库；`apps/xcode/Support/LedgerAppBootstrap.swift` 在应用层组装存储和共享 UI。打开账库失败会显示可重试错误，不会回退到内存、清库或终止 App。

App 显示名为“有落”，英文名为 YoloLedger。当前支持本地手动记账、基本账本切换和当前月汇总；iCloud 暂未接入。构建命令、独立测试账库、产物与证据见 [工程说明](xcode/README.md)。
