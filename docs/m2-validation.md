# M2 本地记账验收

> 本页保留 UI 重做前的 M2 功能验收记录。此后已归档喵喵记账官方参考并完成当前页面重做，最新截图与验证见 [UI 验收记录](ui-validation.md)。

日期：2026-10-28。环境为 Xcode 27.1、macOS 27.0.1（arm64），iPhone 18 Pro / iOS 27.0 模拟器。真机及正式最低系统版本兼容性尚未验收。

## 自动化验证

- Core：26 项测试通过，覆盖精确金额、非法输入、溢出、本地日／周／月／年范围、夏令时、闰年、汇总与关联校验。
- Storage：15 项测试通过，覆盖 SwiftData 真实磁盘读写、仓库重开、种子幂等、CRUD、账本筛选、并发重复 ID、损坏文件与失败回滚。明确关闭 CloudKit，无内存或删除数据库的回退策略。
- UI 状态：7 项测试通过，覆盖读取失败重试、增删改刷新、保存失败保留原值、已保存但刷新失败、防重复提交、账本切换和旧请求取消。
- iPhone：4 项 UI 场景均通过。`ios-flows-final` 中账本管理／收入／切换、四页导航、启动失败重试 3 项通过；修正测试输入和辅助功能查询后，`ios-entry-lifecycle-final` 中新增／编辑／重启保留／删除／删除后重启 1 项通过。两份结果共同覆盖本轮全部用例，并非声称首轮全量运行无失败。

结果包为 `/tmp/yolo-ledger-m2-ios-flows-final.xcresult` 与 `/tmp/yolo-ledger-m2-ios-entry-lifecycle-final.xcresult`，对应同名 `.log`。首轮失败定位为测试光标清空方式、系统字段名前缀和确认按钮父子查询重复，均已修正并复测。

包测试命令：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path packages/core-swift
swift test --package-path packages/storage-swift
swift test --package-path packages/ui-swift
```

## Mac 实际操作

使用 Debug 的独立账库参数，未向日常账库写入测试记录：

```sh
open -n /tmp/yolo-ledger-m2-macos/Build/Products/Debug/YoloLedgerMac.app \
  --args --ui-test-store 89D17744-F7D0-46B6-8AAC-88E080D2FC87
```

已通过 native computer-use 操作验证：

1. 空金额保存被拦截；输入支出 12.34 后正确显示记录和汇总。
2. 编辑为 23.45，并录入中文备注；详情、账单、汇总更新。
3. 切换收入后分类更新为收入分类；收入 100.00 与支出 23.45 得到结余 76.55。
4. 新建账本并重命名，切换后只显示所选账本的数据和汇总。
5. 退出并使用相同独立账库重开，收入、编辑后的支出及中文备注保留。
6. 删除入口会显示确认提示；取消删除后原记录保留。最终删除及删除后的重开由 Storage / UI 自动化和 iPhone 流程验证，未将 Mac 取消确认描述为执行删除。
7. 修复详情辅助功能旧值后，再编辑 23.45 为 24.56，画面与辅助功能读取均刷新；Cmd+N 打开表单，Return 保存，取消新增不会产生记录。

Mac 最终构建日志：`/tmp/yolo-ledger-m2-macos-final-build.log`。本轮未重跑 M1 曾因 automation mode 初始化超时失败的 Mac XCTest runner。

## 验收范围

M2 交付本地手动记账、基础账本／分类选择和当前月汇总。喵喵记账截图／录屏尚未归档，未宣称完成界面还原；完整分类管理、周／年统计界面、导入导出、定时记账、备份恢复和 iCloud 仍按后续里程碑推进。

V1 schema 与迁移计划入口已建立，尚未验证未来版本升级。测试记录为人工样本，测试账库使用 UUID 独立目录；Debug 测试参数在 Release 不生效。
