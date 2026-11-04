import Foundation

public struct TodayAgenda {
    public let progress: TaskDaySummary
    public let overdue: [TodoItem]
    public let dueToday: [TodoItem]
    public let addedToday: [TodoItem]
    public let nextDeadline: TodoItem?

    public init(items: [TodoItem], now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        progress = TaskDaySummary(items: items, date: now, calendar: calendar)
        let pending = items.filter { !$0.isCompleted }
        let dated = pending.compactMap { item in item.dueDate.map { (item: item, date: $0) } }
        overdue = dated.filter { $0.date <= now }.map(\.item)
        let upcoming = dated.filter { $0.date > now }
        dueToday = upcoming.filter { calendar.isDate($0.date, inSameDayAs: now) }.map(\.item)
        addedToday = pending.filter { $0.dueDate == nil && calendar.isDate($0.createdAt, inSameDayAs: now) }
        nextDeadline = upcoming.min { $0.date < $1.date }?.item
    }
}
