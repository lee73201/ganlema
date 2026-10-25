> 后续 0.3.0 阶段的结果、系统权限限制和 GitHub 备份见 [VALIDATION-PHASE2.md](VALIDATION-PHASE2.md)。本文件保留为 0.2 历史记录。

# 干了吗（FocusDock）0.2 验证记录

验证日期：2026-10-25（Asia/Shanghai）。在现有 FocusDock 工程增量修改，没有重建项目。

## 最终产物

- 应用：`build/干了吗.app`，版本 0.2.0 / build 3，Release、本机临时签名。
- 最终应用已启动，并切回原来的真实数据库和偏好域；验收草稿已取消。
- 主面板 368×506pt，胶囊 176×50pt。三页实际截图均保持同样的展开尺寸，没有随任务数增长。
- Swift Package Release 构建及 Xcode Debug 构建/测试通过，两种测试入口均实际通过 **19/19** 项测试。

## 改动范围

AppKit `NSVisualEffectView` 置于透明 NSHostingView 后方，采用 `.popover`、`.behindWindow`、`.active`，并按胶囊或主面板轮廓裁切。SwiftUI 主面板不再用透明填色模拟毛玻璃，也没有覆盖一层实色背景。系统“降低透明度”等辅助功能设置仍由 AppKit 材质正常遵循。

主面板采用固定时钟/日期、今日完成进度、三标签、独立纵向列表和固定底部输入入口。任务行两行截断、可选类别、截止状态小圆点、直接删除；完成页显示完成时间并支持恢复；打卡页按周一至周日切换，支持周导航、重命名、删除和真实连续记录。

语音按钮保留为禁用占位，未增加麦克风授权、识别或 AI 功能。没有伪造语音能力或连续天数。

参考的 Apple 材质行为说明：[NSVisualEffectView behindWindow](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow)。

## 构建和自动化结果

环境为 Xcode 27.1、Apple Swift 6.4、macOS 26.6.2 arm64，部署目标 macOS 14。使用显式 DEVELOPER_DIR，不改变系统级开发工具选择。

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| Swift Package Debug 应用构建 | 通过 | 实际执行成功，最终日志随后由 Release 构建替换 |
| `bash scripts/build-app.sh` Release | 通过，退出码 0 | `Validation/ui-refactor-build.log` |
| `bash scripts/test.sh` | 19/19 通过，退出码 0 | `Validation/ui-refactor-tests.log` |
| 原 FocusDock Xcode scheme Debug build + test | TEST SUCCEEDED，19/19 通过，退出码 0 | `Validation/ui-refactor-xcode-test.log` |
| 签名验证 | valid on disk / satisfies its Designated Requirement | 实际运行 `codesign --verify --strict` |
| Info.plist / project.pbxproj 格式 | 通过 | 实际运行 plutil 检查 |
| 构建脚本语法 | 通过 | 实际运行 bash 语法检查 |
| 原 WindowPlacement / DragRegion 源码 | 与重构前副本一致 | 实际运行文件比较 |

Swift Package 在受限执行环境中输出过 CoreData 通知注册诊断，所有断言仍通过；Xcode 独立运行同一测试套件也全部通过。Release 符号生成使用获准的本地构建执行环境。

19 项测试包含原有任务 CRUD/重开/排序/校验、悬停/锁定/拖动状态与屏幕几何检查，以及新增：

1. 多习惯、多个自然日的独立打卡与同一天的取消。
2. 习惯新增、重命名、跨实例重开、历史打卡取消、删除后的记录清理。
3. 空习惯名称和非法编辑校验。
4. 周一开周、跨年、夏令时日期不重复。
5. 实际历史连续天数、断档、未打卡的今天及未来记录排除。
6. 任务类别规范化、持久化和 UUID 保留。
7. 重构前任务 schema 到新增可空类别字段的迁移。
8. 今日进度排除未来任务，空列表不除零。
9. 主动收起后等待鼠标移出再恢复悬停，直接点击仍可展开。

## 实际应用界面验收

