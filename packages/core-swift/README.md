# 核心业务模块

Swift Package、library product 和模块名均为 `YoloLedgerCore`，目录为 `core-swift`。

本模块承载双端共享的领域模型、业务规则和接口，不依赖 SwiftUI、SwiftData 或其他本仓库 Package。

## 兼容的 M1 契约

- `LedgerBook: Identifiable, Equatable, Sendable`：包含只读 `id: UUID` 和 `name: String`，通过 `public init(id:name:)` 创建。标识由调用方提供。
- `LedgerBookRepository: Sendable`：通过 `func fetchBooks() async throws -> [LedgerBook]` 异步读取账本。具体存储实现由 Storage 提供，并由 App 注入共享界面。

上述类型和方法保持兼容。M2 通过下列模型和协议扩展功能，数据库实现继续位于 Storage。

## M2 公开契约

### 精确金额与记录

- `LedgerAmount` 保存人民币 `Int64` 分，金额严格大于零。`init(input:) throws` 接受 ASCII 数字和可选的一至两位小数，允许首尾空白；拒绝符号、千位分隔、指数、超过两位小数等输入，不猜测、不舍入、不经 `Double` 转换。
- `init(minorUnits:) throws` 供存储映射使用；`decimalString` 输出两位小数；`LedgerAmount.format(minorUnits:)` 可精确格式化汇总中的零和负数。
- 可保存的最大金额为 `92233720368547758.07` 元，超过范围抛出 `LedgerError.amountOverflow`。
- 自定义金额键盘使用 `LedgerAmountExpression.evaluate(_:) throws -> LedgerAmount`：十进制操作数以 `+` / `-` 连接，按从左到右的顺序逐步计算；例 `12.50+3-1.25` 得到 `14.25`。
- 表达式操作数可为零，每项最多两位小数且原始数字最多含一个小数点；纯整数后的尾点按整数额完成，例如 `12.` 等于 `12.00`，`12.+3.` 等于 `15.00`，而 `1.2.`、`1+0.0.` 必须报错。允许中间负数，最终结果必须大于零。
- 表达式仅忽略整体首尾空白；不接受内部空白、一元正负号、悬空／连续运算符、括号、其他运算符或非法字符。语法错误抛出 `invalidAmountExpression`，操作数或逐步运算溢出抛出 `amountOverflow`，最终零／负数抛出 `nonPositiveAmount`，均有中文错误提示。
- 表达式以 `Int64` 分执行 checked 加减，不使用浮点或动态求值，也不会为使最终结果可表示而忽略中途溢出。`LedgerAmount(input:)` 保持原有严格规则，仍不接受 `12.` 或表达式。
- `LedgerEntryKind`：`.expense`、`.income`；`LedgerEntrySource` 当前仅有 `.manual`。
- `LedgerCategory`：`id: UUID`、`name: String`、`kind: LedgerEntryKind`。
- `LedgerEntryDraft`：`bookID`、`categoryID`、`kind`、`amount`、`date`、`note`、`source`；`note` 默认空字符串，`source` 默认 `.manual`。
- `LedgerEntry`：上述草稿内容加稳定 `id: UUID`、`createdAt` 和 `updatedAt`。通过 `init(id:draft:createdAt:updatedAt:)` 创建，`draft` 可取回可编辑内容。

金额、账本、分类、草稿和记录都是可跨并发边界传递的 `Sendable` 值对象。日期用 `Date` 保存绝对时刻，显示及时间范围按设备当前本地日历计算。

### 异步仓库

`LedgerRepository` 继承 `LedgerBookRepository`（及其 `Sendable` 要求），新增方法均为 `async throws`：

```swift
func fetchCategories() async throws -> [LedgerCategory]
func fetchEntries(bookID: UUID?) async throws -> [LedgerEntry]
func createEntry(_ draft: LedgerEntryDraft, id: UUID) async throws -> LedgerEntry
func updateEntry(id: UUID, draft: LedgerEntryDraft) async throws -> LedgerEntry
func deleteEntry(id: UUID) async throws
func createBook(name: String, id: UUID) async throws -> LedgerBook
func renameBook(id: UUID, name: String) async throws -> LedgerBook
```

