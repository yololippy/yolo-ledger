# 核心业务模块

Swift Package、library product 和模块名均为 `YoloLedgerCore`，目录为 `core-swift`。

本模块承载双端共享的领域模型、业务规则和接口，不依赖 SwiftUI、SwiftData 或其他本仓库 Package。

`YoloLedgerProduct` 集中提供运行时产品元数据，包括中英文名称、组合显示名、同步目录名、快捷指令名称和本地数据目录名。UI、Storage 与双端 App 入口直接引用这些派生值；修改产品名称时不再逐个修改运行时代码。

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
- `LedgerEntryKind`：`.expense`、`.income`；`LedgerEntrySource` 包含手动记账 `.manual`、快捷指令截图记账 `.screenshotShortcut`、喵喵记账导入 `.meowLedgerImport` 与定时记账 `.scheduled`。
- `LedgerCategory`：`id: UUID`、`name: String`、`kind: LedgerEntryKind`。
- `LedgerEntryDraft`：`bookID`、`categoryID`、`kind`、`amount`、`date`、`note`、`source`、可选 `importMetadata` 和可选 `scheduledOccurrence`；后三者默认 `.manual`／`nil`／`nil`，现有调用保持兼容。
- `LedgerEntry`：上述草稿内容加稳定 `id: UUID`、`createdAt` 和 `updatedAt`。通过 `init(id:draft:createdAt:updatedAt:)` 创建，`draft` 可取回可编辑内容、导入元数据及定时 occurrence。

金额、账本、分类、草稿和记录都是可跨并发边界传递的 `Sendable` 值对象。日期用 `Date` 保存绝对时刻，显示及时间范围按设备当前本地日历计算。

### 截图识别规则

- `LedgerRecognizedTextLine` 是平台 OCR 结果的轻量输入；Core 不依赖 Vision 或图片框架。
- `LedgerScreenshotParser` 先统一文字与标点，再分别推断收支、金额、商户、日期和分类；候选只通过显式证据评分，不以 OCR 数组中的先后顺序代替业务证据。
- 金额候选综合金额符号／小数、同一行与相邻行标签、支付成功状态、文字高度和 OCR 置信度；“实付款／实际支付”等最终总额优先，商品原价、优惠、余额、差额退款、券包广告降权，订单号和时间排除。现金实付款为零且存在储值卡扣款时，仍选择实际承担消费的卡扣款金额。
- 商户按“显式商户／收款方／店铺标签 → 已确认上下文规则 → 普通标题候选评分”依次解析；普通候选综合商户特征词、金额邻近与标题位置。商户归一化只清理显示噪声，不参与分类推断。
- 收支仅在“退款成功／到账金额／已收款”等确认语义出现时判为收入，普通订单里的“极速退款／退货包运费”保持支出。日期只接受明确日期格式或“今天 HH:mm”，只有状态栏时间、订单号或无日期时返回 `nil`。
- 分类在商户确定后独立推断：先应用极窄的已确认商户映射，再使用集中的通用关键词规则，最后回退“其它”；不会把“农场”等泛词整体映射为餐饮。
- `LedgerScreenshotProposal` 是可编码的待确认结果，只保存结构化文字和候选值，不包含原始截图；iOS App 负责接收图片与调用 Vision。
- `Tests/YoloLedgerCoreTests/Fixtures/` 保存用户明确要求加入的 8 张原始截图测试夹具；`LedgerScreenshotVisionFixtureTests` 使用与 iOS App 相同的 Vision 配置读取原图并验证完整 OCR → 解析结果。这些资源只属于测试 target，不会打包进 App。
- 商户候选排除“摇一摇／有优惠／立减金／领券／活动专区／福利中心”等明确促销文案及“查看／完成／立即购买”等纯操作按钮，避免金额附近的推广卡片覆盖真实商户。滴滴行程／支付页使用集中式多组上下文规则映射统一品牌名；新增已确认场景时扩展规则表，不在解析流程继续堆叠逐图分支。

### 喵喵记账 CSV 导入契约

`LedgerMeowCSVParser.parse(data:calendar:timeZone:)` 将 UTF-8 CSV 转换为平台无关的 `LedgerMeowImportPlan`：