隔离数据库中生成 36 条任务（包含超长中文标题、连续英文长字符串、已完成任务、不同截止时间）和 5 条习惯。测试工具独立于应用，所有示例仅保存在 `work/ui-refactor/qa-*`，没有混入真实数据。

已实际检查或操作：

- 浅色与深色下的主面板、长任务、任务状态和打卡页。
- 超长中文和不带空格的英文标题两行截断，没有水平溢出。
- 多任务列表滚动，顶部时间、进度、标签及底部入口保持固定。
- 原生细覆盖式滚动条；修复了系统“始终显示滚动条”导致的白色宽轨道，编辑器及备注区也已检查。
- 待办、已完成、打卡空状态，0/0 与 0% 正常显示。
- 新增任务与新增习惯的底部中文输入、回车提交、输入后清空和焦点保持。
- 实际完成一条隔离任务，进度变为 1/1、100%；完成页出现完成时间；恢复后回到 0/1、0%。
- 实际将喝水的周二从未打卡切换为已打卡，其他日期/习惯状态保持独立；退出并重新启动后该周二状态仍保留。
- 完整任务编辑器、可空类别、优先级、截止时间和固定保存入口；空标题禁用保存；最终草稿取消，没有写入真实记录。
- 时钟在运行过程中自动按分钟更新，始终使用 24 小时制。
- 三标签切换不调整窗口尺寸。
- 最终 Release 版本从设置菜单收起到胶囊，稳定保持收起，再点击可以展开。

实际验收发现并修复了菜单收起被菜单跟踪状态拦截的问题；同时防止主动收起后鼠标仍在胶囊区域导致立即重新展开。

## 数据保留与备份

首次新界面启动前，通过 SQLite backup API 对原有数据库生成一致性备份，并复制原偏好文件。备份准确位置记录在当前工作区 `work/ui-refactor/backup-location.txt`。

任务库沿用原路径和模型，仅增加可空 category 字段。打卡使用独立 `habits.store`，没有将打卡混入任务模型。旧 schema 迁移测试逐字段验证原任务内容；最终真实数据启动后又比对了备份与当前任务记录的原字段，检查通过，当前任务库 integrity_check 返回 ok。真实习惯库中没有隔离验收习惯。

迁移策略与备份说明见 [MIGRATION.md](MIGRATION.md)。

## 仍需实体环境验收的范围

没有重新进行外接显示器拔插、跨屏真实鼠标拖动、Space 与全屏组合的完整硬件验收。对应的位置算法、序列化和交互状态仍有自动化覆盖，原多屏位置实现保留。250ms/550ms 是实现与自动化验证的计时值，没有做物理鼠标毫秒级测量。

当前应用仅本机临时签名，未公证；语音、AI 和系统通知没有开发。

## 2026-10-25 应用名称调整

按用户要求停止输入问题排查，本次仅改名，没有修改输入与焦点逻辑。应用包、系统显示名称、胶囊文字、窗口标题、辅助功能名称、应用菜单与打开/退出菜单项均改为「干了吗」。工程/target/Swift 模块与可执行文件仍沿用 FocusDock；Bundle ID、数据目录和偏好域不变，不触发数据迁移。

- Swift Package Release 构建、临时签名与严格签名检查实际通过，日志 `Validation/rename-build.log`。
- 原 Xcode FocusDock scheme 的本机 arm64 Debug build 实际通过，日志 `Validation/rename-xcode-build.log`。
- 受限环境首次构建被宏插件/符号生成沙盒限制拦截，获准本机执行后两项构建均成功。
- 实际启动 `build/干了吗.app`，系统应用名与窗口名为「干了吗」，胶囊辅助功能名称为「干了吗，0 项待办」，应用菜单显示「打开干了吗 / 退出干了吗」。
- 旧的 `build/FocusDock.app` 已移到工作区 `work/app-name-backup/FocusDock.previous` 以免误开旧名称版本。
- 本次为显示名称调整，未新增测试或重跑业务测试；上一轮 19/19 结果仅对应上述 UI 重构验证。
