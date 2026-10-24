import Foundation
import SwiftData
import FocusDockCore

// Exact pre-refactor stored fields, kept to verify additive schema compatibility.
enum OriginalSchema {
@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var createdAt: Date
    var dueDate: Date?
    var priorityRawValue: Int
    var isCompleted: Bool
    var completedAt: Date?

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }

    init(title: String, notes: String = "", dueDate: Date? = nil, priority: TaskPriority = .normal) {
        id = UUID()
        self.title = title
        self.notes = notes
        createdAt = Date()
        self.dueDate = dueDate
        priorityRawValue = priority.rawValue
        isCompleted = false
        completedAt = nil
    }
}

}
