# 共享界面模块

Swift module / library：`YoloLedgerUI`，仅依赖本地 `YoloLedgerCore`。

`YoloLedgerRootView(repository:)` 接受 `any LedgerRepository`，不直接引用 SwiftData。iPhone 还可通过 `YoloLedgerRootView(repository:pendingScreenshotProposal:)` 注入快捷指令识别结果；根页面等待数据加载完成后打开记账确认页。App 长期持有磁盘仓库，根页面的 `LedgerAppModel` 为所有入口提供同一套账本、分类和当前浏览窗口的账目状态，不在内存中常驻全部历史。

## 界面与功能

当前页面属于已完成记账功能验证的历史临时界面，后续将替换为有落记账的视觉与交互设计。分类插画继续使用项目内代码绘制，营销图片与外部角色素材不打包进 App。

## 主题架构

- 所有共享页面、组件和代码绘制插画均从 SwiftUI 环境读取 `LedgerTheme`，页面文件内不保存 RGB 色值。
- [LedgerThemeValues.swift](Sources/YoloLedgerUI/LedgerThemeValues.swift) 集中定义语义色和当前 `.pastel` 主题；未来新增暗黑模式或其他主题时，只需增加主题预设并调整平台外观策略。
- App 组装层通过 `.ledgerTheme(.pastel)` 注入当前主题。现阶段 iPhone 明确锁定浅色外观，系统键盘同样使用浅色样式；未来完成暗黑主题设计后再开放跟随系统或用户设置切换，不需要逐页改颜色。
- 当前底部导航、数字键盘和账目详情的大面积背景统一使用粉彩浅蓝 `#C6E2FF`；亮系统蓝仍用于 tint 与选中态，橙色保留为关键动作色。

