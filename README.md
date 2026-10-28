# 有落（YoloLedger）

有落是一款面向 **Mac 和 iPhone** 的个人记账软件，采用 Swift / SwiftUI 原生开发。一个仓库维护 macOS 与 iOS 两个 App，共享核心业务、数据存储和通用界面代码。iPadOS 暂不支持。

## 当前状态

M2 本地手动记账已接入：支持收入／支出新增、编辑、删除，基础账本管理与切换，分类与备注输入，日历明细及按月收支汇总。Mac 和 iPhone 各自在本机保存数据，关闭重开后保留。

支出分类已按用户截图补齐餐饮、交通、购物、宠物、住房、零食、旅行、通讯、医疗、Pos、其它、礼金和运动；另保留原有日用，收入分类不变。已有账库自动补齐新增分类并保留历史记录。

当前页面仍是前一阶段的临时界面，功能与测试结果见 [历史 UI 验收](docs/ui-validation.md)。后续 UI 将使用有落自己的品牌和交互设计，不再以喵喵记账为设计参考。

首版独立图标方向已选择：橙色“记录点”落入象牙色承接页，表达“每一笔，都有落点”；背景采用以 `#0A84FF` 为基准的亮系统蓝。当前方向尚未制作正式 AppIcon 像素资源。见 [品牌与图标](docs/brand/README.md)。

共享 UI 已采用全局语义主题：底部导航、记账键盘和详情背景统一为粉彩浅蓝 `#C6E2FF`，页面不再直接保存 RGB 色值。当前 `.pastel` 主题由双端统一注入，未来可在主题文件中增加暗黑或其他预设并集中切换。

已确认：双端原生开发、`apps/` 下直接按平台划分入口、共享代码按职责拆分，首版使用本地存储。M2 采用 SwiftData 本地持久化，最低系统版本仍待确定；iCloud 同步留待后续按需评估。

M1 使用 Swift 6，临时构建基线为 macOS 14 / iOS 17；产品最低支持范围及旧系统兼容性仍待确认。当前已安装 Xcode 27.1，命令通过 `DEVELOPER_DIR` 显式指定，不修改系统全局开发工具设置。

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

以上为规划范围，具体任务和完成状态见 [开发清单](TODO.md)。Mac 与 iPhone 将采用有落自己的统一品牌语言，并分别适配桌面和移动操作方式。

## 模块关系

`core-swift` 定义模型、业务规则和接口；`storage-swift` 实现存储接口；`ui-swift` 通过核心接口使用数据。两个 App 入口负责组装这些模块和各自的平台能力。

首版各端独立保存本地数据，支持离线使用。M2 使用 SwiftData 保存到本机应用容器，明确关闭 CloudKit；当前开发无需等待 iCloud 方案。后续确定需要同步时，再评估 iCloud 兼容性和已有数据迁移。

手机端日期显示、统计和定时记账跟随手机当前系统本地时区；独立运行的 Mac 按同样原则跟随本机系统时区。定时记账的产品规则和待确认边界记录在 TODO 中。

## 开发入口

- [仓库规则](AGENTS.md)
- [任务与完成记录](TODO.md)
- [双端应用目录](apps/README.md)
- [共享模块目录](packages/README.md)
- [项目文档目录](docs/README.md)
- [工程边界与本地记账](docs/architecture.md)
- [M2 验收记录](docs/m2-validation.md)
- [品牌与图标](docs/brand/README.md)
- [历史 UI 截图与验收](docs/ui-validation.md)
- [main 与子 Agent 协作 skill](.agents/skills/yolo-ledger-coordination/SKILL.md)

开发按五个里程碑推进：M1 双端工程骨架 → M2 本地手动记账闭环 → M3 账目管理与统计 → M4 定时记账与本地备份 → M5 快捷指令与首版验收。具体任务和验收标准见 [TODO](TODO.md)。

## 构建与运行

从仓库根目录执行。已验证的环境为 Xcode 27.1、macOS 27.0.1，以及 iOS 27.0 的 iPhone 18 Pro 模拟器。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build --package-path packages/core-swift
swift build --package-path packages/storage-swift
swift build --package-path packages/ui-swift
swift test --package-path packages/core-swift
swift test --package-path packages/storage-swift
swift test --package-path packages/ui-swift
```

构建并启动 Mac App：

```sh
xcodebuild -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/yolo-ledger-m2-macos build
open /tmp/yolo-ledger-m2-macos/Build/Products/Debug/YoloLedgerMac.app
```

在 iPhone 模拟器中构建并验证手动记账、重启保留、账本切换和导航：

```sh
xcrun simctl list devices available
xcodebuild -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerIOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=2AEB6FA7-B4E7-4A91-86EE-2C942F44F395' \
  -derivedDataPath /tmp/yolo-ledger-m2-ios -parallel-testing-enabled NO test
```

上述模拟器 ID 来自当前 Mac；在其他机器上替换为列表中可用的 iPhone ID。也可打开 `apps/xcode/YoloLedger.xcodeproj`，选择 `YoloLedgerMac` 或 `YoloLedgerIOS` scheme 后运行。独立安装、启动和验证细节见 [Xcode 工程说明](apps/xcode/README.md) 与 [iPhone 入口说明](apps/ios/README.md)。工程不固定个人开发团队；已使用本机现有个人团队通过命令行覆盖参数完成一次真机构建、安装与启动验证。

2026-10-28 UI 重做验证：Core 38 项、UI 状态 9 项测试通过，iPhone 4 项完整流程同轮通过，另补充日期／账本菜单／取消测试；双端 Debug 构建通过。main 已逐屏检查 iPhone 截图并验收 Mac 实际操作。Storage 本轮未改动，保留 M2 的 15 项通过记录。真机、旧系统及参考材料未覆盖的完整页面仍待验收；详见 [UI 验收记录](docs/ui-validation.md) 与 [M2 验收记录](docs/m2-validation.md)。

分类补齐验证：Core 42、Storage 20、UI 状态 9 项测试通过；iPhone 新增 2 项分类专项测试及布局复测通过，双端构建通过。已验证旧账库保留原记录并自动补齐分类；相关界面截图已按用户要求从仓库清理。
