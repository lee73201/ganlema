import Foundation
import SwiftData
import Testing
import FocusDockCore

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}
private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

@Test @MainActor func checkInsAreIndependentByHabitAndCivilDay() throws {
    let repo = try HabitRepository(inMemory: true)
    let water = try repo.add(name: "  喝水  ")
    let reading = try repo.add(name: "阅读")
    let monday = date("2026-10-19T08:00:00Z")
    let tuesday = date("2026-10-20T08:00:00Z")
    let calendar = utcCalendar()
    #expect(water.name == "喝水")
    try repo.toggle(water, on: monday, calendar: calendar)
    try repo.toggle(water, on: tuesday, calendar: calendar)
    #expect(repo.isChecked(water, on: monday, calendar: calendar))
    #expect(repo.isChecked(water, on: tuesday, calendar: calendar))
    #expect(!repo.isChecked(reading, on: monday, calendar: calendar))
    try repo.toggle(water, on: monday.addingTimeInterval(3600), calendar: calendar)
    #expect(!repo.isChecked(water, on: monday, calendar: calendar))
    #expect(repo.isChecked(water, on: tuesday, calendar: calendar))
    #expect(repo.checkIns.count == 1)
}

@Test @MainActor func habitCRUDAndHistorySurviveReopening() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FocusDockHabit-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appendingPathComponent("habits.store")
    let firstDay = date("2026-10-18T12:00:00Z")
    let secondDay = date("2026-10-19T12:00:00Z")
    let calendar = utcCalendar()
    let id = try autoreleasepool {
        let repo = try HabitRepository(storeURL: store)
        let habit = try repo.add(name: "阅读")
        try repo.toggle(habit, on: firstDay, calendar: calendar)
        try repo.toggle(habit, on: secondDay, calendar: calendar)
        try repo.rename(habit, name: "每天阅读")
        return habit.id
    }
    try autoreleasepool {
        let repo = try HabitRepository(storeURL: store)
        let habit = try #require(repo.habits.first)
        #expect(habit.id == id && habit.name == "每天阅读")
        #expect(repo.checkIns.count == 2)
        #expect(repo.streak(for: habit, asOf: secondDay, calendar: calendar) == 2)
        try repo.toggle(habit, on: firstDay, calendar: calendar)
    }
    try autoreleasepool {
        let repo = try HabitRepository(storeURL: store)
        let habit = try #require(repo.habits.first)
        #expect(!repo.isChecked(habit, on: firstDay, calendar: calendar))
        #expect(repo.isChecked(habit, on: secondDay, calendar: calendar))
        try repo.delete(habit)
    }
    let repo = try HabitRepository(storeURL: store)
    #expect(repo.habits.isEmpty && repo.checkIns.isEmpty)
}

@Test @MainActor func habitNamesRejectBlankEditsWithoutLosingHistory() throws {
    let repo = try HabitRepository(inMemory: true)
    #expect(throws: HabitRepositoryError.self) { try repo.add(name: " \n ") }
    let habit = try repo.add(name: "运动")
    try repo.toggle(habit, on: .now)
    #expect(throws: HabitRepositoryError.self) { try repo.rename(habit, name: "\n") }
    #expect(habit.name == "运动" && repo.checkIns.count == 1)
}

@Test func mondayWeeksSurviveYearBoundaryAndDST() {
    let calendar = utcCalendar()
    let days = HabitCalendar.week(containing: date("2026-01-01T12:00:00Z"), calendar: calendar)
    #expect(days.count == 7)
    #expect(HabitCalendar.key(for: days[0], calendar: calendar) == "2025-12-29")
    #expect(HabitCalendar.key(for: days[6], calendar: calendar) == "2026-01-04")
    #expect(calendar.component(.weekday, from: days[0]) == 2)
    var pacific = calendar
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let dstWeek = HabitCalendar.week(containing: date("2026-03-08T12:00:00Z"), calendar: pacific)
    #expect(Set(dstWeek.map { HabitCalendar.key(for: $0, calendar: pacific) }).count == 7)
    #expect(HabitCalendar.key(for: dstWeek.last!, calendar: pacific) == "2026-03-08")
}

@Test func streakUsesHistoryGapsAndNeverCountsFuture() {
    let calendar = utcCalendar()
    let today = date("2026-10-25T12:00:00Z")
    let keys: Set<String> = ["2026-10-22", "2026-10-23", "2026-10-24", "2026-10-26"]
    #expect(HabitCalendar.streak(dayKeys: keys, asOf: today, calendar: calendar) == 3)
    #expect(HabitCalendar.streak(dayKeys: keys.union(["2026-10-25"]), asOf: today, calendar: calendar) == 4)
    #expect(HabitCalendar.streak(dayKeys: keys.subtracting(["2026-10-23"]), asOf: today, calendar: calendar) == 1)
    #expect(HabitCalendar.streak(dayKeys: ["2026-10-26"], asOf: today, calendar: calendar) == 0)
}

@Test @MainActor func categoriesPersistAndNormalizeWithoutChangingTaskIdentity() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FocusDockCategory-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appendingPathComponent("tasks.store")
    let id = try autoreleasepool {
        let repo = try TaskRepository(storeURL: store)
        return try repo.add(TaskDraft(title: "文档", category: "  工作  ")).id
    }
    let repo = try TaskRepository(storeURL: store)
    let item = try #require(repo.items.first)
    #expect(item.id == id && item.category == "工作")
    try repo.update(item, with: TaskDraft(title: "文档", category: "  "))
    #expect(item.id == id && item.category == nil)
}

@Test @MainActor func originalTaskStoreMigratesWithoutDataLoss() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FocusDockMigration-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("tasks.store")
    let deadline = date("2026-10-25T12:00:00Z")
    let id = try autoreleasepool {
        let schema = Schema([OriginalSchema.TodoItem.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let item = OriginalSchema.TodoItem(title: "旧版任务", notes: "必须保留", dueDate: deadline, priority: .high)
        item.isCompleted = true
        item.completedAt = deadline
        context.insert(item)
        try context.save()
        return item.id
    }
    let repo = try TaskRepository(storeURL: url)
    let item = try #require(repo.items.first)
    #expect(repo.items.count == 1 && item.id == id)
    #expect(item.title == "旧版任务" && item.notes == "必须保留")
    #expect(item.dueDate == deadline && item.completedAt == deadline && item.isCompleted)
    #expect(item.priority == .high && item.category == nil)
    var draft = TaskDraft(item: item)
    draft.category = "迁移后添加"
    try repo.update(item, with: draft)
    #expect(item.id == id && item.category == "迁移后添加")
}

@Test @MainActor func todaySummaryExcludesFutureTasksAndHasSafeEmptyProgress() {
    let today = date("2026-10-25T12:00:00Z")
    let tomorrow = date("2026-10-26T12:00:00Z")
    let yesterday = date("2026-10-24T12:00:00Z")
    let due = TodoItem(title: "今日到期", dueDate: today)
    due.createdAt = yesterday
    due.isCompleted = true
    due.completedAt = today
    let created = TodoItem(title: "今日新建")
    created.createdAt = today
    let later = TodoItem(title: "未来", dueDate: tomorrow)
    later.createdAt = today
    let summary = TaskDaySummary(items: [due, created, later], date: today, calendar: utcCalendar())
    #expect(summary.total == 2 && summary.completed == 1 && summary.percentage == 50)
    let empty = TaskDaySummary(items: [], date: today)
    #expect(empty.percentage == 0 && empty.fraction == 0)
}
