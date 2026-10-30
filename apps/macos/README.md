# macOS App

`Sources/YoloLedgerMac/YoloLedgerMacApp.swift` 为原生 Mac 入口，由 `YoloLedgerMac` target 构建。入口持有长期存在的启动状态，通过共用的 App 组装代码打开 SwiftData 磁盘仓库并注入 UI。

当前支持本地手动收支、详情／编辑／确认删除、基础账本管理及选择、当前月汇总。账单／明细页支持 Cmd+N；表单支持默认保存键盘动作。

Bundle ID：`com.yololedger.app`，与 iPhone Target 统一并共享 `iCloud.com.yololedger.app`。当前开发机为 Mac mini（Apple M6、24 GB、arm64），运行 macOS 27.0.1（26A434）。工程临时构建基线是 macOS 14，正式最低支持版本仍待确定。

main 于 2026-10-28 使用独立 DEBUG 账库进行 native computer-use 验收：新增支出、修改金额与中文备注、收入分类、月度收支结余、账本创建／重命名／切换，以及重启保留均已通过。删除确认与取消已验证；真正确认删除的端到端流程由 iPhone XCTest 覆盖。后续复测还确认 Cmd+N、Return 保存、金额标签及编辑后详情辅助功能金额立即更新。

M1 的 Mac XCTest runner 因 automation mode 初始化超时未能执行；本轮未再次运行该 runner 或触发系统密码请求。Mac 实际操作验收与 XCTest 结果分别记录。

最新 main 构建日志为 `/tmp/yolo-ledger-m2-macos-final-build.log`。隔离账库启动命令、构建产物与验证证据见 [Xcode 工程说明](../xcode/README.md)。
