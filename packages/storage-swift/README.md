# 本地存储模块

Swift Package、library product 和模块名均为 `YoloLedgerStorage`，依赖本地 [core-swift](../core-swift/README.md) 中的 `YoloLedgerCore`。

## M2 本地仓库

`SwiftDataLedgerRepository` 实现 Core 的 `LedgerRepository`，可由 Mac / iPhone App 创建一次并注入共享界面：

```swift
import YoloLedgerCore
import YoloLedgerStorage

let storeURL = try SwiftDataLedgerRepository.defaultStoreURL()
let repository: any LedgerRepository = try SwiftDataLedgerRepository(storeURL: storeURL)
let books = try await repository.fetchBooks()
```

公开初始化接口：

- `init(storeURL: URL) throws`：打开指定的真实磁盘数据库，测试可传入独立临时路径。
- `static func defaultStoreURL() throws -> URL`：生成当前 App 容器中的 `Application Support/YoloLedger/ledger.store` 路径。
- `storeURL: URL`：记录实际打开的文件地址。

仓库提供 `fetchBooks()`、`fetchCategories()`、`fetchEntries(bookID:)`、`createEntry(_:id:)`、`updateEntry(id:draft:)`、`deleteEntry(id:)`、`createBook(name:id:)` 和 `renameBook(id:name:)`。无参账目查询及自动分配 ID 的便捷入口沿用 Core 的协议扩展。

M1 的 `EmptyLedgerBookRepository` 继续保留，用于旧骨架和只需要 `LedgerBookRepository` 的空状态场景；实际 M2 App 使用上述磁盘仓库。

## 保存与一致性

- SwiftData 的 `ModelContext` 隔离在内部串行 `ModelActor` 中，跨模块只传递 Core 的 Sendable 值类型。
- 显式配置磁盘 URL 和 `cloudKitDatabase: .none`；没有内存回退或删除旧库重建的错误恢复路径。目录、数据库初始化、读取和保存错误向调用方传播。
- 关闭隐式 autosave，初始化种子和每个写操作显式 `save()`；发生错误时 `rollback()`，防止失败修改混入后续合法保存。
- 使用 Core 的稳定种子账本／分类和已保存的初始化标记；重新打开仓库不会重复插入或重置已改名的种子账本。系统支出分类名称与顺序采用 Core 按用户截图提供的种子，原日用及收入分类继续保留。
- 金额以 `Int64` 分保存，不转为 Double；保存原始 `Date`，本地时区的展示和日期范围计算由 Core / UI 负责。
- 新增和更新前验证账本、分类、收支匹配和日期。重复及不存在的 ID 返回对应 `LedgerError`。更新账目保留 ID、`source` 和 `createdAt`，只修改可编辑字段与 `updatedAt`。
- 同一 App 的窗口和页面复用一个仓库实例。已验证同一实例内并发提交相同 ID 只有一次成功；多进程或多个活跃仓库同时写同一路径的场景尚未验收。

## 数据版本

内部 `LedgerSchemaV1` 声明版本 `1.0.0`，包含账本、分类、账目和初始化标记。`LedgerMigrationPlan` 已登记 V1，当前没有跨版本迁移阶段。

本轮验证的是 V1 新建、重开及同一 schema 下的分类种子数据升级，尚未验证未来 schema 版本迁移。当前唯一约束和引用设计服务于本地版，后续如接入 iCloud，需另行评估兼容性和迁移方案。

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

2026-10-28 使用 Xcode 27.1 完成 macOS arm64 构建和 **20 项测试**。测试使用各自独立的真实临时磁盘文件，覆盖种子幂等、账目新增／更新／删除后重开保留、精确大额金额、账本筛选与改名、并发重复 ID、无效输入、失败回滚，以及文件系统错误和损坏数据库不被清空。

其中 5 项分类升级测试先直接写入冻结的旧 8 分类、旧初始化标记、旧账目和改名账本，真实落盘后再打开仓库升级；覆盖新旧安装一致、自定义数据保留、重开无重复、只读保存失败回滚与重试，以及已升级库无需再保存。

损坏库与只读升级失败测试会触发预期的 Core Data 错误日志；测试同时断言错误可捕获且原数据保留。本次分类升级的 iOS 构建与双端 App 体验仍由 Apple / main 集成验收。

## 后续职责与边界

本轮实现本地账本与账目操作、一次性种子初始化和 V1 数据版本基础。完整备份恢复、分类管理、批量操作恢复、定时规则、截图识别及云同步均属于后续任务。
