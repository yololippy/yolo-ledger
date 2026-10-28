# Xcode 工程

用于统一管理有落的 macOS 与 iOS 工程配置。

后续规划：

- 创建 `YoloLedger.xcodeproj`，包含 macOS 与 iOS 两个原生 App targets 及对应的共享 schemes。
- 分别引用 `../macos/` 和 `../ios/` 下的平台入口。
- 引用 `../../packages/core-swift`、`../../packages/storage-swift` 和 `../../packages/ui-swift` 本地 Swift Packages。
- 在此管理双端构建配置、资源和签名配置。

当前仅建立目录和约定，尚无 `.xcodeproj`、targets、签名配置或构建结果。
