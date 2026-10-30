# 项目文档

此目录用于后续归档：

- 架构、数据模型、持久化和同步方案。
- 品牌、图标及后续独立 UI 设计资料；此前外部参考资料仅作为历史归档。
- Mac、iPhone 的功能验收及验证记录。
- 工程建立后的构建运行、快捷指令和备份恢复说明。

- [工程边界、本地记账与 iCloud 同步](architecture.md)：共享包依赖、平台组装、M2 数据、持久化与同步边界。
- [品牌与图标](brand/README.md)：有落独立图标概念、语义、配色和源文件。
- [iCloud 同步与用户可见目录方案](icloud-sync-plan.md)：双端统一标识、CloudKit 自动同步、iCloud Drive“有落”目录、迁移和验收设计。
- [M2 本地记账验收](m2-validation.md)：测试范围、实际 Mac 操作、iPhone 结果与未验收边界。
- [历史 UI 验收](ui-validation.md)：此前页面覆盖、双端构建和交互回归；本地截图已清理。
- [历史 UI 参考归档](references/meow-ledger/README.md)：此前采用的公开参考及来源记录，不再指导后续设计。

后续 UI 与交互使用有落自己的设计，等待用户提供或确认具体方案。任务状态统一记录在根目录 [TODO.md](../TODO.md)，仓库规则见 [AGENTS.md](../AGENTS.md)。
