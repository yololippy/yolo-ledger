# 本地存储模块

Swift Package、library product 和模块名均为 `YoloLedgerStorage`，依赖本地 [core-swift](../core-swift/README.md) 中的 `YoloLedgerCore`。

## M2 本地仓库

`SwiftDataLedgerRepository` 实现 Core 的 `LedgerRepository` 和 `LedgerScheduledEntryRepository`。当前由 iPhone App 创建一次并注入共享界面；存储 Package 继续保持 macOS 构建兼容，但本阶段不新增 Mac 产品功能：

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

- `init(storeURL:syncMode:) throws`：打开指定的真实磁盘数据库；默认 `.local`，文件夹同步不依赖 CloudKit 或 iCloud entitlement。若未来重新评估 CloudKit，由组装层显式传入容器标识，不在存储层重复保存产品标识。
- `static func defaultStoreURL() throws -> URL`：生成当前 App 容器中的 `Application Support/YoloLedger/ledger.store` 路径。
- `storeURL: URL`：记录实际打开的文件地址。
- `importMeowLedger(plans:)`：事务化导入一个或多个 Core 已解析的 `LedgerMeowImportPlan`，返回备份目录和批次核对报告。
- `makeMeowImportHandler()`：生成 `LedgerMeowImportHandler` concrete 闭包，供 App 组装层适配成 UI 定义的注入接口；UI Package 无需依赖 Storage。

仓库提供 `fetchBooks()`、`fetchCategories()`、`fetchEntries(bookID:)`、`createEntry(_:id:)`、`updateEntry(id:draft:)`、`deleteEntry(id:)`、`createBook(name:id:)` 和 `renameBook(id:name:)`，并实现定时规则版本保存、暂停／恢复／删除、到期处理和下次触发时间查询。无参账目查询及自动分配 ID 的便捷入口沿用 Core 的协议扩展。

M1 的 `EmptyLedgerBookRepository` 继续保留，用于旧骨架和只需要 `LedgerBookRepository` 的空状态场景；实际 M2 App 使用上述磁盘仓库。

## 保存与一致性

- SwiftData 的 `ModelContext` 隔离在内部串行 `ModelActor` 中，跨模块只传递 Core 的 Sendable 值类型。
- 月份界面使用数据库侧的账本 ID 与日期范围谓词，只解码当前月及左右动画相邻月；启动不再读取、校验全部历史账目。全量读取接口继续用于同步、导入和维护场景，并保留 UUID 冲突自愈。
- 打开账库时只整理数量很小的账本、分类和迁移标记，不扫描整张账目表；分类备注在进入记账页后按当前分类单独读取。
- 显式配置磁盘 URL；正常 App、单元测试和 UI 测试都使用本地模式，文件夹同步由独立的 `LedgerFolderSyncing` 调用完成。没有内存回退或删除旧库重建的错误恢复路径，目录、数据库初始化、读取和保存错误向调用方传播。
- 关闭隐式 autosave，初始化种子和每个写操作显式 `save()`；发生错误时 `rollback()`，防止失败修改混入后续合法保存。
- 使用 Core 的稳定种子账本／分类和已保存的初始化标记；重新打开仓库不会重复插入或重置已改名的种子账本。系统支出分类名称与顺序采用 Core 按用户截图提供的种子，原日用及收入分类继续保留。
- 金额以 `Int64` 分保存，不转为 Double；保存原始 `Date`，本地时区的展示和日期范围计算由 Core / UI 负责。
- 喵喵记账导入行另外保存格式、稳定去重键及原始分类、时间、金额、账户、账本、货币和备注。普通有落记账记录的这些字段保持 nil，不改变既有数据含义。
- 新增和更新前验证账本、分类、收支匹配和日期。重复及不存在的 ID 返回对应 `LedgerError`。更新账目保留 ID、`source` 和 `createdAt`，只修改可编辑字段与 `updatedAt`。
- 同一 App 的窗口和页面复用一个仓库实例。已验证同一实例内并发提交相同 ID 只有一次成功；多进程或多个活跃仓库同时写同一路径的场景尚未验收。
- CloudKit 模式移除持久层唯一约束，由仓库按业务 UUID 去重。相同 UUID 以较新的修改／删除时间优先，时间相同时用稳定字段排序；账目删除写入 `deletedAt`，避免另一设备把已删除记录重新上传回来。
- 旧 `CloudSyncMonitor` 兼容代码仍可表达未来 CloudKit 配置；当前本地模式下同一变更流由文件夹同步成功后主动触发，UI 据此重新读取。

