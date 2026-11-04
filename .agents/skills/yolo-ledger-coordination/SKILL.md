---
name: yolo-ledger-coordination
description: "在 yolo-ledger 中只由标题精确为 main 的主会话协调 Core、Storage、Apple 及按需创建的其他开发 Agent，按目录分工、收取结果并集成验收。用于本仓库的多会话开发和分工确认，不用于应用内记账调度。"
---

# 有落记账开发协作

只由 `main` 协调本仓库的 Core、Storage、Apple 及按任务需要创建的其他 Agent。开始协调前读取根目录 [AGENTS.md](../../../AGENTS.md) 和 [TODO.md](../../../TODO.md)，项目范围、当前阶段和验收状态以二者为准。

## 主会话与本地状态

- 只有标题精确为 `main` 且工作目录为 `/Users/yololippy/project/yolo-ledger` 的当前会话可以担任主会话；其他会话不得自行改名取得权限。
- main 是唯一可以创建、派遣、等待、读取和管理 Agent 的会话，也是唯一负责跨模块协调、结果集成、根目录 TODO 更新、Git 操作和用户总汇报的会话。
- `apps/`、`packages/` 产品代码改动默认由 main 新建或派发给非 main Agent 实施，main 负责调研、方案、分工、审阅和集成验证；用户明确要求 main 直接修改时，以该次指令为准，不再创建或转派 Agent。
- 非 main 会话不得给 main 或任何其他 Agent 发消息，不得创建、派遣、等待、读取或管理 Agent，也不得继续分派任务；只执行 main 直接派发的任务，并在自己的最终回复中报告。
- 用户已授权 main 在当前开发范围内按需创建固定角色或其他专项 Agent，无需逐个请求确认；创建 Agent 不扩大用户已授权的产品或开发范围。
- 归档表示会话已经退役。main 不查询、读取、复用或取消归档会话；没有合适的活动 Agent 时直接新建。
- 会话 ID 只记录在 Git 忽略的 `.agents/runtime/yolo-ledger-coordination/team.local.md`。该文件只保存当前活动会话；缺失时创建，活动记录失效时删除。不得把会话 ID 写入 skill、TODO 或其他版本控制文件。

## 角色与文件归属

| 会话 | 负责内容 | 默认可写范围（开发获授权后） |
| --- | --- | --- |
| main | 拆分任务、协调接口、审阅、集成验收、用户沟通、Git 操作 | 根目录文档、`.agents/`、`docs/` 及统一配置；产品代码默认交给非 main Agent，用户明确指定时可直接修改 |
| Core | 领域模型、金额与日期计算、记账与统计规则、核心接口及测试 | `packages/core-swift/` |
| Storage | 本地持久化、迁移、备份恢复、存储适配及测试 | `packages/storage-swift/` |
| Apple | 共享 SwiftUI、iPhone 功能与平台入口、Xcode 工程；保留 Mac 构建兼容 | `packages/ui-swift/`、`apps/` |
| 按需 Agent | main 根据具体任务定义的专项职责 | 由 main 在派活时明确；不得与其他正在工作的 Agent 重叠写入同一文件 |

- 保持 Storage → Core、UI → Core、App 组装各模块的依赖方向。Core 的公开接口由 Core 提出，main 协调使用方后确定；Storage 和 Apple 不直接修改核心包。
- 当前只推进 iPhone 新功能。Apple 不新增 Mac 功能或界面，只按 AGENTS 和实际改动保留必要的 Mac 构建兼容；用户明确恢复 Mac 开发后再扩大范围。
- 非 main 会话可读取其他模块了解上下文；需要跨越写入范围时，只在自己的完成回复中提出建议，由 main 读取后重新分配该次修改的负责人。

## 派活与收取结果

1. main 核对自身资格和本地活动会话记录，只通过活动会话列表确认真实标题、状态和工作目录；不查询归档列表。活动记录不存在或不匹配时删除，任务确有需要时新建 Agent。
2. main 为每个任务明确目标、可写文件、依赖接口、验收方式和允许动作，并重申不得跨 Agent 通信或继续分派。所有 Agent 使用本仓库工作目录和同一工作树；同一文件同时只由一个 Agent 写入。
3. main 使用等待和读取能力主动收取结果。完成回复必须列出修改文件、实现结果、实际验证及结果、未验证部分和需要 main 集成的事项；不得把构建通过描述为启动或真机验收通过。
4. main 汇总差异、完成必要的集成验证、更新 TODO 并向用户报告。非 main 会话不得暂存、commit、push、切换分支或清理工作树；用户要求提交时，main 读取并执行 `$commit-workflow`。

本 skill 只管理开发协作，不创建额度监控、定时唤醒、自动续跑或重复的进度账本。
