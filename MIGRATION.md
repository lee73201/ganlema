# 0.2 数据兼容与备份

任务数据库继续位于原来的 `tasks.store`。原有字段没有改名或删除，唯一增加的存储字段是 `category: String? = nil`；原有任务的类别保持为空。SwiftData 负责这项可空属性的轻量迁移。

测试使用重构前的字段定义创建旧结构数据库，然后用当前 TaskRepository 重新打开，逐项核对 UUID、标题、备注、截止时间、优先级、完成状态和完成时间，并验证迁移后能写入类别。打卡采用另外的 `habits.store`，没有把打卡历史混入任务表。

本轮在第一次新应用启动前，通过 SQLite backup API 对已有 `.store` 生成一致性副本，备份同时覆盖当时已经提交到 WAL 的内容。备份保存在当前工作区的 `work/ui-refactor/user-backup-<UUID>/`，准确路径记录在 `work/ui-refactor/backup-location.txt`；包含偏好文件副本及不含任务正文的备份清单。备份没有写入公开服务或演示数据库。

恢复时应先退出 FocusDock，另行备份当前数据，再用需要恢复的数据库副本替换对应 store；不要在应用运行时直接覆盖 SQLite 文件。SQLite 的 `-wal`、`-shm` 属于对应数据库，不能混用不同时间点的辅助文件。本次一致性备份本身已将已提交数据合并到备份 store，不依赖原 WAL 文件。

应用在数据打开或迁移失败时报告错误并退出，不会自动清空、删除数据库，也没有以空数据覆盖旧数据的容错分支。

## 0.3 提醒与完成记录

`TodoItem.reminderOffsetsJSON: String? = nil` 是可空附加字段。nil（旧记录）按 24 小时、2 小时、到期解释；明确的空数组表示不提醒。用户编辑/确认后保存规范化 JSON。0.1 原 schema 和 0.2（含 category）schema 均通过建立旧版磁盘库再重开的迁移测试，字段及 UUID 保留。

Habit 与 HabitCheckIn schema 没有改动。「已完成」只是两套数据的只读合并投影，删除某次打卡直接删除对应 HabitCheckIn，不向 tasks.store 复制或移入记录；跨周历史保持原日期，旧数据不伪造完成时刻。

本轮首次运行新 schema 前，使用 SQLite backup API 将真实库备份到本机 `work/phase2/user-backup-2026-10-25`，包含 WAL 中已提交内容；不上传 GitHub。旧应用源码/可执行应用备份已单独上传仓库，不含真实数据库。不要在新库上直接运行旧应用尝试反向迁移，应从独立数据库备份恢复。