- 接受文件开头的 UTF-8 BOM、CRLF／LF／CR 换行和 RFC 4180 引号规则，包括字段内逗号、双引号转义及跨行备注；不依赖文件选择器或数据库框架。
- 表头严格要求依次为“分类、时间、金额、账户、账本、货币、备注”。每条问题通过 `LedgerMeowImportIssue` 返回 CSV 记录的物理起始行、列和错误代码，不把原始账单内容写入错误文本。
- 时间严格按 `yyyy-MM-dd HH:mm:ss` 解析，并显式使用调用方注入的 `Calendar` 与 `TimeZone`；金额直接转换为精确的 `Int64` 分，负数为支出，正数为收入，非法、零值和溢出均按行拒绝。
- `LedgerMeowSourceFields` 保留 RFC 4180 解码后的七个原始字段；账户和备注允许为空，分类、时间、金额、账本和货币必须非空。Core 不据此设计账户 UI。
- `LedgerMeowImportPreview` 提供有效／无效、收支、内容重复、精确金额合计及不同账本／分类／账户／货币数量；单方向合计超出 `Int64` 时对应合计为 `nil`，记录本身仍可预览。
- `LedgerEntryImportMetadata` 保留源格式、稳定去重键和七个原始字段。相同内容的多条合法记录按其一基出现序号生成不同 SHA-256 键；同一文件重复解析会得到相同键，Storage 可据此跳过已经导入的记录而不误删合法重复账单。
- Core 只生成导入计划。Storage 负责批量写入、账本／分类映射或创建、持久化元数据、事务回滚和按去重键跳过；Apple 负责文件读取、预览、用户确认和结果展示。

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
func updates() -> AsyncStream<Void>
func currentSyncState() -> LedgerSyncState
func fetchEntries(bookID: UUID, dateRange: LedgerDateRange) async throws -> [LedgerEntry]
func fetchRecentNotes(categoryID: UUID, limit: Int) async throws -> [String]
```

- `fetchEntries(bookID: nil)` 读取全部记录，传入账本 ID 则只读取该账本；无参 `fetchEntries()` 是读取全部记录的便捷重载。结果按记账日期降序、创建时间降序、UUID 字符串升序排列。
- 首屏和月份浏览使用带 `LedgerDateRange` 的有界读取，具体存储应把账本与半开日期范围下推到数据库；默认协议实现保留内存过滤兼容性。分类备注通过独立的 `fetchRecentNotes` 按需读取，不要求启动时载入全部历史。
- `createEntry(_:)`、`createBook(name:)` 便捷重载会生成 UUID。需要重试时可由调用方预先生成并保留 ID，调用带 `id:` 的方法；重复创建相同实体 ID 应抛出 `duplicateIdentifier`，不悄然覆盖。
- Storage 实现新增／修改前调用 `LedgerValidation.validate(_:books:categories:)`，验证账本存在、分类存在、分类收支方向一致及日期有效。金额的正数和精度约束已经由 `LedgerAmount` 构造器保证。
- 新建／重命名账本先调用 `LedgerValidation.normalizedName(_:)`，去除首尾空白并拒绝空名称。`LedgerBook` 的原有非抛错初始化器保留兼容性，校验发生在写入边界。
- 新增记录的两个时间戳由仓库生成；修改保留 ID、创建时间和原始来源，只更新内容与修改时间。删除不存在的记录应抛出 `entryNotFound`。
- `LedgerError` 提供具体错误及中文 `LocalizedError` 提示。数据库读写错误由 Storage 继续抛出，成功与失败由调用方反馈。
- `LedgerSyncState` 表达纯本地、检查中、可用、同步中、暂停和错误；`updates()` 在远端变化或同步状态变化后通知 UI 重新读取。Core 只定义抽象状态，不依赖 CloudKit。

### 用户选定文件夹同步契约

免费 Personal Team 场景下，Core 通过独立的 `LedgerFolderSyncing` 固定用户选定文件夹同步的最小接口，不扩张 `LedgerRepository` 的本地 CRUD 职责：

```swift
func synchronize(
    folderURL: URL,
    deviceID: UUID
) async throws -> LedgerFolderSyncReport
```

- `folderURL` 是 Apple 平台层已经取得访问权限的用户选定目录；安全作用域 bookmark、权限恢复、文件协调和目录选择 UI 不进入 Core。
- `deviceID` 是 App 为当前安装生成并持久化的稳定 UUID，不使用硬件标识或个人信息。
- `LedgerFolderSyncReport` 返回本轮导入记录数、导出记录数和绝对完成时间；`LedgerFolderSyncState` 提供未配置、待机、同步中、成功和失败五类平台中立 UI 状态。
- 本地 SwiftData 始终是运行时真源，文件夹只是设备间交换层。Storage 负责文件格式、原子写入、读取校验，以及按业务 UUID 和 `updatedAt` / `deletedAt` 合并；Core 不依赖 SwiftData、CloudKit 或 SwiftUI。
- 目录同步与现有 `LedgerSyncState` 分开表达：前者是用户主动配置的文件交换通道，后者保留现有仓库存储／云同步状态契约。

### 每月定时记账契约

`LedgerScheduledEntryRule` 是 Storage 与 iPhone UI 共用的规则快照，包含稳定规则 ID、账本、分类、收支方向、精确金额、备注、月内日期、启用状态、生效月份及创建／更新时间：

- `LedgerMonthlyDay.fixed(1...31)` 表示每月固定日期；当月没有该日时自动落在当月最后一天。`.lastDay` 始终使用当月最后一天，包含闰年二月。
- `LedgerYearMonth` 保存 `YYYY-MM`，并参与稳定 occurrence 身份。`LedgerScheduledOccurrenceIdentity` 固定生成 `<小写 rule UUID>:<YYYY-MM>`；同一规则每月只有一个语义 occurrence。
- `LedgerScheduledEntryPlanner.dueOccurrences(for:through:excluding:calendar:timeZone:)` 返回从规则生效月份到 `now` 已到期且未处理的 occurrence，按月份升序排列。每项包含 `.scheduled` 来源、完整 `LedgerEntryDraft` 和 `LedgerScheduledOccurrenceMetadata`。
- `excluding` 必须同时传入已存在账目和已删除账目的 occurrence key。Storage 删除生成账目时保留 tombstone／处理记录，之后不会重新补建。
- 禁用规则不补记；恢复时创建从恢复月份生效的规则快照，因此暂停月份不会追补。修改时沿用原 rule ID，并让新快照从选定未来月份生效；旧 occurrence 的 key 和账目内容不改变。
- `nextExecutionDate(for:after:calendar:timeZone:)` 返回严格晚于 `now` 的下一次本地日历起始时刻，禁用时返回 `nil`。
- 所有日期运算显式接受 `Calendar` 和 `TimeZone`，Core 不写死时区。iPhone 运行时应使用稳定的公历规则并注入设备当前系统时区；时区变化后重新计算绝对执行时刻。
- Core 不负责后台定时、持久化或通知。Storage 负责规则、有效版本和 occurrence/tombstone 的原子保存；iPhone App 在启动、回到前台及系统允许的后台时机调用纯算法。当前不要求接入 Mac UI。
- `LedgerScheduledEntryRepository: Sendable` 是独立于 `LedgerRepository` 的注入边界，没有关联类型，可直接作为 existential 或由闭包适配。它提供当前规则列表、保存有效版本、暂停、显式恢复月份、删除、原子处理全部到期规则，以及所有启用规则中的下一到期时间。
- `LedgerScheduledProcessingResult` 返回本轮新建的 `[LedgerEntry]`、由其派生的生成数量，以及因 occurrence 已生成或已删除而跳过的数量。`LedgerScheduledEntryRepositoryError` 提供规则不存在和同月版本冲突两个可展示／判断的领域错误；具体数据库错误继续由 Storage 原样抛出。

### 日期范围与最小汇总

- `LedgerPeriod`：`.day`、`.week`、`.month`、`.year`。
- `LedgerDateRanges.range(for:containing:calendar:) throws` 默认在调用时使用 `Date()` 与 `Calendar.current`，跟随当前系统时区、日历和每周首日；允许注入日历进行确定性计算和测试。
- `LedgerDateRange` 含 `start`、`end` 和 `contains(_:)`，区间为 `[start, end)`，下一周期起点不会在两边重复统计。范围由 Calendar 计算，支持夏令时，不把一天硬编码为 86400 秒。
- `LedgerSummary(entries:dateRange:) throws` 对传入记录计算 `incomeMinorUnits`、`expenseMinorUnits`、`balanceMinorUnits` 和 `entryCount`。选中账本时传入该账本的记录；可用 `dateRange` 筛选时间，省略则汇总全部。
- 空汇总为 `.zero`；结余允许为负数。收入或支出总额超出 `Int64` 时抛出 `summaryOverflow`，不会回绕或丢失精度。

### 账单统计

- `LedgerStatisticsCalculator.snapshot(entries:categories:kind:dateRange:)` 对任意半开日期范围计算指定收入／支出方向的总金额、笔数、分类聚合与单笔排行。`rankedEntries` 保留完整 `LedgerEntry` 和稳定 ID，可直接作为详情下钻的数据来源。
- `LedgerCategoryStatistics` 按分类 UUID 聚合金额与笔数；`share` 保存精确的金额分子和总额分母，Core 不提前转换为浮点百分比。找不到分类或分类方向不匹配时保留原 UUID，使用“未知分类”并将 `isKnownCategory` 设为 `false`。分类结果和每个趋势点都提供稳定排序的 `entryIDs`，点击环形分类、类目排行或趋势点时可精确下钻。
- 分类按金额降序、名称 Unicode 顺序、UUID 字符串升序稳定排列；单笔按金额降序、记账日期降序、创建时间降序、UUID 字符串升序稳定排列，不依赖存储返回顺序。
- `LedgerStatisticsCalculator.monthly(entries:categories:kind:monthContaining:calendar:)` 返回选中自然月的统计快照和截至该月的最近 6 个自然月趋势。趋势从最早月份到选中月份固定返回 6 个点，没有记录的月份仍返回金额和笔数为零的点。
- Apple 侧先调用 `sixMonthDateRange(endingAtMonthContaining:calendar:)` 获取有界查询范围，再由 Storage 按当前账本读取这 6 个月的账目并传给 `monthly`。Core 只计算，不依赖 SwiftData、SwiftUI 或图表框架；本项不代表统计 UI 已完成。
- 全部金额使用 `Int64` 分并检查加总溢出；溢出抛出 `summaryOverflow`。无效记账日期、创建时间或选中月份抛出 `invalidDate`；日历由调用方注入并跟随设备当前本地时区。

### 初始数据与范围

`LedgerSeedData.books` 包含“默认账本”，`defaultBook` 提供其稳定 ID；旧版内置“日常账本”由 Storage 的一次性种子迁移合并到“默认账本”。`categories` 按用户于 2026-10-28 提供的喵喵记账截图补齐支出分类，顺序为：**餐饮、交通、购物、宠物、住房、零食、旅行、通讯、医疗、Pos、其它、礼金、运动**。原有“日用”额外保留在支出末尾，收入仍为工资、奖金、其他收入。截图中的“设置”是分类管理入口，不加入分类种子，也不扩展本轮分类 CRUD。

种子 UUID 使用前缀 `A20E127A-36F6-401A-A6E3-` 和下表的 12 位后缀，供 Storage 幂等初始化／升级和 UI 共用：

| 分类 | 后缀 | 兼容约定 |
| --- | --- | --- |
| 餐饮、交通、购物、日用 | `000000000101`–`000000000104` | 保持原 ID，“日用”仅调整顺序 |
| 其它 | `000000000105` | 原“其他支出”的同 ID 显示名更新 |
| 宠物、住房、零食、旅行、通讯、医疗、Pos、礼金、运动 | `000000000106`–`000000000114` | 按列出顺序分配新 ID |
| 工资、奖金、其他收入 | `000000000201`–`000000000203` | 名称、顺序、收入方向及 ID 均保持原样 |

本次核实范围仅为截图中支出分类的名称与顺序；收入仍沿用 M2 初始选项，其他交互继续以实际参考材料为准。Core 只定义契约和规则；已有数据库的种子补齐、同 ID 名称更新及历史引用保留由 Storage 实现并验证。持久化、CRUD 的原子写入、重复 ID 拦截、时间戳维护、同步实现和双端页面接入由对应模块实现。M2 不包含删除账本、分类管理、多币种或定时规则。

## 构建

在仓库根目录执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/core-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/core-swift
```