- iPhone 使用固定底栏：明细、账单、中央加号、账本、我的。Mac 使用同色系桌面侧栏，支持 Cmd+N 和保存默认键盘动作。
- 记账页使用四列圆形分类与四列数字键盘；可选择支出／收入、真实分类、账本、日期和备注。系统备注键盘使用自带“完成”键收起，随后恢复数字键盘。
- iPhone 的备注与当前金额共用白色输入卡片，点击卡片任意位置（包括右侧金额）都会进入备注输入；系统键盘出现时隐藏自定义数字键盘，通过系统“完成”键收起后恢复。输入卡片使用更紧凑的垂直留白并固定固有高度，不会在自定义数字键盘显示时被页面压矮，因此两种键盘状态下高度一致；数字键盘整体更贴近屏幕底部。右侧金额使用 32 点单行显示，长金额自动缩放；Mac 仍保留原输入高度和可直接编辑的金额文本框。
- 支出分类按用户实机截图排列：餐饮、交通、购物、宠物、住房、零食、旅行、通讯、医疗、Pos、其它、礼金、运动，并在末尾保留原有日用；收入为工资、奖金、其他收入。分类网格可滚动，猫咪、住房、蛋糕、飞机、电话、医疗箱、票券、省略号、礼金袋和运动鞋使用代码绘制的插画。
- 分类圆形按钮最大为 70 点，窄列随实际可用宽度等比缩小，维持四列，避免固定宽度挤出网格；切换收支类型时滚动位置回到顶部。
- 数字键盘支持加减表达式，保存调用 Core 的 `LedgerAmountExpression.evaluate`；例如 `12.34+7.66-5` 保存为 `15.00`，非法表达式保留输入。
- 记账成功后，输入过的非空备注会按分类从账目中去重提取；记账页只展示当前选中分类的备注，按 FIFO 顺序横向排列最多 20 条，点击即可填入并继续使用数字键盘，超出上限时淘汰最早的备注。该记录沿用账目本身的本地持久化和可选文件夹同步，不另建备注数据库。
- iPhone“账单”保留账本、月份和本月结余卡，并新增支出／收入统计切换：最近 6 个月趋势、分类占比环图、分类排行和明细排行。趋势固定包含所选月份及此前 5 个月（无数据月份也保留）；分类和趋势可进入账目列表，明细排行可直接打开票据详情，关闭详情后保持原浏览月份和层级。Mac 仍使用原月账单列表，仅保留构建兼容。
- 明细提供真实月日历、前后月切换、每日结余、日期选择、当日收支及列表筛选；日历卡片横向拖动时当前月跟手移动、相邻月同步进入，达到位移阈值或预测终点后完成翻页，否则回弹。左滑进入下一月、右滑返回上一月，箭头与手势复用同一段过渡动画，日期点击和纵向滚动保持可用。选中某一天后点击中央加号，新账目默认使用该日期；再次点击同一天或“查看整月”取消日期筛选。
- 账单与明细共用自研年月选择器：点击年月标题后，iPhone 显示紧凑 Sheet，Mac 显示标题锚定 Popover；月份使用 3 × 4 网格，点击年份可进入每页 12 年的快速选择。月份模式按年分页，年份模式按 12 年范围分页，两种模式与日历共用横向分页组件，左右按钮和手势走相同动画。月份高亮同时匹配选中年份，切到其他年份不会保留旧月份高亮；“回到本月”只导航并保持面板打开。iPhone 点击 Sheet 外部灰色区域关闭，Mac Popover 点击外部自然关闭；两端均不显示额外关闭按钮。未引入第三方日历代码。
- 详情使用白色票据、虚线和锯齿底边，支持编辑与确认删除。账本支持新建、重命名、切换；“我的”提供选择、立即同步、更换文件夹和关闭文件夹同步，并展示文件夹名、最后成功时间、导入／导出数量、同步中或错误状态。
- 喵喵记账 CSV 导入作为一次性迁移能力保留在代码中，但完成迁移后不再显示于“我的”页面。`LedgerMeowImportController` 及预览、校验、备份和导入测试继续保留，后续需要时可重新开放入口。
- 导入确认页明确说明不会修改喵喵记账数据，并会在写入前创建本地备份。UI 只依赖 Core 的导入计划；真实写入通过 App 组装层注入的异步动作交给 Storage，提交期间禁止重复操作。成功报告展示导入、跳过重复、创建账本／分类、收支汇总和备份目录名；失败保留预览与来源文件，可重新选择或取消。
- iPhone“我的”在注入 `any LedgerScheduledEntryRepository` 时显示“定时记账”，支持新建、编辑、启用／暂停和删除。规则可选择账本、收入／支出、匹配类型的分类、精确金额、备注、每月 1...31 日或最后一天；新建从当前本地月份生效，编辑明确只影响所选当前／未来月份。`LedgerScheduledEntryController` 仅依赖 Core，repository 为 `nil` 时隐藏入口，Mac 不创建此运行时能力。
- iPhone 快捷指令截图识别结果进入“确认截图记账”页面，预填金额、日期、商户备注和分类建议；用户确认保存后将来源记为 `.screenshotShortcut`。
- iPhone“我的”页面提供“轻点两下，截图记账”三步设置指引和快捷指令跳转；系统的“轻点背面”绑定仍由用户在设置中完成。

当前界面只是已实现功能的历史验证载体，后续以有落记账的品牌和交互设计为准。完整分类管理和通用导入导出仍属于后续阶段；用户选择文件夹的真实双设备验收单独跟踪。

## 状态与数据

- 金额解析、格式化、日期范围和汇总使用 Core；月份、日期均按当前系统本地时区计算，前台恢复会刷新数据并保留浏览月份。
- 首次读取和切换月份只请求当前账本的前一月、当前月、后一月，既保证横向分页相邻页有数据，又让启动耗时不随历史总量线性增长。切换账本同样只重载该窗口；常用备注进入记账页后按分类异步读取。
- iPhone 统计使用独立 controller，按当前账本、浏览月份和收支类型请求 Core 给出的精确六个月半开区间，不扩张 `LedgerAppModel` 的三个月可见窗口，也不读取全部历史。切换上下文或刷新时使用代次标识，较慢的旧请求不能覆盖最新统计；同一上下文刷新失败时保留已有结果并在统计区内显示重试。
- “正在读取本地账目”作为异常慢读取的兜底保留，但延迟 400 毫秒才显示；正常毫秒级加载直接进入首页，不闪加载提示。
- 保存成功会切到记录所属月份，并清理不匹配的日期筛选，让新建或改期后的记录可见。
- 保存中禁止重复提交和继续编辑输入；失败保留输入。新建 UUID 在编辑器生命周期内保持不变。
- 写入成功但刷新失败仍保留返回记录并提示“已保存，但刷新失败”；重试只读取，不再次写入。
- 刷新使用代次标识，旧请求或取消请求不能覆盖新快照。重命名其他账本不改变当前选择。
- UI 订阅仓库变更流；文件夹同步成功后通过控制器修订号自动重新读取，回到前台也会刷新。本地写入成功后通知 App 层防抖同步；同步失败不改变本地 CRUD 结果。

