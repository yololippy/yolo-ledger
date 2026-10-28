# 应用入口

本仓库只有有落一个软件，平台入口直接放在 `apps/` 下。

- [macos/](macos/README.md)：Mac 原生 App 入口及桌面适配。
- [ios/](ios/README.md)：iPhone 原生 App 入口及移动平台适配。
- [xcode/](xcode/README.md)：统一 Xcode 工程和双端构建配置。

应用层负责组装共享模块、注入依赖和接入平台能力。记账规则、统计计算和本地存储实现放在对应的 `packages/` 模块中。

当前已建立 M1 原生双端入口、统一 Xcode 工程及共享四页导航。两个入口均注入 `EmptyLedgerBookRepository`，账本结果为空；尚无持久化或记账 CRUD。

App 显示名为“有落”，英文名为 YoloLedger。构建命令、产物位置和实际验证边界见 [Xcode 工程说明](xcode/README.md)。
