import Foundation
import Testing
import FocusDockCore

@Test func todayAgendaSeparatesOverdueFromTodayAndUsesTheClosestFutureDeadline() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10)))
    let yesterday = TodoItem(title: "昨日", dueDate: now.addingTimeInterval(-14 * 3600))
    let thisMorning = TodoItem(title: "早上", dueDate: now.addingTimeInterval(-3600))
    let noon = TodoItem(title: "中午", dueDate: now.addingTimeInterval(2 * 3600))
    let tomorrow = TodoItem(title: "明天", dueDate: now.addingTimeInterval(18 * 3600))
    let added = TodoItem(title: "今天记录"); added.createdAt = now
    let unscheduled = TodoItem(title: "早前记录"); unscheduled.createdAt = yesterday.dueDate!
    let completed = TodoItem(title: "已完成", dueDate: now.addingTimeInterval(-20))
    completed.isCompleted = true
    completed.completedAt = now

    let agenda = TodayAgenda(items: [tomorrow, yesterday, thisMorning, noon, added, unscheduled, completed], now: now, calendar: calendar)
    #expect(agenda.overdue.map(\.id) == [yesterday.id, thisMorning.id])
    #expect(agenda.dueToday.map(\.id) == [noon.id])
    #expect(agenda.addedToday.map(\.id) == [added.id])
    #expect(agenda.nextDeadline?.id == noon.id)
    #expect(agenda.progress.total == 4 && agenda.progress.completed == 1)
}

@Test func agendaMovesDeadlineIntoOverdueWhenTimeAdvances() throws {
    let start = Date(timeIntervalSince1970: 12_000)
    let task = TodoItem(title: "即将到期", dueDate: start.addingTimeInterval(30))
    let before = TodayAgenda(items: [task], now: start)
    let atDeadline = TodayAgenda(items: [task], now: start.addingTimeInterval(30))
    #expect(before.nextDeadline?.id == task.id && before.overdue.isEmpty)
    #expect(atDeadline.nextDeadline == nil && atDeadline.overdue.map(\.id) == [task.id])
    #expect(atDeadline.dueToday.isEmpty)
}
