# iPhone App

`Sources/YoloLedgerIOS/YoloLedgerIOSApp.swift` 是 iPhone 原生入口，由 `YoloLedgerIOS` target 构建。入口持有共享 App 启动状态，打开真实 SwiftData 本地磁盘仓库，再注入共享页面。

当前支持收入／支出新增、详情、编辑、确认删除、基础账本管理与切换，以及当前月收支汇总。默认账本与分类由存储层初始化；运行中的 SwiftData 账库始终位于 App 本地容器。用户可在“我的”中选择 iCloud Drive 或普通可写文件夹进行变更交换，iPadOS 暂不支持。

当前 iPhone 版本只使用浅色外观：Target 通过 `UIUserInterfaceStyle = Light` 锁定系统界面，SwiftUI 根视图同时声明浅色方案，因此系统键盘、弹窗和共享页面不会随手机深色模式切换。未来正式完成暗黑主题后，再移除该锁定并增加对应的全局 `LedgerTheme` 预设。

`ScreenshotLedgerIntent.swift` 提供 iOS 快捷指令“截图记账”：通过 Vision 在设备端 OCR，将结构化候选结果暂存并打开共享记账确认页。原图不写入账库；完整配置与验收边界见 [快捷指令截图记账说明](../../docs/screenshot-shortcut.md)。

截图记账先在后台识别并暂存候选结果，再请求系统转到前台确认。iOS 26 及以上使用 `supportedModes = [.background, .foreground(.dynamic)]` 和 `continueInForeground(alwaysConfirm: false)`，取消 App 强制要求的“Cancel / Continue”确认，在系统允许时直接进入记账确认页；Apple 仍可能根据运行条件要求确认，不能保证所有场景均无系统提示。iOS 17–18 保留 `ForegroundContinuableIntent` 的 `requestToContinueInForeground` 兼容路径，该接口没有 `alwaysConfirm` 参数，且 `openAppWhenRun = false`，避免把前台启动作为 OCR 的前置条件。无法转到前台时提示手动解锁并打开 App，待确认结果保留到 App 真正进入前台。识别完成仍需用户确认保存，不会直接写入账库。

快捷指令继续使用“截取屏幕 → 有落记账的截图记账”，无需另加“打开 App”。Intent 类型 `ScreenshotLedgerIntent`、参数 `screenshot` 与 Bundle ID 均保持不变，已有快捷指令可继续使用。

2026-11-07 启动故障复核：真机系统明确以 `invalid code signature / inadequate entitlements / profile not explicitly trusted` 拒绝启动 App，属于已安装包的签名、权限或描述文件信任问题。使用当前工程 entitlements 和 Xcode 自动签名覆盖安装后，App 构建、安装、启动成功；同一快捷指令未改配置，重新运行已进入 OCR，随后提示“截图中没有识别到文字”。这验证了启动拒绝已解除，尚不代表有效支付截图到确认保存的完整链路已通过。没有证据表明本次故障源于旧快捷指令缓存，无需删除重建动作；前台兼容逻辑也不能修复无效签名。遇到同类系统错误应核对签名与设备信任状态，并覆盖安装有效签名版本；不要卸载 App，以免删除本地账库。

启动策略依据 Apple 的 [App Intents 运行方式](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents) 与 [旧系统前台继续接口](https://developer.apple.com/documentation/appintents/foregroundcontinuableintent)。前台切换受设备锁定、系统条件及用户选择约束，构建通过不代表真机“轻点背面”链路已验收。

“我的”页面提供“轻点两下，截图记账”配置入口。用户首次在快捷指令中组合“截取屏幕 → 有落记账截图”，再到系统“轻点背面”绑定；iOS 不允许 App 自动修改该系统设置。

Bundle ID：`com.yololedger.app`，与 Mac Target 保持一致。`TARGETED_DEVICE_FAMILY=1`，关闭 Mac Catalyst、Designed for iPhone on Mac 和 Vision 兼容入口。工程临时构建基线为 iOS 17，正式最低支持版本仍待确定。

选定文件夹后会立即同步，App 打开、回到前台及本地记账变更后也会尝试同步。iOS 会提交 `BGAppRefreshTask`，但后台执行时机由系统决定，不保证实时或每次都执行。书签失效时界面会要求更换文件夹；同步失败不阻断本地记账。

iPhone 流程测试使用 DEBUG 参数 `--ui-test-store <UUID>`，每个用例生成独立磁盘账库，重启使用同一 UUID，不清理日常数据。构建、测试命令和本次结果见 [Xcode 工程说明](../xcode/README.md)。iPhone 真机尚未验证。

2026-10-28：iPhone 18 Pro / iOS 27.0 模拟器构建通过，四页导航、账本／收入／切换隔离、打开失败重试三个流程通过；新增、编辑、重启保留、确认删除及删除后再次重启的完整生命周期单独复验通过。4 个场景分次通过，报告与截图位置记录在工程说明中。
