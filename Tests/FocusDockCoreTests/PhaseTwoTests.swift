import Foundation
import Testing
import SwiftData
import FocusDockCore

private func cnCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}
private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let reference = instant("2026-10-25T01:00:00Z") // Sunday, 09:00 in Shanghai.

@Test func naturalLanguageExtractsChineseTimeAndTask() throws {
    let card = try #require(LocalTaskParser().parse("明天下午三点交报告", now: reference, calendar: cnCalendar()).first)
    #expect(card.draft.title == "交报告")
    #expect(card.draft.dueDate == instant("2026-10-26T07:00:00Z"))
    #expect(card.draft.reminderOffsets == [86400, 7200, 0])
    #expect(card.warnings.isEmpty)
}

@Test func multipleTasksKeepDatesAndExplicitReminderRequirements() throws {
    let cards = LocalTaskParser().parse("明天下午三点交报告，提前三十分钟提醒；后天上午十点开会，不要提醒", now: reference, calendar: cnCalendar())
    #expect(cards.count == 2)
    #expect(cards[0].draft.title == "交报告")
    #expect(cards[0].draft.reminderOffsets == [1800, 0])
    #expect(cards[1].draft.title == "开会")
    #expect(cards[1].draft.reminderOffsets.isEmpty)
    #expect(cards[1].draft.dueDate == instant("2026-10-27T02:00:00Z"))
}

@Test func multipleTaskClockCanInheritThePreviousExplicitDay() {
    let cards = LocalTaskParser().parse("明天下午三点交报告，然后晚上八点运动和后天上午九点开会", now: reference, calendar: cnCalendar())
    #expect(cards.count == 3)
    #expect(cards[1].draft.dueDate == instant("2026-10-26T12:00:00Z"))
    #expect(cards[2].draft.dueDate == instant("2026-10-27T01:00:00Z"))
}

@Test func calendarWeekAbsoluteDateAndRelativeDurationAreCorrect() {
    let parser = LocalTaskParser()
    #expect(parser.parse("下周一上午九点开会", now: reference, calendar: cnCalendar())[0].draft.dueDate == instant("2026-10-26T01:00:00Z"))
    #expect(parser.parse("2026年12月31日23:30交稿", now: reference, calendar: cnCalendar())[0].draft.dueDate == instant("2026-12-31T15:30:00Z"))
    #expect(parser.parse("两小时后吃药", now: reference, calendar: cnCalendar())[0].draft.dueDate == reference.addingTimeInterval(7200))
    #expect(parser.parse("今天下午三点半读书", now: reference, calendar: cnCalendar())[0].draft.dueDate == instant("2026-10-25T07:30:00Z"))
}

@Test func ambiguousMissingAndInvalidTimesRequireConfirmation() {
    let parser = LocalTaskParser()
    let noDate = parser.parse("买牛奶", now: reference, calendar: cnCalendar())[0]
    #expect(noDate.draft.title == "买牛奶" && noDate.draft.dueDate == nil)
    let dateOnly = parser.parse("明天交报告", now: reference, calendar: cnCalendar())[0]
    #expect(dateOnly.draft.dueDate == instant("2026-10-26T10:00:00Z"))
    #expect(!dateOnly.warnings.isEmpty)
    let invalid = parser.parse("2026年2月30日下午三点交报告", now: reference, calendar: cnCalendar())[0]
    #expect(invalid.draft.dueDate == nil && !invalid.warnings.isEmpty)
    #expect(parser.parse("明天25:90开会", now: reference, calendar: cnCalendar())[0].draft.dueDate == nil)
    #expect(!parser.parse("周末交报告", now: reference, calendar: cnCalendar())[0].warnings.isEmpty)
    #expect(parser.parse(" \n ", now: reference).isEmpty)
}

@Test func remindersAreFutureOnlyDeduplicatedAndStableAcrossEdits() {
    let id = UUID()
    let deadline = reference.addingTimeInterval(3600)
    let plan = ReminderPlan.make(taskID: id, title: "交报告", dueDate: deadline, offsets: [86400, 7200, 1800, 0, 0, -1, .nan, .infinity], now: reference)
    #expect(plan.count == 2)
    #expect(plan[0].fireDate == reference.addingTimeInterval(1800))
    #expect(plan[1].fireDate == deadline)
    let changed = ReminderPlan.make(taskID: id, title: "改名", dueDate: deadline.addingTimeInterval(600), offsets: [1800, 0], now: reference)
    #expect(changed.map(\.id) == plan.map(\.id))
    #expect(changed[0].fireDate != plan[0].fireDate)
    #expect(ReminderPlan.make(taskID: id, title: "过期", dueDate: reference, now: reference).isEmpty)
    #expect(ReminderPlan.make(taskID: id, title: "关闭", dueDate: deadline, offsets: [], now: reference).isEmpty)
}

@Test func urgencyHasBoundedMonotonicGrowthAndNoTaskCountDependency() {
    let thresholds: [(TimeInterval, DeadlineUrgency)] = [(90000,.normal),(86400,.day),(7200,.soon),(1800,.imminent),(0,.overdue),(-3600,.overdue)]
    for (seconds, expected) in thresholds {
        #expect(DeadlineUrgency.evaluate(dueDates: [reference.addingTimeInterval(seconds)], now: reference) == expected)
    }
    #expect(DeadlineUrgency.evaluate(dueDates: [], now: reference) == .normal)
    for level in DeadlineUrgency.allCases {
        #expect(level.panelSize.width <= 412 && level.panelSize.height <= 560)
        let frame = WindowPlacement().frame(size: level.panelSize, in: CGRect(x: -900, y: 0, width: 320, height: 480))
        #expect(CGRect(x: -900, y: 0, width: 320, height: 480).contains(frame))
    }
}

