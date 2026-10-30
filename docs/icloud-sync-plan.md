# iCloud 同步与用户可见目录方案

## 1. 目标与结论

有落继续使用 SwiftData 作为本地数据库，通过 CloudKit 私有数据库在原生 iPhone 与 Mac App 之间自动同步；同时启用 iCloud Documents，在“文件”App 和 Finder 的 iCloud 云盘中提供用户可见的“有落”目录。

当前结论如下：

- iPhone 与 Mac 两个 Target 统一使用 Bundle ID：`com.yololedger.app`。
- 两端共同使用 iCloud Container：`iCloud.com.yololedger.app`。
- CloudKit 负责结构化账本数据的自动同步，不向用户暴露数据库文件。
- iCloud Drive 显示名为“有落”的目录，用于备份、CSV、附件和其他用户可识别文件。
- 不把运行中的 SwiftData / SQLite 数据库直接放入 iCloud Drive。
- 不建立有落自己的登录系统，使用设备当前 Apple Account 的 iCloud 能力。
- 当前只有测试数据，不采用两次正式发布的过渡方案，直接迁移为 CloudKit 兼容模型。
- 远端数据导入后自动刷新界面，不要求用户手动点击同步。
- iPadOS 暂不支持。

当前实现进度：代码、entitlements、Info.plist 与双端 Target 配置已接入；Core 42 项、Storage 22 项、UI 10 项测试及 iPhone 模拟器导航冒烟通过，iOS 模拟器和 macOS Debug 构建通过，模拟器也已用正常 CloudKit 配置打开本地账库。共享容器注册、Development CloudKit Schema、真实 Apple Account、双设备同步和用户可见目录仍待签名环境验收，不能仅凭本地构建视为完成。

## 2. 整体结构

```text
iPhone / Mac
├── 本地 SwiftData
│   └── Application Support/YoloLedger/ledger.store
│
└── iCloud.com.yololedger.app
    ├── CloudKit Private Database
    │   ├── BookRecord
    │   ├── CategoryRecord
    │   └── EntryRecord
    │
    └── iCloud Drive/有落（容器的 Documents 目录）
        ├── 关于有落.txt
        ├── 有落备份.yololedger
        ├── 账单导出.csv
        └── 后续附件
```

每台设备仍保留一份本地数据库，读取和写入不依赖网络。CloudKit 在系统允许的时机上传本地变更、下载远端变更；iCloud Documents 是另一套文件同步能力，只承载用户能够识别和直接管理的文件。

## 3. 标识与发布方式

### 3.1 Bundle ID

两个平台统一为：

```text
com.yololedger.app
```

iPhone 与 Mac 仍保留独立 Target、入口和平台适配代码。统一 Bundle ID 用于把两端作为 App Store Connect 中同一产品的多平台版本发布，并支持 Universal Purchase。

修改 Bundle ID 后，系统会把已经安装的旧测试 App 视为另一款 App，旧测试容器不会自动继承。由于当前只有测试数据，可重新安装并重新生成测试数据；正式发布后不再修改 Bundle ID。

### 3.2 iCloud Container

两个平台共同使用：

```text
iCloud.com.yololedger.app
```

该标识是 iCloud 容器标识，不是用户看到的文件夹名称。创建前需要确认 Apple Developer 账户可以注册该标识；注册并用于正式环境后保持稳定。

## 4. 两类 iCloud 数据的职责

| 能力 | 用途 | 用户能否直接看到 | 存储形式 |
| --- | --- | --- | --- |
| SwiftData 本地存储 | 离线读写、启动和本机缓存 | 否 | SQLite 主文件、WAL、SHM |
| CloudKit Private Database | Mac 与 iPhone 的结构化数据同步 | 否 | CloudKit Schema 与 CKRecord |
| iCloud Documents | 备份、导出、附件等用户文件 | 是 | 文件或文件包 |

CloudKit 同步不是备份替代品：修改和删除也会传播到其他设备。独立备份导出与恢复仍需按 `TODO.md` 的 M4 任务实现。

## 5. SwiftData 模型调整

当前 V1 模型的 `BookRecord.id`、`CategoryRecord.id`、`EntryRecord.id` 和 `StoreMetadata.key` 使用 `@Attribute(.unique)`。CloudKit 不支持 SwiftData 唯一约束，接入前需要调整。

计划如下：

1. 保留业务 UUID，但移除 `@Attribute(.unique)`。
2. 由 Storage Repository 在创建和合并时检查业务 UUID，保证单机操作不产生重复数据。
3. 为需要参与冲突判断的账本、分类和账目保留或补齐 `createdAt`、`updatedAt`、`deletedAt`。
4. 删除优先采用软删除；确认多端收敛后再考虑物理清理。
5. 所有 CloudKit 模型属性提供兼容的默认值或可选形式。
6. 如后续增加 SwiftData 关系，关系必须可选并明确 inverse；不使用 CloudKit 不支持的 Deny 删除规则。
7. 保留版本化 Schema 和升级前快照机制，但本轮允许清理现有测试库及 Development CloudKit 数据重新初始化。

## 6. 自动同步与界面刷新

SwiftData / CloudKit 的同步时机由系统决定，应用不能承诺“点击后立即同步”。有落应实现自动刷新：

1. 启动时读取本地数据库并检查 iCloud 账户状态。
2. 监听 CloudKit setup、import、export 事件。
3. 远端 import 成功后，由 Storage 通知 UI 重新获取账本、分类和账目。
4. App 从后台回到前台时再进行一次轻量刷新。
5. 本地新增、编辑和删除完成后继续立即刷新当前界面，不等待云端确认。