Manifest 使用 `swift-tools-version: 6.0`，Swift 语言模式为 6。临时构建基线为 macOS 14 / iOS 17；产品最低支持系统版本仍待 main 确认。

验证记录（2026-11-02）：使用指定 Xcode 的 Swift 6.4 / arm64 环境运行上述测试命令，构建通过，**96 项测试全部通过**。其中 8 项账单统计测试覆盖收入／支出切换、半开范围边界、精确占比基础数据、未知分类、分类与单笔稳定排序、跨年六个月趋势、零月份、本地 Calendar、溢出和无效日期；8 项定时记账算法测试覆盖固定日期月底收敛、最后一天、闰年、注入时区、跨月补记、已处理／已删除 occurrence、暂停恢复、未来月份修改边界、下一执行日、稳定 key 和非法规则；2 项仓库边界测试覆盖 existential 注入、完整规则生命周期、原子处理结果、下一日期及领域错误；截图识别现有 15 项文字规则测试与 8 项原图 Vision 集成测试；其余测试继续覆盖 CSV 导入、文件夹同步、产品元数据、金额、表达式、基础汇总、本地日期范围、DST、关联校验、默认账本名称和分类种子。

## 后续业务约定

iPhone 采用手机当前系统本地时区计算日期范围和定时规则。当前只接入 iPhone App，Mac 端暂不开发；跨设备幂等后续沿用稳定 occurrence key 与用户选定文件夹同步。