## 每月定时记账

Storage 按 Core 的 `LedgerScheduledEntryRepository` 保存每月固定日／月末规则，并在 App 调用时处理已经到期的月份：

- 同一规则使用稳定 `ruleID`。相同 `effectiveStartMonth` 的编辑、暂停和恢复会原位覆盖该月唯一版本，跨月修改才新增版本；历史月份按当月生效版本生成，修改规则不会改写已经生成的账目或 occurrence。
- 暂停与恢复同样写入新版本，因此可以表示一段停用月份。删除规则会软删除其全部版本，但不会删除已经生成的账目或 occurrence 记录。
- 每个规则每月的 occurrence 使用稳定键。账目与 occurrence 在同一个 `ModelContext.save()` 中提交；处理在内部 actor 串行执行，重复调用、并发调用和重启后都不会重复生成。
- 用户删除自动生成的账目后，独立 occurrence 记录继续保留，因此该月不会再次生成。自动账目自身保存规则 ID、年月和 occurrence 键，来源固定为 `scheduled`。
- 触发日期由 Core planner 使用调用方传入的手机当前系统日历及时区计算；固定 29／30／31 日会收敛到该月最后一天。
- 当前规则版本和 occurrence 仅保存在本机 SwiftData 中，不参与文件夹同步；文件夹快照只随普通账目同步自动账目的来源与 occurrence 元数据。规则跨设备同步留待后续单独设计，不能据此认为两台设备会共享或共同执行同一规则。

## 喵喵记账 CSV 导入

Core 负责只读解析 CSV 和生成预览／问题列表，Storage 只接收解析后的计划：

```swift
let importHandler = repository.makeMeowImportHandler()
let report = try await importHandler(plans)
```

- 至少接收一个计划；任一计划仍有 issue、预览与记录不一致、原始字段与去重键不一致时，整批在备份和数据库写入前拒绝。
- 按标准化后的原始账本名复用或创建账本；分类使用“收支方向 + 原始分类名”复用或创建。未知账本和未知分类会单独创建，不归入默认“其它”。原始未标准化字符串始终完整保存在账目导入元数据中。
- Core 的去重键包含七个原始字段和同内容行的一基出现序号：同一文件中的合法相同账单会分别保留；重复文件和跨文件重叠行会跳过。账本、分类和账目使用稳定 UUID，两个设备独立导入同一行后也能通过文件夹同步收敛。
- 不删除、改名或覆盖已有有落记账记录。导入账目来源为 `meowLedgerImport`；普通编辑继续保留原始来源、去重键和全部原始字段。
- 所有计划先完成映射和碰撞检查，再在一次 ModelContext save 中插入新账本、分类和账目；任何错误统一 rollback。备份失败时数据库尚未开始修改。
- 成功报告包含批次 ID、备份 URL、提交／新增／跳过数量、创建的账本／分类数量、导入收支笔数及以分为单位的 Decimal 精确合计。

每次实际导入前会在账库旁创建 `ImportSnapshots/<batch UUID>/`，复制 SQLite 主文件、WAL、SHM、schema 标记并写入不含账单内容的 `manifest.json`。恢复时应先完全退出 Mac 与 iPhone App，保留当前 store family，再把报告目录中的 store family 和 schema 标记复制回原账库目录；不能在活跃 `ModelContainer` 上直接替换。当前只提供安全快照与恢复材料，自动恢复界面仍由后续 App 工作实现。