设置页只显示状态，不提供不能保证生效的“立即同步”按钮。建议状态包括：

- iCloud 可用，已开启自动同步。
- 正在上传或下载。
- 最近一次同步成功时间。
- 未登录 Apple Account、iCloud 权限关闭、空间不足或服务暂时不可用。
- 同步暂停时仍可在本机记账。

这里的“未登录”只指设备没有可用的 Apple Account / iCloud，不是有落账号。有落不新增独立账号体系。

## 7. 首次合并与冲突规则

虽然当前只有测试数据，正式实现仍需建立可重复验证的规则：

- 使用业务 UUID 识别同一账本、分类和账目。
- 相同 UUID 出现多个持久化对象时，以较新的 `updatedAt` 为主。
- 时间相同时使用固定的稳定排序规则选择结果，避免不同设备得出不同结论。
- `deletedAt` 晚于 `updatedAt` 时视为已删除。
- 默认账本和内置分类使用稳定 UUID，并在远端导入后去重。
- 定时记账后续使用“规则 ID + 周期 ID”作为幂等键，避免多设备生成同一笔账。
- 冲突处理和去重放在 Storage 层，Core 只保存业务规则，UI 不直接处理 CloudKit Record。

## 8. 用户可见的“有落”目录

在 iOS 与 macOS Target 中启用 iCloud Documents，并在 `Info.plist` 为 `iCloud.com.yololedger.app` 配置：

```xml
<key>NSUbiquitousContainers</key>
<dict>
    <key>iCloud.com.yololedger.app</key>
    <dict>
        <key>NSUbiquitousContainerIsDocumentScopePublic</key>
        <true/>
        <key>NSUbiquitousContainerName</key>
        <string>有落</string>
        <key>NSUbiquitousContainerSupportedFolderLevels</key>
        <string>Any</string>
    </dict>
</dict>
```

应用需要创建容器中的 `Documents` 目录，并至少写入一个用户文档后，系统才会在 iCloud 云盘中显示“有落”。容器元数据变更时需要提升 App 的 build 版本。

目录中可以放置：

- 完整备份文件，例如 `有落备份-2026-10-30.yololedger`。
- CSV 或其他可交换格式的账单导出。
- 后续由用户添加并能够直接识别的附件。

目录中不得放置：

- 正在运行的 `ledger.store`。
- `ledger.store-wal`、`ledger.store-shm`。
- 可重新生成的缓存、临时文件和内部状态文件。

如果未来允许用户在“文件”App中直接打开 `.yololedger` 文件，需要再声明自定义 UTType、支持 Open in Place，并通过 `UIDocument`、`NSDocument` 或文件协调 API 安全读写。

## 9. 工程配置

两个 App Target 均需关联同一容器，并配置：

- iCloud：CloudKit。
- iCloud：iCloud Documents。
- Push Notifications。
- Background Modes：Remote notifications。
- 对应的 iCloud Container、服务和环境 entitlements。

SwiftData 配置从本地模式：

```swift
cloudKitDatabase: .none
```

改为显式私有数据库：

```swift
cloudKitDatabase: .private("iCloud.com.yololedger.app")
```

测试仍需支持注入 `.none` 或独立测试账库，避免单元测试读写真实 iCloud。

## 10. 开发与上线顺序

1. 统一两个 Target 的 Bundle ID。
2. 创建并关联共享 iCloud Container。
3. 调整 SwiftData Schema，移除唯一约束并补齐同步字段。
4. 更新 Storage 配置并初始化 Development CloudKit Schema。
5. 接入同步状态监听和 UI 自动刷新。
6. 实现业务 UUID 去重、软删除和冲突规则。
7. 发布用户可见的“有落”iCloud Documents 目录。
8. 完成模拟器、真机 iPhone 和真实 Mac 的双端验证。
9. 在 CloudKit Console 检查 Development Schema。
10. 上线前将 Schema 部署到 Production；生产 Schema 只做向前兼容的新增，不删除或重命名既有类型和字段。

## 11. 验收标准

- iPhone 离线新增账目，恢复网络后自动出现在 Mac。
- Mac 修改账目后，iPhone 无需手动同步即可刷新。
- 两端同时新增、修改或删除时结果符合确定的冲突规则。
- 默认账本、分类和相同 UUID 的账目不会重复显示。
- 没有 Apple Account、关闭 iCloud 或服务暂时不可用时，本地记账仍正常。
- iCloud 空间不足时显示可理解的状态，不清空本地数据。
- 覆盖安装、重启和重新登录 iCloud 后数据保持完整。
- “文件”App 和 Finder 的 iCloud 云盘中能够看到“有落”目录及导出文件。
- 用户删除可见备份文件不会直接删除 CloudKit 中的当前账目。
- Development 与 Production 环境分别完成验证。

## 12. 官方参考

- [Apple：添加多平台版本与 Universal Purchase](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)
- [Apple：准备多平台 App 发布](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Apple：SwiftData 跨设备同步](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Apple：配置 iCloud 服务](https://developer.apple.com/documentation/xcode/configuring-icloud-services)
- [Apple：同步 iCloud Documents 并发布公开目录](https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment)
- [Apple：iOS 存储最佳实践](https://developer.apple.com/videos/play/tech-talks/204/)
- [Apple：调试 NSPersistentCloudKitContainer 同步](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)
