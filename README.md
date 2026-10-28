# 有落（YoloLedger）

有落是一款面向 **Mac 和 iPhone** 的个人记账软件，采用 Swift / SwiftUI 原生开发。一个仓库维护 macOS 与 iOS 两个 App，共享核心业务、数据存储和通用界面代码。iPadOS 暂不支持。

## 当前状态

目前已建立目录结构、仓库规则和开发清单，尚未创建 Xcode 工程、Swift Package manifest 或功能代码，因此暂时没有可运行的 App。

已确认：双端原生开发、`apps/` 下直接按平台划分入口、共享代码按职责拆分，首版使用本地存储。最低系统版本和本地持久化实现仍待确定；iCloud 同步留待后续按需评估。

当前开发设备：Mac mini（Apple M6、24 GB 内存、arm64），系统 macOS 27.0.1（26A434），于 2026-10-28 从本机读取；iPhone 系统为用户确认的 iOS 27。

## 目录结构

```text
yolo-ledger/
├── apps/
│   ├── macos/              # Mac App 入口和桌面适配
│   ├── ios/                # iPhone App 入口和平台适配
│   └── xcode/              # 统一 Xcode 工程及双端构建配置
├── packages/
│   ├── core-swift/         # 数据模型、记账规则、统计逻辑和接口
│   ├── storage-swift/      # 本地存储、迁移、备份与恢复
│   └── ui-swift/           # 共享页面、组件和页面状态
├── docs/                   # 架构、参考材料和验收说明
├── AGENTS.md               # 仓库协作与代码组织规则
├── README.md
└── TODO.md                 # 需求、任务和验证记录
```

各目录通过 README 记录职责和当前状态，后续添加实现时沿用这一结构。

## 功能方向

- 收支记账、账本管理、分类与备注。
- 按周、月、年查看账单、明细和统计。
- 定时记账、账单导入与导出。
- iOS 快捷指令及截图识别记账。
- 本地保存和备份恢复；后续可能加入 iCloud 同步。

以上为规划范围，具体任务和完成状态见 [开发清单](TODO.md)。iPhone 的 UI 与交互先参考喵喵记账；Mac 端适配桌面操作方式。

## 模块关系

`core-swift` 定义模型、业务规则和接口；`storage-swift` 实现存储接口；`ui-swift` 通过核心接口使用数据。两个 App 入口负责组装这些模块和各自的平台能力。

首版各端独立保存本地数据，支持离线使用。SwiftData 是本地持久化候选，当前开发无需等待 iCloud 方案。后续确定需要同步时，再评估 iCloud 兼容性和已有数据迁移。

手机端日期显示、统计和定时记账跟随手机当前系统本地时区；独立运行的 Mac 按同样原则跟随本机系统时区。定时记账的具体行为参考喵喵记账，尚未核实的细节记录在 TODO 中。

## 开发入口

- [仓库规则](AGENTS.md)
- [任务与完成记录](TODO.md)
- [双端应用目录](apps/README.md)
- [共享模块目录](packages/README.md)
- [项目文档目录](docs/README.md)
- [main 与子 Agent 协作 skill](.agents/skills/yolo-ledger-coordination/SKILL.md)

开发按五个里程碑推进：M1 双端工程骨架 → M2 本地手动记账闭环 → M3 账目管理与统计 → M4 定时记账与本地备份 → M5 快捷指令与首版验收。具体任务和验收标准见 [TODO](TODO.md)。构建命令在工程建立并验证后补充。