## 用户选定文件夹同步

`SwiftDataLedgerRepository` 同时实现 Core 的 `LedgerFolderSyncing`。平台层负责让用户选择普通文件夹或 iCloud Drive 文件夹、保存 security-scoped bookmark 并在调用期间取得访问权限；Storage 只接收已授权的 URL：

```swift
let report = try await repository.synchronize(
    folderURL: authorizedFolderURL,
    deviceID: installationDeviceID
)
```

- SwiftData 本地库始终是运行时真源。同步目录只保存交换快照，不包含 `ledger.store`、SQLite、WAL 或 SHM。
- 交换位置为 `有落记账同步数据/devices/<device UUID>.json`。每个安装只覆盖自己的快照，不删除其他设备文件；缺少某台设备的文件不表示删除数据。
- JSON 协议当前写出 `formatVersion: 3`、`schemaVersion: 3.0.0`，使用排序键、缩进和带 9 位小数秒的 UTC ISO 8601 日期。快照包含账本、分类、账目的全部持久化字段、导入元数据、自动账目 occurrence 元数据及软删除时间；读取继续兼容 format 1／2 与 schema 1.1.0／2.0.0 快照。定时规则版本和独立 occurrence 处理记录不写入交换文件。
- 每轮先通过 `NSFileCoordinator` 读取并完整解码所有设备快照，检查文件名／deviceID、版本、重复 UUID、枚举值、时间、账目引用和收支类型。任何损坏或不支持版本都会在修改本地前明确失败。
- 合并以业务 UUID 为键，比较 `max(updatedAt, deletedAt)`；时间相同先选 tombstone，再按完整稳定字段和来源 deviceID 确定结果。tombstone 会继续导出，避免缺文件或旧快照让删除数据复活。
- 本地变化在串行 `ModelActor` 中一次保存，失败统一 rollback。成功后把合并后的完整数据写到同目录临时文件，再原子替换本设备 JSON，并通过 `updates()` 通知界面重新读取。
- `LedgerFolderSyncReport.importedRecordCount` 是本轮因文件快照而改变的本地记录数；`exportedRecordCount` 是写入本设备完整快照的账本、分类和账目记录总数，包含 tombstone。

文件夹同步不会自动监听目录变化或常驻后台轮询；调用时机、错误展示、bookmark 生命周期和 iCloud Drive 文件下载状态由 Mac / iPhone 平台层负责。

## 数据版本

内部保留 `LedgerSchemaV1` 1.1.0 和 `LedgerSchemaV2` 2.0.0 的完整旧模型；当前 `LedgerSchemaV3` 为 3.0.0，在账目上增加可选的定时 occurrence 元数据，并新增规则版本与独立 occurrence 记录。`LedgerMigrationPlan` 登记 V1 → V2 → V3 两段轻量迁移；真实 V1／V2 SQLite 测试确认既有账本、分类、账目、金额、备注、时间和导入元数据不丢失，新定时字段迁移后为 nil。

每次成功打开账库后，会在数据库旁记录当前 schema 版本。已有数据库首次由新 schema 打开前，存储层先把 SQLite 主文件、WAL 和 SHM 一起复制到同目录 `UpgradeSnapshots/before-<目标版本>/`；同一目标版本的快照只创建一次，失败或重试不会覆盖最初快照。快照完成前不启动 SwiftData 迁移，迁移失败不清库。今后新增 schema 时必须同时更新当前版本、保留旧 `VersionedSchema`、补迁移阶段和旧版本数据测试。

打开 1.1.0 或 2.0.0 账库并升级到当前版本前，会先生成不可覆盖的 `UpgradeSnapshots/before-3.0.0/` store family，再执行 staged migration。上线后 schema 继续只能向前兼容演进，并保留旧 schema 与迁移测试。

## 本地数据保护