- `fetchEntries(bookID: nil)` 读取全部记录，传入账本 ID 则只读取该账本；无参 `fetchEntries()` 是读取全部记录的便捷重载。结果按记账日期降序、创建时间降序、UUID 字符串升序排列。
- `createEntry(_:)`、`createBook(name:)` 便捷重载会生成 UUID。需要重试时可由调用方预先生成并保留 ID，调用带 `id:` 的方法；重复创建相同实体 ID 应抛出 `duplicateIdentifier`，不悄然覆盖。
- Storage 实现新增／修改前调用 `LedgerValidation.validate(_:books:categories:)`，验证账本存在、分类存在、分类收支方向一致及日期有效。金额的正数和精度约束已经由 `LedgerAmount` 构造器保证。
- 新建／重命名账本先调用 `LedgerValidation.normalizedName(_:)`，去除首尾空白并拒绝空名称。`LedgerBook` 的原有非抛错初始化器保留兼容性，校验发生在写入边界。
- 新增记录的两个时间戳由仓库生成；修改保留 ID、创建时间和原始来源，只更新内容与修改时间。删除不存在的记录应抛出 `entryNotFound`。
- `LedgerError` 提供具体错误及中文 `LocalizedError` 提示。数据库读写错误由 Storage 继续抛出，成功与失败由调用方反馈。

### 日期范围与最小汇总

- `LedgerPeriod`：`.day`、`.week`、`.month`、`.year`。
- `LedgerDateRanges.range(for:containing:calendar:) throws` 默认在调用时使用 `Date()` 与 `Calendar.current`，跟随当前系统时区、日历和每周首日；允许注入日历进行确定性计算和测试。
- `LedgerDateRange` 含 `start`、`end` 和 `contains(_:)`，区间为 `[start, end)`，下一周期起点不会在两边重复统计。范围由 Calendar 计算，支持夏令时，不把一天硬编码为 86400 秒。
- `LedgerSummary(entries:dateRange:) throws` 对传入记录计算 `incomeMinorUnits`、`expenseMinorUnits`、`balanceMinorUnits` 和 `entryCount`。选中账本时传入该账本的记录；可用 `dateRange` 筛选时间，省略则汇总全部。
- 空汇总为 `.zero`；结余允许为负数。收入或支出总额超出 `Int64` 时抛出 `summaryOverflow`，不会回绕或丢失精度。

### 初始数据与范围

`LedgerSeedData.books` 包含“日常账本”，`defaultBook` 提供其稳定 ID；`categories` 按用户于 2026-10-28 提供的喵喵记账截图补齐支出分类，顺序为：**餐饮、交通、购物、宠物、住房、零食、旅行、通讯、医疗、Pos、其它、礼金、运动**。原有“日用”额外保留在支出末尾，收入仍为工资、奖金、其他收入。截图中的“设置”是分类管理入口，不加入分类种子，也不扩展本轮分类 CRUD。

种子 UUID 使用前缀 `A20E127A-36F6-401A-A6E3-` 和下表的 12 位后缀，供 Storage 幂等初始化／升级和 UI 共用：

| 分类 | 后缀 | 兼容约定 |
| --- | --- | --- |
| 餐饮、交通、购物、日用 | `000000000101`–`000000000104` | 保持原 ID，“日用”仅调整顺序 |
| 其它 | `000000000105` | 原“其他支出”的同 ID 显示名更新 |
| 宠物、住房、零食、旅行、通讯、医疗、Pos、礼金、运动 | `000000000106`–`000000000114` | 按列出顺序分配新 ID |
| 工资、奖金、其他收入 | `000000000201`–`000000000203` | 名称、顺序、收入方向及 ID 均保持原样 |

本次核实范围仅为截图中支出分类的名称与顺序；收入仍沿用 M2 初始选项，其他交互继续以实际参考材料为准。Core 只定义契约和规则；已有数据库的种子补齐、同 ID 名称更新及历史引用保留由 Storage 实现并验证。持久化、CRUD 的原子写入、重复 ID 拦截、时间戳维护和双端页面接入由对应模块实现。M2 不包含删除账本、分类管理、多币种、定时规则或 iCloud。

## 构建

在仓库根目录执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/core-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/core-swift
```

Manifest 使用 `swift-tools-version: 6.0`，Swift 语言模式为 6。临时构建基线为 macOS 14 / iOS 17；产品最低支持系统版本仍待 main 确认。

验证记录（2026-10-28）：使用指定 Xcode 的 Swift 6.4 / arm64 环境运行上述测试命令，构建通过，**42 项测试全部通过**。分类种子新增 4 项验证截图顺序、旧分类 ID 兼容、106–114 新 ID 映射及收入名称／顺序／ID 保持；金额表达式 12 项覆盖精确加减、左到右计算、末尾小数点、多余尾点回归、零操作数、中间负数、最终正数限制、非法语法、操作数和中间运算溢出，以及 `Int64.min` 中间结果恢复；其余 26 项覆盖原有严格金额解析、汇总、本地日期范围、DST 和关联校验。已有数据库的分类升级由 Storage 验证，分类页面及自定义键盘的双端 UI 验收由 Apple／main 完成。

## 后续业务约定

手机端采用手机当前系统本地时区计算日期范围和定时规则；独立运行的 Mac 按同样原则使用本机系统时区。定时规则的具体行为以喵喵记账实际操作结果为准，跨设备去重留待后续 iCloud 阶段。
