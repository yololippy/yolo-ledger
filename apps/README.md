# 应用入口

本仓库只有有落一个软件，平台入口直接放在 `apps/` 下。

- [macos/](macos/README.md)：Mac 原生 App 入口及桌面适配。
- [ios/](ios/README.md)：iPhone 原生 App 入口及移动平台适配。
- [xcode/](xcode/README.md)：统一 Xcode 工程和双端构建配置。

应用层负责组装共享模块、注入依赖和接入平台能力。记账规则、统计计算和本地存储实现放在对应的 `packages/` 模块中。

当前仅建立目录和说明，尚无 App 入口或 Xcode 工程。
