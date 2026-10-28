# 共享模块

此目录存放 macOS 与 iOS 两端共享的 Swift 代码，使用“模块-语言”命名。

| 目录 | 职责 | 仓库内依赖 |
| --- | --- | --- |
| [core-swift/](core-swift/README.md) | 数据模型、业务规则、统计逻辑和接口 | 无 |
| [storage-swift/](storage-swift/README.md) | 本地持久化、迁移、备份与恢复 | core-swift |
| [ui-swift/](ui-swift/README.md) | 共享页面、组件和页面状态 | core-swift |

两个 App 入口负责将存储实现注入共享界面；核心层保持独立于具体数据库和 UI 框架。

三个 Package 已建立并独立构建通过。Core 提供最小账本读取契约，Storage 提供返回空数组的适配器，UI 通过注入接口展示四页导航骨架及账本加载状态。M1 尚无实际账目保存；完整业务与本地持久化随后续里程碑实现。后续出现真实复用需求时再新增模块。
