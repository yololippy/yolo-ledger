# 核心业务模块

Swift Package、library product 和模块名均为 `YoloLedgerCore`，目录为 `core-swift`。

本模块承载双端共享的领域模型、业务规则和接口，不依赖 SwiftUI、SwiftData 或其他本仓库 Package。

## M1 公开契约

- `LedgerBook: Identifiable, Equatable, Sendable`：包含只读 `id: UUID` 和 `name: String`，通过 `public init(id:name:)` 创建。标识由调用方提供。
- `LedgerBookRepository: Sendable`：通过 `func fetchBooks() async throws -> [LedgerBook]` 异步读取账本。具体存储实现由 Storage 提供，并由 App 注入共享界面。

M1 仅提供上述数据与读取接口，供页面骨架及空列表适配器联调。完整账目模型、金额和日期计算、统计、CRUD、定时规则与持久化设计随后续里程碑实现。

## 构建

在仓库根目录执行：

```sh
swift build --package-path packages/core-swift
```

Manifest 使用 `swift-tools-version: 6.0`，Swift 语言模式为 6。临时构建基线为 macOS 14 / iOS 17；产品最低支持系统版本仍待 main 确认。

验证记录（2026-10-28）：本机 Swift 6.4 / arm64 环境运行上述命令构建通过。Manifest 链接时提示 `/Library/Developer/CommandLineTools/Developer/Library/Frameworks` 搜索路径不存在，未阻断本次构建。iOS 构建与双端 App 集成尚未在本模块验收。

## 后续业务约定

手机端采用手机当前系统本地时区计算日期范围和定时规则；独立运行的 Mac 按同样原则使用本机系统时区。定时规则的具体行为以喵喵记账实际操作结果为准，跨设备去重留待后续 iCloud 阶段。
