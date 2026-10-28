# 共享界面模块

Swift 模块与 library：`YoloLedgerUI`，仅依赖 `../core-swift` 的 `YoloLedgerCore`。

当前为 M1 页面骨架：账单、明细、账本、设置四个入口。iPhone 使用 TabView / NavigationStack，Mac 使用 NavigationSplitView 侧边栏。页面是中文占位，尚未还原喵喵记账的完整样式或实现记账业务。

App 通过 `YoloLedgerRootView(repository:)` 注入 `any LedgerBookRepository`。账本页实际调用 `fetchBooks()`，展示加载、空结果、账本列表和失败重试状态。请求使用代次标识，旧请求或取消请求不能覆盖新请求的结果。本包不直接依赖存储模块或具体数据库。

## 构建与测试

在仓库根目录执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/ui-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/ui-swift
```

2026-10-28：独立构建通过，4 项 Swift Testing 测试通过，覆盖注入仓库结果、空结果、失败后重试，以及取消旧请求后快速重新加载的竞态。Mac / iPhone 实际导航验证见 [Xcode 工程说明](../../apps/xcode/README.md)。

工具版本为 Swift tools 6.0 / Swift 6。当前 Package 构建基线为 macOS 14 / iOS 17，用于工程验证；产品正式最低支持版本仍待确定。首版仅面向 Mac / iPhone，iPadOS 暂不支持。
