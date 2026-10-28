# 共享模块

此目录存放 macOS 与 iOS 两端共享的 Swift 代码，使用“模块-语言”命名。

| 目录 | 职责 | 仓库内依赖 |
| --- | --- | --- |
| [core-swift/](core-swift/README.md) | 数据模型、业务规则、统计逻辑和接口 | 无 |
| [storage-swift/](storage-swift/README.md) | 本地持久化、迁移、备份与恢复 | core-swift |
| [ui-swift/](ui-swift/README.md) | 共享页面、组件和页面状态 | core-swift |

两个 App 入口负责将存储实现注入共享界面；核心层保持独立于具体数据库和 UI 框架。

当前三个目录均为结构占位，尚未创建 `Package.swift`、源文件或测试。后续出现真实复用需求时再新增模块。
