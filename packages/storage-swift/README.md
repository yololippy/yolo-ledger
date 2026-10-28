# 本地存储模块

Swift Package、library product 和模块名均为 `YoloLedgerStorage`，依赖本地 [core-swift](../core-swift/README.md) 中的 `YoloLedgerCore`。

## 当前 M1 接口

`EmptyLedgerBookRepository` 是供双端 App 组装和注入共享 UI 的无数据适配器，实现 Core 的 `LedgerBookRepository`：

```swift
import YoloLedgerCore
import YoloLedgerStorage

let repository: any LedgerBookRepository = EmptyLedgerBookRepository()
let books = try await repository.fetchBooks() // 返回空数组
```

公开入口为 `public init()` 和 `public func fetchBooks() async throws -> [LedgerBook]`，不暴露具体数据库类型。

## 构建

工具版本声明为 Swift 6.0，采用 Swift 6 语言模式。M1 临时构建基线为 macOS 14 / iOS 17；正式最低支持版本仍待确认，当前 iOS App 仅面向 iPhone。

从仓库根目录运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/storage-swift
```

2026-10-28 已使用 Xcode 27.1 完成上述 macOS arm64 构建。iOS 构建与双端启动仍由后续 App 工程集成验证。

## 后续职责与边界

后续在此实现本地持久化、迁移、备份恢复与存储适配，数据库模型和实现细节留在本模块内。

当前适配器始终返回空数组，尚无数据库、CRUD、持久化、迁移、备份恢复或重启保留能力。SwiftData 仍是候选方案；首版本地存储实现属于 M2，iCloud 留待后续按需评估。
