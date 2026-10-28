# macOS App

用于有落 Mac App 的入口、窗口、菜单、快捷键和桌面布局适配。

后续由 `apps/xcode/` 中的 macOS target 构建，入口负责组装 `core-swift`、`storage-swift` 和 `ui-swift`，与 iOS 端共享业务逻辑。

当前本地开发设备（2026-10-28 读取）：Mac mini（Mac18,5）、Apple M6、24 GB 内存、arm64，运行 macOS 27.0.1（26A434）。

当前仅建立目录；尚无 Swift 源文件、可运行 App 或已确认的最低 macOS 版本。
