# Xcode 工程

`YoloLedger.xcodeproj` 管理原生 Mac 与 iPhone App，直接引用三个本地 Swift Packages，无外部依赖或工程生成器。

## 产品与组装

| Scheme / target | 产品 | Bundle ID |
| --- | --- | --- |
| YoloLedgerMac | 原生 Mac App | com.yololedger.macos |
| YoloLedgerIOS | iPhone App | com.yololedger.ios |
| YoloLedgerMacUITests | Mac 导航测试 target | com.yololedger.macos.uitests |
| YoloLedgerIOSUITests | iPhone 导航及记账流程测试 | com.yololedger.ios.uitests |

显示名“有落”，英文名 `YoloLedger`。iOS 仅面向 iPhone，关闭 iPad、Mac Catalyst、Designed for iPhone on Mac 和 Vision 兼容入口；Mac 使用独立原生 target。

`Support/LedgerAppBootstrap.swift` 同时编入两个 App，长期持有 `SwiftDataLedgerRepository` 并注入共享 UI。默认位置为各 App 容器的 `Application Support/YoloLedger/ledger.store`。打开失败显示错误和重试，不回退内存、不清库、不调用 fatalError。当前仅本地保存，未接入 iCloud。

当前已有本地新增收支、编辑、确认删除、基本账本管理、月收支汇总与日历筛选。UI 按[喵喵记账参考材料](../../docs/references/meow-ledger/README.md)重做为纸张、描边、圆形分类、黄色数字键盘和票据样式；未展示的参考页面按同一视觉组件适配。功能与状态见 [UI 模块](../../packages/ui-swift/README.md)。

工具 Xcode 27.1（27A9275）、Swift 6。临时构建基线 macOS 14 / iOS 17，正式最低支持范围待确定。Mac 与模拟器使用本地 ad-hoc 签名，无个人团队或证书；真机另行配置与验收。

## 构建

从仓库根目录执行，每次显式指定完整 Xcode，不修改全局 `xcode-select`。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/yolo-ledger-meow-macos build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerIOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/yolo-ledger-meow-ios build
```

产物分别位于 `/tmp/yolo-ledger-meow-macos/Build/Products/Debug/YoloLedgerMac.app` 与 `/tmp/yolo-ledger-meow-ios/Build/Products/Debug-iphonesimulator/YoloLedgerIOS.app`。

## 独立测试账库

DEBUG 参数 `--ui-test-store <UUID>` 写入同一容器下的 `Application Support/YoloLedger/UITests/<UUID>/ledger.store`。同一 UUID 重启保留数据，不同 UUID 与日常账库隔离。UUID 无效时显示启动错误，不回退日常账库；测试不清理已有账库。

例如启动新的 Mac 验收账库：

```sh
open -n /tmp/yolo-ledger-meow-macos/Build/Products/Debug/YoloLedgerMac.app \
  --args --ui-test-store 793D8F42-6503-4F04-9C89-225BF2385B4A
```

`--ui-test-fail-open-once` 仅在 DEBUG 模拟一次打开失败。测试验证错误、没有编辑入口，以及重试后打开真实磁盘仓库。

## iPhone 流程测试

`Tests/NavigationSmokeTests.swift` 每个用例生成独立 UUID，重启使用同一 UUID。覆盖导航和取消、真实日期／账本选项、账本新建／重命名／切换、收入、非法金额保持输入、精确加减保存、日历日／月筛选、编辑、重启保留、确认删除及删除后再次重启、启动失败重试。

本轮设备为 iPhone 18 Pro / iOS 27.0：`2AEB6FA7-B4E7-4A91-86EE-2C942F44F395`。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerIOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=2AEB6FA7-B4E7-4A91-86EE-2C942F44F395' \
  -derivedDataPath /tmp/yolo-ledger-meow-ios \
  -resultBundlePath /tmp/yolo-ledger-meow-ios-flows-final.xcresult \
  -parallel-testing-enabled NO test
```

重复执行需要新的 `.xcresult` 路径。仅运行导航／选项可加 `-only-testing:YoloLedgerIOSUITests/NavigationSmokeTests/testFourDestinationsAreReachable`。

## 喵喵样式重做验证（2026-10-28）

