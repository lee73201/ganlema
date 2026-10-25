import Foundation

/// A read projection. Habits remain in their independent store and are never copied to TodoItem.
public struct CompletionEntry: Identifiable {
    public enum Source { case task(TodoItem), habit(Habit, HabitCheckIn) }
    public let id: String
    public let date: Date
    public let source: Source
    public static func all(tasks: [TodoItem], habits: [Habit], records: [HabitCheckIn], calendar: Calendar = .autoupdatingCurrent) -> [CompletionEntry] {
        var entries = tasks.filter(\.isCompleted).map {
            CompletionEntry(id: "task/\($0.id)", date: $0.completedAt ?? $0.createdAt, source: .task($0))
        }
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        for record in records {
            guard let habit = byID[record.habitID], let date = HabitCalendar.date(for: record.dayKey, calendar: calendar) else { continue }
            entries.append(CompletionEntry(id: "habit/\(record.key)", date: date, source: .habit(habit, record)))
        }
        return entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
