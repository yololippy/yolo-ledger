# 共享界面模块

Swift module / library：`YoloLedgerUI`，仅依赖本地 `YoloLedgerCore`。

`YoloLedgerRootView(repository:)` 接受 `any LedgerRepository`，不直接引用 SwiftData。iPhone 还可通过 `YoloLedgerRootView(repository:pendingScreenshotProposal:)` 注入快捷指令识别结果；根页面等待数据加载完成后打开记账确认页。App 长期持有磁盘仓库，根页面的 `LedgerAppModel` 为所有入口提供同一套账本、分类和账目状态。

## 界面与功能

当前页面属于已完成记账功能验证的历史临时界面，后续将替换为有落自己的视觉与交互设计。分类插画继续使用项目内代码绘制，营销图片与外部角色素材不打包进 App。

## 主题架构

- 所有共享页面、组件和代码绘制插画均从 SwiftUI 环境读取 `LedgerTheme`，页面文件内不保存 RGB 色值。
- [LedgerThemeValues.swift](Sources/YoloLedgerUI/LedgerThemeValues.swift) 集中定义语义色和当前 `.pastel` 主题；新增暗黑模式或其他主题时增加一个主题预设即可。
- App 组装层通过 `.ledgerTheme(.pastel)` 注入当前主题，未来可在这里跟随系统外观或用户设置切换，不需要逐页改颜色。
- 当前底部导航、数字键盘和账目详情的大面积背景统一使用粉彩浅蓝 `#C6E2FF`；亮系统蓝仍用于 tint 与选中态，橙色保留为关键动作色。

- iPhone 使用固定底栏：明细、账单、中央加号、账本、我的。Mac 使用同色系桌面侧栏，支持 Cmd+N 和保存默认键盘动作。
- 记账页使用四列圆形分类与四列数字键盘；可选择支出／收入、真实分类、账本、日期和备注。备注键盘可收起，继续使用数字键盘。
- 支出分类按用户实机截图排列：餐饮、交通、购物、宠物、住房、零食、旅行、通讯、医疗、Pos、其它、礼金、运动，并在末尾保留原有日用；收入为工资、奖金、其他收入。分类网格可滚动，猫咪、住房、蛋糕、飞机、电话、医疗箱、票券、省略号、礼金袋和运动鞋使用代码绘制的插画。
- 分类圆形按钮最大为 70 点，窄列随实际可用宽度等比缩小，维持四列，避免固定宽度挤出网格；切换收支类型时滚动位置回到顶部。
- 数字键盘支持加减表达式，保存调用 Core 的 `LedgerAmountExpression.evaluate`；例如 `12.34+7.66-5` 保存为 `15.00`，非法表达式保留输入。
- 记账成功后，输入过的非空备注会按分类从账目中去重提取；记账页只展示当前选中分类的备注，按 FIFO 顺序横向排列最多 20 条，点击即可填入并继续使用数字键盘，超出上限时淘汰最早的备注。该记录沿用账目本身的本地持久化和 iCloud 同步，不另建备注数据库。
- 账单按所选月份显示真实收支、结余、黄色支出／粉色收入条及日分组记录。
- 明细提供真实月日历、前后月切换、每日结余、日期选择、当日收支及列表筛选；选中某一天后点击中央加号，新账目默认使用该日期；再次点击同一天或“查看整月”取消日期筛选。
- 账单与明细共用自研年月选择器：点击年月标题后，iPhone 显示紧凑 Sheet，Mac 显示标题锚定 Popover；月份使用 3 × 4 网格，点击年份可进入每页 12 年的快速选择。左右按钮或横向滑动切换年份；月份高亮同时匹配选中年份，切到其他年份不会保留旧月份高亮；“回到本月”只导航并保持面板打开。iPhone 禁用系统拖拽关闭以免横滑误关，使用右上角关闭按钮主动退出。未引入第三方日历代码。
- 详情使用白色票据、虚线和锯齿底边，支持编辑与确认删除。账本支持新建、重命名、切换；“我的”展示离线、检查、同步、暂停或错误状态。
- iPhone 快捷指令截图识别结果进入“确认截图记账”页面，预填金额、日期、商户备注和分类建议；用户确认保存后将来源记为 `.screenshotShortcut`。
- iPhone“我的”页面提供“轻点两下，截图记账”三步设置指引和快捷指令跳转；系统的“轻点背面”绑定仍由用户在设置中完成。

