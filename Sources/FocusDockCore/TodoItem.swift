import Foundation
import SwiftData

public enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0, normal = 1, high = 2
    public var id: Int { rawValue }
    public var title: String {
        switch self { case .low: return "低"; case .normal: return "普通"; case .high: return "高" }
    }
}

@Model
public final class TodoItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var notes: String
    public var createdAt: Date
    public var dueDate: Date?
    public var priorityRawValue: Int
    public var isCompleted: Bool
    public var completedAt: Date?
    // Optional additive field: existing stores migrate without inventing a category.
    public var category: String? = nil
    public var reminderOffsetsJSON: String? = nil

    public var reminderOffsets: [TimeInterval] {
        get {
            guard let raw = reminderOffsetsJSON?.data(using: .utf8), let values = try? JSONDecoder().decode([Double].self, from: raw) else { return ReminderPlan.defaultOffsets }
            return ReminderPlan.normalized(values)
        }
        set { reminderOffsetsJSON = (try? JSONEncoder().encode(ReminderPlan.normalized(newValue))).flatMap { String(data: $0, encoding: .utf8) } }
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    public init(title: String, notes: String = "", dueDate: Date? = nil, priority: TaskPriority = .normal, category: String? = nil) {
        id = UUID()
        self.title = title
        self.notes = notes
        createdAt = Date()
        self.dueDate = dueDate
        priorityRawValue = priority.rawValue
        isCompleted = false
        completedAt = nil
        self.category = category
    }
}

public struct TaskDraft {
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var priority: TaskPriority
    public var category: String?
    public var reminderOffsets: [TimeInterval]

    public init(title: String = "", notes: String = "", dueDate: Date? = nil, priority: TaskPriority = .normal, category: String? = nil, reminderOffsets: [TimeInterval] = ReminderPlan.defaultOffsets) {
        self.reminderOffsets = ReminderPlan.normalized(reminderOffsets)
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.category = category
    }

    public init(item: TodoItem) {
        self.init(title: item.title, notes: item.notes, dueDate: item.dueDate, priority: item.priority, category: item.category, reminderOffsets: item.reminderOffsets)
    }
}
