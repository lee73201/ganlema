import Foundation
import SwiftData
import FocusDockCore

// Exact stored fields of app 0.2.0 before adding optional reminder metadata.
enum PreviousSchema {
    @Model final class TodoItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var notes: String
        var createdAt: Date
        var dueDate: Date?
        var priorityRawValue: Int
        var isCompleted: Bool
        var completedAt: Date?
        var category: String? = nil
        init() {
            id = UUID(); title = "0.2 待办"; notes = "保留备注"; createdAt = .now
            dueDate = .now.addingTimeInterval(3600); priorityRawValue = 2
            isCompleted = true; completedAt = .now; category = "工作"
        }
    }
}
