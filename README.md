# 干了吗（FocusDock）0.2

原生 macOS 悬浮待办与打卡工具，沿用现有 NSPanel、SwiftUI 和 SwiftData 工程。最低系统 macOS 14，开发需要带 SwiftData 编译插件的完整 Xcode。

应用显示名称为「干了吗」。工程、Bundle ID 和 `Application Support/FocusDock` 数据路径保留原值，原有任务、打卡与偏好无需迁移。

## 使用

打开 `build/干了吗.app`。悬停胶囊约 250ms 展开，移开约 550ms 后收起；点击胶囊锁定展开，图钉按钮解锁。按住胶囊或顶部时钟区域拖动。设置菜单可收起、找回或重置位置；Escape 取消编辑或收起面板。主动收起后，鼠标需先移出才能再次悬停展开，直接点击仍可展开。

主面板固定为 368×506pt，使用 AppKit `NSVisualEffectView` 的 `.popover` 材质和 `.behindWindow` 混合方式，保留桌面背景模糊；透明度与材质外观遵循系统设置。时钟为 24 小时制，日期、星期自动刷新。

顶部时间、今日完成进度、待办/已完成/打卡标签及底部入口固定，列表单独滚动，使用原生覆盖式细滚动条。标签切换不会改变窗口尺寸。主色为系统中性色，强调色为低饱和鼠尾草绿，明暗主题从齿轮或菜单栏选择。

- 待办：底部输入标题并按回车快速添加；输入为空时点箭头进入完整编辑器。点击任务标题编辑备注、类别、截止时间、优先级；圆圈完成，右侧垃圾桶删除。临近截止时间仅强调小圆点和文字。
- 已完成：显示完成时间，勾选圆圈可恢复待办，仍可编辑或删除。
- 打卡：底部输入习惯名称，按回车添加；点击名称重命名。周一至周日分别切换，左右箭头浏览历史或未来周，名称右侧删除习惯。删除习惯同时删除其历史记录。
- 连续天数：从今天已打卡的记录开始向前计算；今天未打卡时从昨天开始。遇到断档停止，不计未来记录；不会填入假连续天数。
- 今日进度：统计今日到期、今日新建且无截止时间，以及今日完成的任务。空列表显示 0/0、0%。

麦克风入口保留为明确禁用的占位按钮，暂不申请麦克风权限，不宣称已有语音识别。AI、系统通知、云同步、开机启动仍不在当前版本范围内。

## 本地数据和兼容性

正常启动继续使用原位置：

- `~/Library/Application Support/FocusDock/tasks.store`：原有任务，新增可空类别字段，由 SwiftData 轻量迁移。
- `~/Library/Application Support/FocusDock/habits.store`：独立的 `Habit` 和 `HabitCheckIn` 模型，保存所有历史日期的打卡状态。
- `local.focusdock.app` UserDefaults：外观、显示器 UUID 及各屏幕归一化位置。

本次升级已在新界面启动前对原数据库作一致性 SQLite 备份。旧结构迁移测试验证任务 ID、标题、备注、日期、优先级、完成状态仍被保留。数据库打开失败会显示错误并退出，不会静默删除或重置数据。备份和迁移细节见 [MIGRATION.md](MIGRATION.md)。

## 构建与测试

```sh
bash scripts/doctor.sh
bash scripts/test.sh
bash scripts/build-app.sh
open build/干了吗.app
```

默认构建 Release，也可传 `debug`。产物使用本机临时签名，未公证。脚本优先使用 `/Applications/Xcode.app`，或遵循显式 `DEVELOPER_DIR`；不修改系统级开发工具选择。缓存可用 `FOCUSDOCK_BUILD_ROOT` 指定，嵌套自动化沙箱中可设置 `FOCUSDOCK_SWIFTPM_NO_SANDBOX=1`。

Xcode 打开原有 `FocusDock.xcodeproj`，选择 FocusDock scheme 进行 Run/Test。新增源文件后运行 `python3 scripts/generate_xcodeproj.py` 同步文件引用。

## 架构和隔离验收

UI 位于 `Sources/FocusDockApp/UI/`；`PanelWindowController` 负责窗口、悬停、拖动、焦点和位置；`TaskRepository` 与 `HabitRepository` 分别负责两套数据；`HabitCalendar` 按本地自然日处理星期和连续记录，避免用固定 24 小时推算夏令时日期。

`FocusDockQAFixtures` 是独立的开发验收工具，不会链接进应用，也不会在普通启动时生成示例数据。`FOCUSDOCK_DATA_DIRECTORY` 和 `FOCUSDOCK_PREFERENCES_SUITE` 仅供明确指定隔离验收路径与偏好域；普通启动不设置它们，继续打开真实数据。本轮长任务、多任务、空列表和打卡验收均与真实待办分开。

实际构建、测试和运行记录见 [VALIDATION.md](VALIDATION.md)。
