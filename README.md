# 有落（YoloLedger）

有落是一款面向 **Mac、iPhone 和 iPad** 的个人记账软件，采用 Swift / SwiftUI 原生开发。一个仓库维护 macOS 与 iOS 两个 App，共享核心业务、数据存储和通用界面代码。

## 当前状态

目前已建立目录结构、仓库规则和开发清单，尚未创建 Xcode 工程、Swift Package manifest 或功能代码，因此暂时没有可运行的 App。

已确认：双端原生开发、`apps/` 下直接按平台划分入口、共享代码按职责拆分。最低系统版本、本地持久化实现和多端同步方案仍待确定。

## 目录结构

```text
yolo-ledger/
├── apps/
│   ├── macos/              # Mac App 入口和桌面适配
│   ├── ios/                # iPhone / iPad App 入口和平台适配
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
- 本地保存、多端共享和备份恢复。

以上为规划范围，具体任务和完成状态见 [开发清单](TODO.md)。iPhone / iPad 的 UI 与交互先参考喵喵记账；Mac 端适配桌面操作方式。

## 模块关系

`core-swift` 定义模型、业务规则和接口；`storage-swift` 实现存储接口；`ui-swift` 通过核心接口使用数据。两个 App 入口负责组装这些模块和各自的平台能力。

数据采用本地优先方向。SwiftData 是持久化候选；若设备使用同一 Apple 账户，优先评估 iCloud 同步。具体实现以确认后的方案为准。

## 开发入口

- [仓库规则](AGENTS.md)
- [任务与完成记录](TODO.md)
- [双端应用目录](apps/README.md)
- [共享模块目录](packages/README.md)
- [项目文档目录](docs/README.md)

后续先创建共享 Swift Packages、统一 Xcode 工程及两个 App 入口，再逐项实现并验证业务功能。构建命令在工程建立并验证后补充。
