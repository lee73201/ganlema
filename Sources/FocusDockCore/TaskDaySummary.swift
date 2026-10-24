import Foundation

public struct TaskDaySummary {
    public let total: Int
    public let completed: Int
    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    public var percentage: Int { Int((fraction * 100).rounded()) }
    public init(items: [TodoItem], date: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        let today = items.filter {
            ($0.dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? calendar.isDate($0.createdAt, inSameDayAs: date))
                || ($0.completedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false)
        }
        total = today.count
        completed = today.filter(\.isCompleted).count
    }
}
