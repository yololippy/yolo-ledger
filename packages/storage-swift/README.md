# 本地存储模块

Swift Package、library product 和模块名均为 `YoloLedgerStorage`，依赖本地 [core-swift](../core-swift/README.md) 中的 `YoloLedgerCore`。

## M2 本地仓库

`SwiftDataLedgerRepository` 实现 Core 的 `LedgerRepository`，可由 Mac / iPhone App 创建一次并注入共享界面：

```swift
import YoloLedgerCore
import YoloLedgerStorage

let storeURL = try SwiftDataLedgerRepository.defaultStoreURL()
let repository: any LedgerRepository = try SwiftDataLedgerRepository(
    storeURL: storeURL
)
let books = try await repository.fetchBooks()
```

公开初始化接口：

- `init(storeURL:syncMode:) throws`：打开指定的真实磁盘数据库；默认 `.local`，文件夹同步不依赖 CloudKit 或 iCloud entitlement。旧的 `YoloLedgerICloud.syncMode` 配置保留给未来方案评估，当前文件同步不使用它。
- `static func defaultStoreURL() throws -> URL`：生成当前 App 容器中的 `Application Support/YoloLedger/ledger.store` 路径。
- `storeURL: URL`：记录实际打开的文件地址。

仓库提供 `fetchBooks()`、`fetchCategories()`、`fetchEntries(bookID:)`、`createEntry(_:id:)`、`updateEntry(id:draft:)`、`deleteEntry(id:)`、`createBook(name:id:)` 和 `renameBook(id:name:)`。无参账目查询及自动分配 ID 的便捷入口沿用 Core 的协议扩展。

M1 的 `EmptyLedgerBookRepository` 继续保留，用于旧骨架和只需要 `LedgerBookRepository` 的空状态场景；实际 M2 App 使用上述磁盘仓库。

## 保存与一致性

- SwiftData 的 `ModelContext` 隔离在内部串行 `ModelActor` 中，跨模块只传递 Core 的 Sendable 值类型。
- 显式配置磁盘 URL；正常 App、单元测试和 UI 测试都使用本地模式，文件夹同步由独立的 `LedgerFolderSyncing` 调用完成。没有内存回退或删除旧库重建的错误恢复路径，目录、数据库初始化、读取和保存错误向调用方传播。
- 关闭隐式 autosave，初始化种子和每个写操作显式 `save()`；发生错误时 `rollback()`，防止失败修改混入后续合法保存。
- 使用 Core 的稳定种子账本／分类和已保存的初始化标记；重新打开仓库不会重复插入或重置已改名的种子账本。系统支出分类名称与顺序采用 Core 按用户截图提供的种子，原日用及收入分类继续保留。
- 金额以 `Int64` 分保存，不转为 Double；保存原始 `Date`，本地时区的展示和日期范围计算由 Core / UI 负责。
- 新增和更新前验证账本、分类、收支匹配和日期。重复及不存在的 ID 返回对应 `LedgerError`。更新账目保留 ID、`source` 和 `createdAt`，只修改可编辑字段与 `updatedAt`。
- 同一 App 的窗口和页面复用一个仓库实例。已验证同一实例内并发提交相同 ID 只有一次成功；多进程或多个活跃仓库同时写同一路径的场景尚未验收。
- CloudKit 模式移除持久层唯一约束，由仓库按业务 UUID 去重。相同 UUID 以较新的修改／删除时间优先，时间相同时用稳定字段排序；账目删除写入 `deletedAt`，避免另一设备把已删除记录重新上传回来。
- 旧 `CloudSyncMonitor` 兼容代码仍可表达未来 CloudKit 配置；当前本地模式下同一变更流由文件夹同步成功后主动触发，UI 据此重新读取。

## 用户选定文件夹同步

`SwiftDataLedgerRepository` 同时实现 Core 的 `LedgerFolderSyncing`。平台层负责让用户选择普通文件夹或 iCloud Drive 文件夹、保存 security-scoped bookmark 并在调用期间取得访问权限；Storage 只接收已授权的 URL：

```swift
let report = try await repository.synchronize(
    folderURL: authorizedFolderURL,
    deviceID: installationDeviceID
)
```

- SwiftData 本地库始终是运行时真源。同步目录只保存交换快照，不包含 `ledger.store`、SQLite、WAL 或 SHM。
- 交换位置为 `有落同步数据/devices/<device UUID>.json`。每个安装只覆盖自己的快照，不删除其他设备文件；缺少某台设备的文件不表示删除数据。
- JSON 协议当前为 `formatVersion: 1`、`schemaVersion: 1.1.0`，使用排序键、缩进和带 9 位小数秒的 UTC ISO 8601 日期。快照包含账本、分类、账目的全部持久化字段及软删除时间。
- 每轮先通过 `NSFileCoordinator` 读取并完整解码所有设备快照，检查文件名／deviceID、版本、重复 UUID、枚举值、时间、账目引用和收支类型。任何损坏或不支持版本都会在修改本地前明确失败。
- 合并以业务 UUID 为键，比较 `max(updatedAt, deletedAt)`；时间相同先选 tombstone，再按完整稳定字段和来源 deviceID 确定结果。tombstone 会继续导出，避免缺文件或旧快照让删除数据复活。
- 本地变化在串行 `ModelActor` 中一次保存，失败统一 rollback。成功后把合并后的完整数据写到同目录临时文件，再原子替换本设备 JSON，并通过 `updates()` 通知界面重新读取。
- `LedgerFolderSyncReport.importedRecordCount` 是本轮因文件快照而改变的本地记录数；`exportedRecordCount` 是写入本设备完整快照的账本、分类和账目记录总数，包含 tombstone。

