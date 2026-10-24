# FocusDock 开发指令

这是 macOS 原生个人待办工具，最低系统为 macOS 14。使用 SwiftUI 展示界面、AppKit NSPanel 管理桌面悬浮窗、SwiftData 本地持久化，不使用网页容器。

## 当前范围：第一阶段及主面板 UI/UX 重构

- 主面板约 368×506pt；使用真正的 NSVisualEffectView behindWindow 毛玻璃，保留悬浮胶囊交互。
- 固定时钟/日期、今日完成进度、待办/已完成/打卡三标签、底部添加入口；列表独立滚动。
- 打卡使用独立 Habit/HabitCheckIn 模型和本地数据库，按周一至周日独立切换，连续天数根据真实记录计算。
- 保留任务数据；可空类别字段进行轻量迁移，并验证原始 schema 兼容性。真实数据在首次新版本启动前备份。

- 桌面悬浮胶囊；悬停约 250ms 展开，离开 550ms 后收起；重新进入时取消收起。
- 点击胶囊锁定展开；展开后的图钉按钮切换锁定；编辑和拖动时不能自动收起。
- 胶囊或展开窗标题区可拖动；按显示器 UUID 保存位置，使用归一化坐标适应分辨率变化；窗口限制在可见区域；显示器移除时恢复到可用屏幕。
- 待办新建、查看、编辑、删除、完成与取消完成；标题、备注、可选截止时间、优先级；SwiftData 写入本机，重启恢复。
- 菜单栏入口、找回窗口、重置位置、退出；跟随系统、浅色、深色主题。
- 分离 UI、WindowController、TaskRepository；SpeechService、AIService、ReminderService 仅定义扩展协议。

## 暂不实施

语音识别、AI 建议、系统通知、云同步、账号、自动启动、外部服务调用和权限申请均不在阶段一范围内。截止时间仅在界面中显示，逾期用醒目颜色提示，不能宣称已支持系统通知。

## 验证和交付

先检查本地环境；实际构建并执行测试。优先运行 `bash scripts/test.sh` 和 `bash scripts/build-app.sh`。有完整 Xcode 时也验证共享 FocusDock scheme。只能报告实际执行得到的结果，Xcode 不可用时明确区分 Swift 工具链构建与 Xcode 构建。

持续维护 README.md 和 VALIDATION.md。新建 Swift 文件后运行 `python3 scripts/generate_xcodeproj.py` 同步 Xcode 文件引用。不要静默丢弃数据库错误、清空用户数据或插入演示待办。
