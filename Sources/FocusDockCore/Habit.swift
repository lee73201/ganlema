import Foundation
import SwiftData

@Model
public final class Habit {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public init(name: String) { id = UUID(); self.name = name; createdAt = Date() }
}

@Model
public final class HabitCheckIn {
    @Attribute(.unique) public var key: String
    public var habitID: UUID
    public var dayKey: String
    public init(habitID: UUID, dayKey: String) {
        self.habitID = habitID
        self.dayKey = dayKey
        key = "\(habitID.uuidString)/\(dayKey)"
    }
}

public enum HabitCalendar {
    /// Use local civil dates, not 24-hour intervals, so DST does not duplicate or skip a day.
    public static func calendar(_ source: Calendar = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.timeZone
        calendar.firstWeekday = 2
        return calendar
    }
    public static func key(for date: Date, calendar source: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar(source).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func week(containing date: Date, calendar source: Calendar = .autoupdatingCurrent) -> [Date] {
        let calendar = calendar(source)
        let offset = (calendar.component(.weekday, from: date) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date))!
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
    public static func streak(dayKeys: Set<String>, asOf date: Date, calendar source: Calendar = .autoupdatingCurrent) -> Int {
        let calendar = calendar(source)
        var day = calendar.startOfDay(for: date)
        if !dayKeys.contains(key(for: day, calendar: calendar)) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while dayKeys.contains(key(for: day, calendar: calendar)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