文件夹同步不会自动监听目录变化或常驻后台轮询；调用时机、错误展示、bookmark 生命周期和 iCloud Drive 文件下载状态由 Mac / iPhone 平台层负责。

## 数据版本

内部 `LedgerSchemaV1` 当前声明版本 `1.1.0`，包含账本、分类、账目和初始化标记，并为 CloudKit 属性提供默认值或可选值。`LedgerMigrationPlan` 已登记当前 schema，现阶段只有测试数据，未保留正式版 1.0 的跨版本迁移阶段。

每次成功打开账库后，会在数据库旁记录当前 schema 版本。已有数据库首次由新 schema 打开前，存储层先把 SQLite 主文件、WAL 和 SHM 一起复制到同目录 `UpgradeSnapshots/before-<目标版本>/`；同一目标版本的快照只创建一次，失败或重试不会覆盖最初快照。快照完成前不启动 SwiftData 迁移，迁移失败不清库。今后新增 schema 时必须同时更新当前版本、保留旧 `VersionedSchema`、补迁移阶段和旧版本数据测试。

本轮验证的是当前 schema 新建、重开、升级前快照、分类种子升级、软删除以及重复 UUID 冲突收敛；尚未验证正式发布版本之间的真实迁移。上线后 schema 只能向前兼容演进，并需要保留旧 schema 与迁移测试。

## 本地数据保护

iPhone target 声明系统默认数据保护级别 `NSFileProtectionComplete`。存储层还会显式把已有的账库目录、SQLite 主文件、WAL、SHM、schema 标记及升级快照提升到 Complete，避免旧安装继续沿用较弱的默认级别。该级别由 iOS 使用设备密钥自动完成磁盘加密，锁屏时文件不可读写；当前 App 没有锁屏后台写账能力。模拟器只能验证代码路径和 entitlement 生成，真实锁屏保护仍需在物理 iPhone 上做发布前安全验收。

macOS 没有同一套 iOS 文件保护类；Mac 侧继续依赖 App Sandbox、系统账户权限与用户开启的 FileVault。上述升级快照逻辑同时用于 Mac 和 iPhone。

## 分类种子数据升级

`LedgerSeedBootstrap` 在打开仓库时处理种子版本，数据库 schema 仍为 V1：

- `starter-choices-v1` 保留原有账本／分类初始化含义。
- 独立的 `starter-categories-v2` 标记记录新增分类及系统顺序升级；已有旧标记不会跳过此升级。
- 旧库按 UUID 补齐 Core 中的新分类，按 Core 当前种子顺序排列系统分类；新安装与升级后的默认分类一致。
- 原 `…000000000105` 分类仅在名称仍为“其他支出”时改为“其它”，保留相同 UUID 和历史引用。已改名的系统分类、原日用／收入分类、自定义分类与账本均保留；自定义分类的排序值不变。
- 分类变化与版本标记一次保存，失败统一回滚并向上抛错；下次可写打开时重试。已有两个标记时没有待保存变化，不重复保存或重新应用系统顺序，后续用户修改不会被重置。

今后种子内容需要覆盖既有安装时，应增加独立升级标记与对应验证，不能只改 Core 的默认数组。

## 构建

工具版本声明为 Swift 6.0，采用 Swift 6 语言模式。M1 临时构建基线为 macOS 14 / iOS 17；正式最低支持版本仍待确认，当前 iOS App 仅面向 iPhone。

从仓库根目录运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/storage-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/storage-swift
```

2026-10-31 使用 Xcode 27.1 完成 macOS arm64 构建和 **30 项测试**。测试使用各自独立的真实临时磁盘文件，覆盖种子幂等、账目新增／更新／软删除后重开保留、精确大额金额、账本筛选与改名、并发重复 ID、CloudKit 型重复 UUID 收敛、无效输入、失败回滚、升级前快照只创建一次，以及文件系统错误和损坏数据库不被清空。

其中 5 项分类升级测试先直接写入冻结的旧 8 分类、旧初始化标记、旧账目和改名账本，真实落盘后再打开仓库升级；覆盖新旧安装一致、自定义数据保留、重开无重复、只读保存失败回滚与重试，以及已升级库无需再保存。

其中 7 项文件夹同步测试使用真实临时交换目录和两个独立 SwiftData store / deviceID，覆盖 A 新增后 B 导入、B 修改和删除后 A 收敛、双方离线新增、相同时间确定性与 tombstone 优先、同一秒内小数时间顺序、损坏与不支持版本不改本地、原子替换无临时残留、重开保留及成功后的更新通知。

损坏库与只读升级失败测试会触发预期的 Core Data 错误日志；测试同时断言错误可捕获且原数据保留。本次分类升级的 iOS 构建与双端 App 体验仍由 Apple / main 集成验收。

## 后续职责与边界

本轮实现本地账本与账目操作、一次性种子初始化、用户选定文件夹的完整快照交换、同步事件通知和冲突收敛。完整备份恢复、分类管理、批量操作恢复和定时规则仍属于后续任务；真实 iCloud Drive 双设备下载／上传时机、bookmark 权限恢复、网络中断及物理 iPhone 后台行为仍待验收。旧 CloudKit 代码只作为未来可选实现保留，不是当前 App 配置。
