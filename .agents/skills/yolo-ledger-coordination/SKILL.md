---
name: yolo-ledger-coordination
description: "在 yolo-ledger 中由 main 协调 Core、Storage、Apple 开发会话，按目录分工、收取结果并集成验收。用于本仓库的多会话开发和分工确认，不用于应用内记账调度。"
---

# 有落开发协作

用户与 `main` 对话，由 main 协调同一仓库中的三个角色会话。先读取根目录 [AGENTS.md](../../../AGENTS.md)、[TODO.md](../../../TODO.md)，派活前查看 [会话登记](references/team.md) 中的 ID、工作目录和当前授权阶段。

## 授权与当前阶段

- 用户已确认本项目的协作 skill 和角色分工，并于 2026-10-28 要求提交配置后派发开发任务。当前按 M1 双端工程骨架开展实现；具体任务与验证状态以根目录 TODO 为准。
- 后续用户在 main 中确认开始某个里程碑，即可由 main 在该范围内连续分工、收取结果和集成，无需逐个子任务重复请求确认。会话登记中创建时的待命状态不覆盖用户的新指令。
- 本 skill 只协调开发会话；不创建额度监控、定时唤醒或自动续跑服务。

## 角色与文件归属

| 会话 | 负责内容 | 默认可写范围（开发获授权后） |
| --- | --- | --- |
| main | 拆分任务、协调接口、集成、验收、用户沟通、Git 操作 | 根目录文档、`.agents/`、`docs/` 及统一配置；跨模块修改先协调文件归属 |
| Core | 领域模型、金额与日期计算、记账与统计规则、核心接口及测试 | `packages/core-swift/` |
| Storage | 本地持久化、迁移、备份恢复、存储适配及测试 | `packages/storage-swift/` |
| Apple | 共享 SwiftUI 页面、Mac / iPhone 入口、平台能力、Xcode 工程及双端验证 | `packages/ui-swift/`、`apps/` |

- `core-swift` 是共享依赖：公开接口由 Core 提出，main 协调使用方后确定。Storage 和 Apple 不直接修改核心包。
- Apple 统一持有共享 UI 和两个 App，避免 Mac、iPhone 会话并发修改同一套组件或 Xcode 工程。
- 保留现有依赖方向：Storage → Core，UI → Core，App 组装各模块。接口的进一步细化遵循 TODO 中的暂缓安排，不为 M1 提前设计完整数据库契约。
- 子会话可读取其他模块了解上下文；需要跨越写入范围时，将建议交给 main，由 main 重新分配该次修改的负责人。
- 根目录 TODO 和总 README 由 main 统一更新；子会话在完成回复中给出待勾选事项和模块内验证记录。

## 派活与收取结果

1. 使用 `list_threads` / `read_thread` 核对登记会话的真实标题、状态和工作目录。只复用属于当前 `yolo-ledger` 的角色会话，不向参考项目的会话发任务。
2. 每次通过 `send_message_to_thread` 给出具体目标、里程碑、可写文件、依赖接口、验收方式及当前允许的动作。只读确认任务明确要求不改文件、不运行开发、不创建更多会话。
3. 三个角色共用同一工作目录和 Git 工作树。并发任务只写各自负责的文件；同一文件由一人写。需要变更另一个角色正在使用的接口或 Package manifest 时，由 main 协调顺序。
4. 用 `wait_threads` 等待完成或需要关注的状态，必要时使用 `read_thread` 获取细节。main 主动收取结果，子会话在自己的回复中报告，不要求子会话主动给 main 或其他会话发送消息。
5. 完成回复包含：修改文件、实现结果、实际运行的验证及结果、未验证部分、需要 main 集成的事项。不要将仅构建通过描述成已完成启动或真机验收。
6. main 汇总差异、验证依赖和双端集成，更新 TODO 并向用户报告。子会话不执行暂存、commit、push、分支切换或工作树清理；Git 操作由 main 按用户授权统一处理。通用提交流程统一维护在用户级 `$commit-workflow` skill；提交时读取该 skill，本文件只规定本仓库的 Git 操作归属。

优先复用现有角色会话。仅在用户授权新增且现有会话确实无法复用时创建替代会话，并更新登记。任务进度继续使用 TODO 和各会话上下文，不另建重复的进度账本。

## 获准后的 M1 分工

- Core：创建并验证 `YoloLedgerCore` 的 Swift Package 骨架。
- Core 的包入口可用后，Storage 创建依赖 Core 的 `YoloLedgerStorage` 骨架；Apple 创建依赖 Core 的 `YoloLedgerUI` 骨架，两者按目录并行。
- 三个包可解析后，Apple 创建统一 Xcode 工程、Mac 与 iPhone 入口及页面占位，分别验证构建与启动。
- main 负责协调构建基线、共享包依赖与结果收口；产品最低支持版本未确认时，明确区分临时构建基线和正式兼容性承诺。首版本地存储、iPadOS 暂不支持、iCloud 后续可选等范围遵循根目录文档。
