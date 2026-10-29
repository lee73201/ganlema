import Foundation

/// Value snapshots survive deletion of the original SwiftData objects. No schema change.
public struct DeletedTaskSnapshot {
    public let id: UUID
    public let draft: TaskDraft
    public let createdAt: Date
    public let isCompleted: Bool
    public let completedAt: Date?
    public let priorityRawValue: Int
    public let reminderJSON: String?
    public init(_ item: TodoItem) {
        priorityRawValue = item.priorityRawValue
        id = item.id; draft = TaskDraft(item: item); createdAt = item.createdAt
        isCompleted = item.isCompleted; completedAt = item.completedAt; reminderJSON = item.reminderOffsetsJSON
    }
}
public struct DeletedCheckInSnapshot {
    public let habitID: UUID
    public let dayKey: String
    public init(_ record: HabitCheckIn) { habitID = record.habitID; dayKey = record.dayKey }
}
public struct DeletedHabitSnapshot {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let records: [DeletedCheckInSnapshot]
    public init(_ habit: Habit, records: [HabitCheckIn]) {
        id = habit.id; name = habit.name; createdAt = habit.createdAt
        self.records = records.filter { $0.habitID == habit.id }.map(DeletedCheckInSnapshot.init)
    }
}
public enum DeletionRestoreError: LocalizedError {
    case alreadyExists, missingHabit
    public var errorDescription: String? {
        switch self { case .alreadyExists: return "记录已经存在，未覆盖现有数据。"; case .missingHabit: return "该习惯已被删除，无法单独恢复打卡。请先撤销习惯删除。" }
    }
}
public enum FocusCountdown {
    public static func text(session: FocusSession, now: Date) -> String {
        let seconds = Int(ceil(session.remaining(at: now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