- UI 模型 9 项测试通过，包含原有保存与失败语义，以及新增的日历筛选、浏览月份保留和保存后可见性。
- Mac arm64 Debug 构建通过；iPhone 模拟器 App 与 UI 测试 target 构建通过。
- `/tmp/yolo-ledger-meow-ios-flows-final.xcresult` 的 4 项流程同一轮全部通过：四页导航与取消；账本／收入隔离；新增 `12.34+7.66-5=15.00`、日历筛选、编辑 `23.45`、重启、删除；启动失败重试。
- 该轮截图已导出至 `/tmp/yolo-ledger-meow-ios-final-screens/`，包括 `01-bills.png`、`02-details.png`、`03-books.png`、`04-settings.png`、`05-editor-calculator.png`、`06-calendar-selected-day.png`、`entry-created.png`、`entry-edited-detail.png`、`entry-persisted-after-relaunch.png`。均为独立测试数据。
- 最后调整底栏描边遮挡顺序与日历顶部留白后，`/tmp/yolo-ledger-meow-ios-navigation-final.xcresult` 的扩展导航用例通过，额外验证日期选择面板、账本菜单选项和取消；最新四页截图在上述目录的 `latest-navigation/` 中。最终 Mac 构建日志为 `/tmp/yolo-ledger-meow-macos-final-build.log`。
- 第一轮仅账本重命名用例因测试点击旧输入框坐标未聚焦而失败，改为点击新输入框中心后第二轮全过；没有以修改业务数据绕过失败。
- main 已核对本轮六类 iPhone 实际截图，视觉通过；Mac native 验证 Cmd+N、`12.34+7.66-5` 保存为 `15.00`、中文备注和日期筛选正常。Apple 子会话未使用系统 UI 自动化或将旧样式验收充作本轮结果。Mac 空态已单独使用左侧“记一笔”的平台文案。
- Mac XCTest 未重跑：M1 的系统 automation mode 初始化曾超时；Mac 由 main 使用 native 操作。真机、正式最低系统、Release 分发、iCloud 尚未验收。

M2 重做前的验证保留于 [M2 验收记录](../../docs/m2-validation.md)及历史 `/tmp/yolo-ledger-m2-*.xcresult`，与本轮 UI 验收区分。

## 实机截图分类补齐验证（2026-10-28）

共享 UI 补齐用户截图的分类插画，支出按 Core 的 13 个截图分类加末尾保留的“日用”排列，收入保持 3 类。四列网格使用最大 70 点、随可用列宽等比缩放的圆形按钮，iPhone 18 Pro 一屏完整显示四行；较小窗口保留独立分类滚动区，键盘固定在下方。“设置”属于管理入口，本轮未作为分类或占位按钮加入。

- UI 状态测试 9 项通过，日志 `/tmp/yolo-ledger-categories-ui-tests.log`。
- 两项针对性 iPhone 用例在 `/tmp/yolo-ledger-categories-ios.xcresult` 同轮通过：逐个选中 14 支出／3 收入并验证末行未被键盘遮挡；保存末行“运动”12.34 与“宠物”6.78 后重启，详情的分类、金额和备注仍正确。每个用例使用独立 UUID 账库。
- 最后收紧行距、简化蓝色听筒并接入随列宽缩放后，仅重跑相关分类可选性测试，`/tmp/yolo-ledger-categories-ios-responsive-final.xcresult` 通过，未重复无关流程。
- 最终分类截图在 `/tmp/yolo-ledger-categories-ios-screens/final/`：`categories-expense-top.png`、`categories-expense-last-row.png`、`categories-income.png`。已实际查看，14 支出四行完整显示；上一级的 `category-persisted-运动.png`、`category-persisted-宠物.png` 为重启后详情。
- 最终 Mac 构建通过，日志 `/tmp/yolo-ledger-categories-macos-final-build.log`，产物 `/tmp/yolo-ledger-categories-macos/Build/Products/Debug/YoloLedgerMac.app`。iPhone 产物 `/tmp/yolo-ledger-categories-ios/Build/Products/Debug-iphonesimulator/YoloLedgerIOS.app`。

本轮 Apple 侧未操作 Mac UI、未新增真机验收；已有库种子升级由 Storage 模块单独验证。