iPhone target 声明系统默认数据保护级别 `NSFileProtectionComplete`。存储层还会显式把已有的账库目录、SQLite 主文件、WAL、SHM、schema 标记及升级快照提升到 Complete，避免旧安装继续沿用较弱的默认级别。该级别由 iOS 使用设备密钥自动完成磁盘加密，锁屏时文件不可读写；当前 App 没有锁屏后台写账能力。模拟器只能验证代码路径和 entitlement 生成，真实锁屏保护仍需在物理 iPhone 上做发布前安全验收。

macOS 没有同一套 iOS 文件保护类；Mac 侧继续依赖 App Sandbox、系统账户权限与用户开启的 FileVault。上述升级快照逻辑同时用于 Mac 和 iPhone。

## 分类种子数据升级

`LedgerSeedBootstrap` 在打开仓库时处理种子内容版本，当前数据库 schema 为 V3；两者独立：

- `starter-choices-v1` 保留原有账本／分类初始化含义。
- 独立的 `starter-categories-v2` 标记记录新增分类及系统顺序升级；已有旧标记不会跳过此升级。
- `starter-default-book-v3` 将未改名的旧内置“日常账本”升级为“默认账本”；若导入已创建同名账本，会先把其账目迁移到稳定种子 ID，再软删除重复账本。用户自行改名的种子账本不会被覆盖。
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

2026-11-01 使用 Xcode 27.1 完成 macOS arm64 Package 构建和 **47 项测试**。测试使用各自独立的真实临时磁盘文件，覆盖种子幂等、旧“日常账本”与已导入“默认账本”的无损合并、账目新增／更新／软删除后重开保留、精确大额金额、账本筛选与改名、并发重复 ID、CloudKit 型重复 UUID 收敛、无效输入、失败回滚、升级前快照只创建一次，以及文件系统错误和损坏数据库不被清空。

其中 5 项分类升级测试先直接写入冻结的旧 8 分类、旧初始化标记、旧账目和改名账本，真实落盘后再打开仓库升级；覆盖新旧安装一致、自定义数据保留、重开无重复、只读保存失败回滚与重试，以及已升级库无需再保存。

其中 10 项文件夹同步相关测试使用真实临时交换目录和两个独立 SwiftData store / deviceID，覆盖 A 新增后 B 导入、B 修改和删除后 A 收敛、双方离线新增、相同时间确定性与 tombstone 优先、同一秒内小数时间顺序、旧 format 1 兼容、损坏与不支持版本不改本地、原子替换无临时残留、重开保留、成功后的更新通知，以及只交换自动账目元数据而不交换规则与 occurrence 处理记录。

其中 6 项喵喵导入测试覆盖真实 V1 → V2 staged migration、未知账本／分类创建、账户货币和全部原始字段保真、收支报告、导入前备份可读、多文件整批回滚、备份失败不落库、文件内合法重复、重复文件／跨文件去重、重开保留，以及两台 store 独立导入后经文件夹同步保持单条和元数据一致。

其中 7 项定时存储测试覆盖真实 V2 → V3 staged migration、规则版本持久化和重复月份拒绝、历史月份按版本生成、月末收敛、暂停／恢复、下次触发时间、删除账目后不重建、删除规则后停止、并发幂等、重启后去重和文件夹同步边界。

损坏库与只读升级失败测试会触发预期的 Core Data 错误日志；测试同时断言错误可捕获且原数据保留。本次分类升级的 iOS 构建与双端 App 体验仍由 Apple / main 集成验收。

## 后续职责与边界

本轮实现本地账本与账目操作、一次性种子初始化、喵喵记账批量导入及导入前恢复快照、用户选定文件夹的完整快照交换、同步事件通知和冲突收敛，以及本机每月定时规则的版本化存储与幂等到期处理。自动恢复 UI、一般用途完整备份恢复、分类管理、其他批量操作恢复、定时规则跨设备同步及系统后台唤醒仍属于后续任务；真实 iCloud Drive 双设备下载／上传时机、bookmark 权限恢复、网络中断及物理 iPhone 前后台调度仍待验收。旧 CloudKit 代码只作为未来可选实现保留，不是当前 App 配置。
