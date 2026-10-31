# 用户选定文件夹同步方案

## 1. 当前结论

有落记账的默认同步方案改为：本地 SwiftData + 用户选定文件夹交换。用户可在 iPhone 或 Mac 的“我的”页面选择 iCloud Drive 中的文件夹，也可以选择其他系统文件提供方或普通可写目录。

- 日常读写始终先落到各设备 App 容器内的 SwiftData 数据库，断网和未配置同步时仍可正常记账。
- App 不申请 CloudKit、iCloud Container、推送或远程通知权限，因此可使用免费的 Apple Developer Personal Team 构建和安装。
- 文件夹权限由系统选择器授予；App 保存安全作用域 bookmark，覆盖安装和重启后恢复访问。
- 同步目录只保存版本化 JSON 交换文件，不保存正在运行的 SQLite、WAL 或 SHM。
- 首次选择、App 启动、回到前台、本地数据变化和用户点击“立即同步”时尝试同步。
- iOS 后台刷新属于 best-effort，由系统决定是否及何时执行，不能承诺实时同步。
- iPadOS 暂不支持。

CloudKit 仍可作为未来取得付费开发者账号后的可选方案，但不是当前 Target 的默认能力，也不影响本方案的文件格式和本地数据库。

## 2. 为什么采用该方案

免费的 Personal Team 不支持 CloudKit、iCloud Documents App Container、iCloud Key-Value Storage 或推送权限，但 App 可以通过系统文件选择器访问用户主动选择的目录。用户如果在两台设备上选择同一个 iCloud Drive 文件夹，文件本身由 iCloud Drive 负责传输，有落记账负责读取、验证、合并和写回。

这不是 CloudKit 的等价替代：系统文件传输和后台执行都没有实时保证。因此产品文案使用“尝试同步”“最近成功”，并保留明确的“立即同步”按钮。

## 3. 数据结构

```text
iPhone / Mac
├── App 容器
│   └── Application Support/YoloLedger/ledger.store
│       ├── 本地 SwiftData / SQLite
│       ├── WAL / SHM
│       └── 本地升级快照
│
└── 用户选择的文件夹
    └── 有落记账同步数据/
        └── devices/
            ├── <安装 A 的 UUID>.json
            └── <安装 B 的 UUID>.json
```

每个安装生成并持久化一个随机 UUID，仅用于区分交换文件，不使用设备名称、硬件标识、Apple Account 或其他个人信息。每台设备只原子替换自己的 JSON 文件，不覆盖其他设备文件。

## 4. JSON 交换协议

每个设备文件是一份完整合并快照，包含：

- `formatVersion`：文件协议版本。
- `schemaVersion`：本地数据模型版本。
- `deviceID`：当前安装的随机 UUID，必须与文件名一致。
- `generatedAt`：生成时间，使用带小数秒的 UTC ISO 8601。
- `books`：账本 UUID、名称、顺序、创建／修改／删除时间。
- `categories`：分类 UUID、名称、收支类型、顺序、创建／修改／删除时间。
- `entries`：账目 UUID、账本／分类 UUID、金额分值、发生时间、备注、来源及创建／修改／删除时间。

读取时会检查格式版本、Schema 版本、文件名、UUID 唯一性、枚举值、时间、关联关系和金额字段。任何可见 JSON 损坏或版本不受支持时，本轮同步失败，并且不会把该批快照部分导入本地。

写入使用同目录临时文件和原子替换，并通过系统文件协调 API 与 iCloud Drive 或其他文件提供方协作。临时文件失败时会清理，不留下半份正式 JSON。

## 5. 合并与删除规则

1. 先完整读取并验证目录中的全部设备快照。
2. 将本地全部记录（包括软删除记录）和远端快照按业务 UUID 分组。
3. 比较 `max(updatedAt, deletedAt)`，时间较新的记录获胜。
4. 时间完全相同时，软删除优先，防止另一台设备把已删除记录复活。
5. 仍相同时，使用稳定序列化字段和来源 `deviceID` 排序，保证不同设备得到相同结果。
6. 账本、分类和账目在一次本地保存中应用；失败回滚本轮本地变更。
7. 成功合并后，将完整结果写为当前设备的新快照。

缺少某台设备的文件不等于删除记录。软删除标记当前不会自动清理；以后增加压缩或墓碑回收时，需要先定义所有设备确认边界。

## 6. 权限与隐私