## 验证

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/ui-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/ui-swift
```

2026-11-02：39 项状态测试通过。在原有 35 项基础上，新增统计精确六个月范围与空月份、收入／支出切换、旧请求防覆盖、失败保留结果与重试 4 项测试。

端到端流程、独立测试账库与报告见 [Xcode 工程说明](../../apps/xcode/README.md)。

## 辅助功能标识

- 导航：`navigation.details`、`navigation.bills`、`navigation.books`、`navigation.settings`、`entry.add`。
- 编辑：`editor.title`、`editor.screenshot-confirmation`、`editor.kind.expense`／`income`、`editor.input-card`、`editor.amount`、`editor.categories`（分类滚动区）、`editor.category.<UUID>`、`editor.book`、`editor.date`、`editor.note`、`editor.note-suggestions`、`editor.note-suggestion.<index>`、`editor.save`、`editor.cancel`、`editor.error`。
- 数字键盘：`keypad.0` 至 `keypad.9`、`keypad..`、`keypad.+`、`keypad.-`、`keypad.delete`、`keypad.date`。
- 日历与年月分页：`calendar.card`、`calendar.pager`、`month.previous`、`month.next`、`month.title`、`month-picker.year-pager`、`month-picker.range-pager`、`month-picker.year-toggle`、`month-picker.year.previous`、`month-picker.year.next`、`month-picker.range.previous`、`month-picker.range.next`、`month-picker.month.<1...12>`、`month-picker.year.<year>`、`month-picker.current`、`month-picker.back-to-months`、`calendar.day.<day>`、`calendar.clear-selection`。
- 详情：`entry.row.<UUID>`、`detail.amount`、`detail.note`、`entry.edit`、`entry.delete`、`entry.delete.confirm`、`detail.close`。票据按 `updatedAt` 重建，保持编辑后的辅助功能内容同步。
- 账本／汇总：`ledger.book-picker`、`book.add`、`book.select.<UUID>`、`book.rename.<UUID>`、`book-editor.name`、`book-editor.save`、`summary.income`、`summary.expense`、`summary.balance`。
- iPhone 统计：`statistics.kind.expense`／`income`、`statistics.trend`、`statistics.trend.month.<yyyy-MM>`、`statistics.donut`、`statistics.categories`、`statistics.category.<UUID>`、`statistics.categories.expand`、`statistics.entries`、`statistics.entry.<UUID>`、`statistics.entries.expand`、`statistics.drilldown`、`statistics.drilldown.entry.<UUID>`、`statistics.drilldown.close`、`statistics.error`、`statistics.retry`。
- 喵喵导入：`settings.meow-import.card`、`settings.meow-import.choose`、`meow-import.metrics`、`meow-import.summary`、`meow-import.issues`、`meow-import.safety`、`meow-import.failure`、`meow-import.success`、`meow-import.reselect`、`meow-import.confirm`、`meow-import.cancel`、`meow-import.done`。
- 定时记账：`settings.scheduled-entry.card`、`settings.scheduled-entry.open`、`scheduled-entry.timing`、`scheduled-entry.add`、`scheduled-entry.empty-add`、`scheduled-entry.rule.<UUID>`、`scheduled-entry.edit.<UUID>`、`scheduled-entry.toggle.<UUID>`、`scheduled-entry.delete.<UUID>`、`scheduled-entry.delete.confirm`，以及 `scheduled-entry.editor.*` 表单标识。

Swift tools 6.0 / Swift 6；临时构建基线为 macOS 14 / iOS 17，正式最低支持版本仍待确定。仅面向 Mac / iPhone，iPadOS 暂不支持。
