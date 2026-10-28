# Xcode 工程

`YoloLedger.xcodeproj` 统一管理原生 macOS 与 iPhone App，直接打开即可解析三个本地 Swift Packages，无外部包或工程生成器依赖。

## 工程与产品

| Scheme / target | 产品 | Bundle ID |
| --- | --- | --- |
| YoloLedgerMac | YoloLedgerMac.app | com.yololedger.macos |
| YoloLedgerIOS | YoloLedgerIOS.app | com.yololedger.ios |
| YoloLedgerMacUITests（归属 Mac scheme） | Mac 导航 smoke 测试 | com.yololedger.macos.uitests |
| YoloLedgerIOSUITests（归属 iOS scheme） | iPhone 导航 smoke 测试 | com.yololedger.ios.uitests |

两个 App 的显示名为“有落”，`CFBundleName` 为 `YoloLedger`。平台入口分别位于 `../macos/` 和 `../ios/`；引用的本地包为 `../../packages/{core-swift,storage-swift,ui-swift}`。

iOS target 仅面向 iPhone（`TARGETED_DEVICE_FAMILY=1`），关闭 iPad、Mac Catalyst、Designed for iPhone on Mac 和 Vision 兼容入口。Mac 为独立原生 target。当前仅有 M1 页面占位，两个入口注入空账本仓库，尚无真实持久化、CRUD 或 iCloud。

当前工具为 Xcode 27.1（27A9275），Swift 6；临时工程构建基线是 macOS 14 / iOS 17，正式最低支持版本仍待确认。Debug 只构建当前运行架构，Release 保留标准架构设置。Mac 和模拟器使用本地 ad-hoc 签名，工程不包含个人开发团队或证书配置；真机运行须配置对应签名后单独验证。

## 构建

以下命令在仓库根目录执行，每条命令显式选择完整 Xcode，不修改全局 `xcode-select`。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/yolo-ledger-m1-macos build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerIOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/yolo-ledger-m1-ios build
```

本次 Debug 产物：

- Mac：`/tmp/yolo-ledger-m1-macos/Build/Products/Debug/YoloLedgerMac.app`
- iPhone 模拟器：`/tmp/yolo-ledger-m1-ios/Build/Products/Debug-iphonesimulator/YoloLedgerIOS.app`

Mac 产物可用 `open /tmp/yolo-ledger-m1-macos/Build/Products/Debug/YoloLedgerMac.app` 启动。iPhone 模拟器运行可通过 Xcode 的 YoloLedgerIOS scheme；本次使用设备 ID `2AEB6FA7-B4E7-4A91-86EE-2C942F44F395`（iPhone 18 Pro / iOS 27.0）。

## 导航 smoke 验证

`Tests/NavigationSmokeTests.swift` 通过实际点击四个导航入口，断言页面内容后返回账单，并将每页截图作为附件保留。两条命令分别验证 iPhone 与 Mac；重复运行时请使用新的 `.xcresult` 路径，Xcode 不覆盖已有结果。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerIOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=2AEB6FA7-B4E7-4A91-86EE-2C942F44F395' \
  -derivedDataPath /tmp/yolo-ledger-m1-ios \
  -resultBundlePath /tmp/yolo-ledger-m1-ios-navigation.xcresult \
  -parallel-testing-enabled NO test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project apps/xcode/YoloLedger.xcodeproj -scheme YoloLedgerMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/yolo-ledger-m1-macos \
  -resultBundlePath /tmp/yolo-ledger-m1-macos-navigation.xcresult \
  -parallel-testing-enabled NO test
```

## 实际结果（2026-10-28）

| 检查 | 结果 |
| --- | --- |
| 工程解析和三个本地包依赖 | 通过；无外部包依赖 |
| YoloLedgerUI 独立构建与模型测试 | 构建通过，4 项测试通过，含取消旧请求后重新加载的竞态 |
| Mac arm64 Debug / iOS Simulator Debug 构建 | 均通过 |
| Mac App 实际启动 | 已启动，显示中文侧边栏与账单空页 |
| iPhone 模拟器实际启动与四页点击 | 1 项 XCUITest 通过，含四页截图和返回账单 |
| Mac XCUITest | runner 初始化失败：`Timed out while enabling automation mode`，导航用例未执行 |
| Mac 四页实际点击 | main 使用 native computer-use 依次点击明细、账本、设置、账单，核对窗口标题、选中行与内容，并检查截图，实际验收通过 |
| 真机、正式最低系统、Release 分发、完整业务界面 | 未验证／未实现 |

iPhone 导航结果位于 `/tmp/yolo-ledger-m1-ios-navigation.xcresult`，截图已导出至 `/tmp/yolo-ledger-m1-ios-screenshots/`。Mac runner 失败记录位于 `/tmp/yolo-ledger-m1-macos-navigation.xcresult`；Mac 实际点击的补充证据来自 main 的 native computer-use 验收，不能与 XCTest 结果混淆。

本次代表截图：

- Mac 账单窗口：`/tmp/yolo-ledger-m1-macos-screenshots/app-bills.png`（main 实际点击验收后的单独 App 窗口截图）。
- iPhone 账单：`/tmp/yolo-ledger-m1-ios-screenshots/D2AF44A0-57E8-4F6B-BF41-EDB8BFC84BF9.png`。
- iPhone 账本：`/tmp/yolo-ledger-m1-ios-screenshots/EA876EFF-F895-43F0-96B6-5EF4543862BB.png`。
