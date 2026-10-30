---
name: yolo-ledger-device-install
description: "在 yolo-ledger 中构建、安装并验证 iPhone 真机 Debug 版。用于用户要求安装到已连接手机、重新安装真机包或启动真机应用；不用于模拟器、发布归档或 App Store 分发。"
---

# 有落 iPhone 真机安装

为当前工作树构建 `YoloLedgerIOS` Debug 版，安装到用户明确要求的已连接 iPhone，并区分报告“构建成功”“安装成功”和“启动成功”。先读取仓库根目录 `AGENTS.md`；本流程不授权修改功能、证书、Git 远端或提交记录。

## 边界与隐私

- 仅支持物理 iPhone；不要把同型号模拟器误认为真机，iPadOS 不在本仓库支持范围内。
- 不卸载旧 App。直接安装更新以保留本机应用数据，除非用户明确要求清除。
- 不把设备名称、UDID、Apple 账号、开发团队 ID、证书标识、描述文件 UUID 或安装容器路径写入仓库、TODO、提交信息或用户回复。
- 工程不保存个人 `DEVELOPMENT_TEAM`。签名值只作为本次命令参数传入，不修改 `.pbxproj`。
- 若连接了多台物理 iPhone 且无法从用户上下文确定目标，先让用户选择；没有已连接真机时停止并说明。

## 安装流程

1. 使用 `xcrun devicectl list devices` 查找 `Reality` 为 `physical`、状态为 `connected` 的 iPhone，并保存本次命令使用的设备标识。不要选 `simulated` 行。
2. 检查本机现有签名材料，不要从证书显示名称猜团队 ID。优先在以下目录查找与 `com.yololedger.app` 匹配的 `.mobileprovision`：
   - `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
   - `~/Library/MobileDevice/Provisioning Profiles/`
3. 使用 `security cms -D -i <profile>` 解码描述文件，并读取 `TeamIdentifier[0]`；同时确认 `Entitlements.application-identifier` 以 `.com.yololedger.app` 结尾，并包含共享 iCloud Container 权限。
   - `Apple Development: ... (<标识>)` 中括号内的值可能是证书用户标识，不一定是 `DEVELOPMENT_TEAM`。
   - 以描述文件的 `TeamIdentifier` 为准。不要把实际值写入仓库。
4. 使用独立的 `/tmp/yolo-ledger-...` Derived Data 目录构建真机 Debug 版。命令形态如下，运行时替换占位值，不将其原样执行：

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -project apps/xcode/YoloLedger.xcodeproj \
     -scheme YoloLedgerIOS \
     -configuration Debug \
     -destination 'platform=iOS,id=<DEVICE_ID>' \
     -derivedDataPath /tmp/yolo-ledger-device-build \
     DEVELOPMENT_TEAM=<PROFILE_TEAM_IDENTIFIER> \
     CODE_SIGN_STYLE=Automatic \
     -allowProvisioningUpdates \
     build
   ```

5. 仅在构建成功后安装产物：

   ```sh
   xcrun devicectl device install app \
     --device <DEVICE_ID> \
     /tmp/yolo-ledger-device-build/Build/Products/Debug-iphoneos/YoloLedgerIOS.app
   ```

6. 安装成功后启动并验证 Bundle ID：

   ```sh
   xcrun devicectl device process launch \
     --device <DEVICE_ID> \
     com.yololedger.app
   ```

## 失败处理与汇报

- `requires a development team`：确认构建命令传入了描述文件的 `TeamIdentifier`；不要因此把团队写进工程。
- `No Account for Team` 或找不到 profile：先检查是否误用了证书名称中的个人标识，再检查匹配 Bundle ID 的描述文件和 Xcode 账号状态。
- 安装失败时保留构建结果和原始错误，不卸载 App、不清理用户数据、不反复更换签名。
- 启动失败不等同于安装失败；分别报告 CoreDevice 返回的构建、安装、启动结果。
- 成功回复只需说明当前 Debug 版已安装并启动、Bundle ID 为 `com.yololedger.app`，以及是否包含当前工作树未提交改动；不要回显上述个人或设备标识。