@Test @MainActor func confirmedBatchIsAtomicAndReminderChoicesPersist() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Capture-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("tasks.store")
    try autoreleasepool {
        let repo = try TaskRepository(storeURL: url)
        #expect(throws: TaskRepositoryError.self) { try repo.addBatch([TaskDraft(title:"有效"), TaskDraft(title:" ")]) }
        #expect(repo.items.isEmpty)
        let cards = LocalTaskParser().parse("明天下午三点交报告，不要提醒；买牛奶", now: reference, calendar: cnCalendar())
        try repo.addBatch(cards.map(\.draft))
        #expect(repo.items.count == 2)
        #expect(repo.items.first(where: { $0.title == "交报告" })?.reminderOffsets == [])
    }
    let repo = try TaskRepository(storeURL: url)
    #expect(repo.items.count == 2)
    let task = try #require(repo.items.first(where: { $0.title == "交报告" }))
    #expect(task.reminderOffsets == [])
    var draft = TaskDraft(item: task); draft.reminderOffsets = [600, 0]
    try repo.update(task, with: draft)
    #expect(task.reminderOffsets == [600, 0])
}

@Test @MainActor func habitCompletionProjectionTracksDatesUndoAndReopening() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("History-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("habits.store")
    let calendar = cnCalendar()
    try autoreleasepool {
        let repo = try HabitRepository(storeURL: url)
        let habit = try repo.add(name: "阅读")
        try repo.toggle(habit, on: reference, calendar: calendar)
        try repo.toggle(habit, on: reference.addingTimeInterval(-86400), calendar: calendar)
    }
    let repo = try HabitRepository(storeURL: url)
    let task = TodoItem(title: "已完成待办"); task.isCompleted = true; task.completedAt = reference
    var entries = CompletionEntry.all(tasks: [task], habits: repo.habits, records: repo.checkIns, calendar: calendar)
    #expect(entries.count == 3 && Set(entries.map(\.id)).count == 3)
    #expect(entries.first?.id == "task/\(task.id)")
    let record = try #require(repo.checkIns.first { $0.dayKey == "2026-10-25" })
    try repo.removeCheckIn(record)
    entries = CompletionEntry.all(tasks: [task], habits: repo.habits, records: repo.checkIns, calendar: calendar)
    #expect(entries.count == 2 && repo.habits.count == 1)
    #expect(!repo.isChecked(repo.habits[0], on: reference, calendar: calendar))
    #expect(repo.isChecked(repo.habits[0], on: reference.addingTimeInterval(-86400), calendar: calendar))
    #expect(HabitCalendar.date(for: "2026-02-30", calendar: calendar) == nil)
}

@Test @MainActor func previousVersionStoreAddsDefaultRemindersWithoutLosingFields() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PreviousMigration-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("tasks.store")
    let (id, due, completion) = try autoreleasepool {
        let schema = Schema([PreviousSchema.TodoItem.self])
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let item = PreviousSchema.TodoItem(); context.insert(item); try context.save()
        return (item.id, item.dueDate, item.completedAt)
    }
    let repo = try TaskRepository(storeURL: url)
    let item = try #require(repo.items.first)
    #expect(repo.items.count == 1 && item.id == id && item.category == "工作")
    #expect(item.title == "0.2 待办" && item.notes == "保留备注" && item.priority == .high)
    #expect(item.isCompleted && item.dueDate == due && item.completedAt == completion)
    #expect(item.reminderOffsets == [86400, 7200, 0])
}

@Test func reminderQueueCancelsCompletedRequestsAndOnlyReschedulesChangedDates() {
    let id = UUID()
    let plan = ReminderPlan.make(taskID: id, title: "任务", dueDate: reference.addingTimeInterval(90000), now: reference)
    let pending = plan.map { PendingReminderSnapshot(id: $0.id, title: $0.title, body: "截止", fireDate: $0.fireDate) }
        + [PendingReminderSnapshot(id: "another-app", title: "别的通知", body: "", fireDate: reference)]
    let unchanged = ReminderQueueChange(desired: plan, pending: pending, body: { _ in "截止" })
    #expect(unchanged.removeIDs.isEmpty && unchanged.upsert.isEmpty)
    let completed = ReminderQueueChange(desired: [], pending: pending, body: { _ in "截止" })
    #expect(Set(completed.removeIDs) == Set(plan.map(\.id)))
    #expect(!completed.removeIDs.contains("another-app"))
    let edited = ReminderPlan.make(taskID: id, title: "任务", dueDate: reference.addingTimeInterval(91000), now: reference)
    let delta = ReminderQueueChange(desired: edited, pending: pending, body: { _ in "截止" })
    #expect(delta.removeIDs.isEmpty && delta.upsert.count == edited.count)
}

@Test func ordinaryTaskWordsAreNotMistakenForTimeExpressions() {
    let parser = LocalTaskParser()
    let plain = parser.parse("整理说明文档和设计要点", now: reference, calendar: cnCalendar())[0]
    #expect(plain.draft.dueDate == nil && plain.warnings.isEmpty)
    let prefixed = parser.parse("提醒我明天下午三点交报告", now: reference, calendar: cnCalendar())[0]
    #expect(prefixed.draft.title == "交报告" && prefixed.warnings.isEmpty)
    #expect(parser.parse("一百二十分钟后休息", now: reference, calendar: cnCalendar())[0].draft.dueDate == reference.addingTimeInterval(7200))
}