账本与“我的”未在参考截图中完整展示，按同一视觉组件适配现有功能，不声称精确还原未知页面。未增加预算、猫咪游戏、存钱等无对应实现的入口。完整分类管理、图表、导入导出和定时记账仍属于后续阶段；iCloud 的真实双设备验收单独跟踪。

## 状态与数据

- 金额解析、格式化、日期范围和汇总使用 Core；月份、日期均按当前系统本地时区计算，前台恢复会刷新数据并保留浏览月份。
- 保存成功会切到记录所属月份，并清理不匹配的日期筛选，让新建或改期后的记录可见。
- 保存中禁止重复提交和继续编辑输入；失败保留输入。新建 UUID 在编辑器生命周期内保持不变。
- 写入成功但刷新失败仍保留返回记录并提示“已保存，但刷新失败”；重试只读取，不再次写入。
- 刷新使用代次标识，旧请求或取消请求不能覆盖新快照。重命名其他账本不改变当前选择。
- UI 订阅仓库变更流；CloudKit 导入或账户／同步状态变化后自动重新读取，回到前台也会刷新。本地测试仓库的默认变更流会正常结束，不产生常驻任务。

## 验证

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path packages/ui-swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path packages/ui-swift
```

2026-10-28：10 项状态测试通过，覆盖读取失败重试、保存／编辑／删除与汇总、失败保持数据、写入成功后刷新失败、防重复提交、账本选择、旧刷新取消、日／月筛选、刷新保留月份、保存后记录可见性，以及年月选择的月初归一化和日期筛选清理。

端到端流程、独立测试账库与报告见 [Xcode 工程说明](../../apps/xcode/README.md)。

## 辅助功能标识

- 导航：`navigation.details`、`navigation.bills`、`navigation.books`、`navigation.settings`、`entry.add`。
- 编辑：`editor.title`、`editor.screenshot-confirmation`、`editor.kind.expense`／`income`、`editor.amount`、`editor.categories`（分类滚动区）、`editor.category.<UUID>`、`editor.book`、`editor.date`、`editor.note`、`editor.note-suggestions`、`editor.note-suggestion.<index>`、`editor.keypad-return`、`editor.save`、`editor.cancel`、`editor.error`。
- 数字键盘：`keypad.0` 至 `keypad.9`、`keypad..`、`keypad.+`、`keypad.-`、`keypad.delete`、`keypad.date`。
- 日历：`month.previous`、`month.next`、`month.title`、`month-picker.year-toggle`、`month-picker.year.previous`、`month-picker.year.next`、`month-picker.range.previous`、`month-picker.range.next`、`month-picker.month.<1...12>`、`month-picker.year.<year>`、`month-picker.current`、`month-picker.back-to-months`、`month-picker.close`、`calendar.day.<day>`、`calendar.clear-selection`。
- 详情：`entry.row.<UUID>`、`detail.amount`、`detail.note`、`entry.edit`、`entry.delete`、`entry.delete.confirm`、`detail.close`。票据按 `updatedAt` 重建，保持编辑后的辅助功能内容同步。
- 账本／汇总：`ledger.book-picker`、`book.add`、`book.select.<UUID>`、`book.rename.<UUID>`、`book-editor.name`、`book-editor.save`、`summary.income`、`summary.expense`、`summary.balance`。

Swift tools 6.0 / Swift 6；临时构建基线为 macOS 14 / iOS 17，正式最低支持版本仍待确定。仅面向 Mac / iPhone，iPadOS 暂不支持。