- 文件夹必须由用户通过系统选择器主动选择。
- App 只保存系统 bookmark、文件夹显示名、安装随机 UUID 和最近同步摘要。
- 每次同步前恢复 URL 并调用 `startAccessingSecurityScopedResource()`，结束后立即停止访问。
- bookmark 过期时尝试更新；权限被撤销、目录被移动或文件提供方不可用时显示错误，要求用户重新选择。
- 停止使用文件夹只删除本机保存的授权和状态，不删除文件夹中的交换文件，也不删除本地账目。
- 同步文件是可读 JSON，不等同于加密备份。用户应选择自己的私有目录；将目录共享给他人会同时共享账目内容。

## 7. 自动与手动时机

有落记账在以下时机触发一次合并：

- 首次选择或更换文件夹后。
- App 打开并恢复文件夹权限后。
- App 从后台回到前台后。
- 新增、编辑、删除账目或变更账本后，短暂去抖再同步。
- 用户点击“立即同步”后。
- iOS 系统授予后台刷新时间时。

同一时刻只运行一个同步任务；期间再次发生变化时，当前任务结束后再补一次。同步失败不阻止本地记账，不会清空或重建本地数据库。

Mac 仅在 App 活跃时工作，不安装常驻守护进程。iOS 后台刷新由 `BGAppRefreshTask` 提交请求，但低电量、后台刷新关闭、系统资源不足、App 被用户强制退出等情况都会延迟或阻止执行。

## 8. 设置页状态

未配置时显示：

- 选择同步文件夹。
- 说明可选择 iCloud Drive 或普通可写文件夹。

配置后显示：

- 当前文件夹名称。
- 正在同步、最近成功或错误状态。
- 最近成功时间、本轮导入记录数和导出记录数。
- 立即同步、更换文件夹、停止使用。
- iPhone 后台同步由系统决定、不能保证实时的提示。

这里没有“登录有落记账”或“登录 iCloud”的步骤。能否看到 iCloud Drive 取决于设备系统的 Apple Account 和 iCloud Drive 设置；有落记账只使用系统选择器返回的目录权限。

## 9. 从旧 CloudKit 测试配置切换

- 保持 iPhone 与 Mac 的 Bundle ID `com.yololedger.app` 不变。
- 保持 `Application Support/YoloLedger/ledger.store` 路径不变，不删除现有本地数据。
- 正常 App 的 SwiftData 配置改回 `.local`。
- Target 移除 CloudKit、iCloud Documents、Push Notifications 和 Remote notifications 权限。
- iPhone 保留 `NSFileProtectionComplete`；Mac 沙盒增加用户选择文件夹的读写权限。
- 删除旧的 iCloud Container 启动初始化和 `NSUbiquitousContainers` 配置。

此前真实存在于本机 SwiftData 的记录会继续保留。尚未下载到本机、只存在于 CloudKit 远端的测试数据不会由文件夹方案自动迁移；当前项目尚未完成真实 CloudKit 双设备验收，因此不提供远端迁移工具。

## 10. 验收标准

- 同一文件夹下，设备 A 新增后同步，设备 B 能导入并显示。
- B 修改或删除后，A 再同步可收敛，删除记录不会复活。
- 两台设备离线各自新增后，恢复文件可用时双方最终都包含两边记录。
- 相同 UUID、相同时间的冲突在不同同步顺序下得到相同结果。
- 损坏、不支持版本或关联无效的快照不会造成部分导入。
- 同一设备文件通过临时文件原子替换，重开 App 后本地记录保持。
- 覆盖安装保留本地账库、bookmark 和安装 UUID。
- 目录失效或 iCloud Drive 暂不可用时，本地新增、编辑和删除仍正常。
- iPhone 与 Mac 均能选择目录、立即同步、恢复权限和停止使用。
- Personal Team 构建不再请求不受支持的 iCloud、CloudKit 或推送 entitlement。

## 11. 已知边界

- 文件传输是否完成由 iCloud Drive 或所选文件提供方决定；“同步成功”表示本轮成功读取当前可见文件并写回本设备快照，不保证另一台设备已经下载。
- 后台刷新不是定时器，也不是实时推送。
- 交换 JSON 当前未做额外端到端加密。
- 本方案不是历史备份；删除和修改会传播。独立的可恢复备份仍按 M4 实现。
- 文件数量会随安装数量增加；设备管理、过期设备清理和墓碑压缩属于后续功能。

## 12. Apple 参考

- [Apple：Accessing documents](https://developer.apple.com/documentation/uikit/view_controllers/providing_access_to_directories)
- [Apple：Managing Documents in Your iOS Apps](https://developer.apple.com/documentation/uikit/managing-documents-in-your-ios-apps)
- [Apple：URL security-scoped resources](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource())
- [Apple：NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [Apple：Using background tasks](https://developer.apple.com/documentation/backgroundtasks/using-background-tasks)
- [Apple：Supported capabilities for free and paid accounts](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
