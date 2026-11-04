import Foundation

/// Estimates are optional and keyed by task ID, separate from the task database.
public struct TaskEstimates {
    public static let choices = [5, 15, 25, 50, 90]
    private static let key = "taskEstimates.v1"
    private var minutes: [String: Int]

    public init(defaults: UserDefaults, existingIDs: Set<UUID>) {
        let keys = Set(existingIDs.map(\.uuidString))
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        minutes = stored.filter { keys.contains($0.key) && Self.choices.contains($0.value) }
        if stored != minutes { save(to: defaults) }
    }

    public subscript(id: UUID) -> Int? { minutes[id.uuidString] }

    public mutating func set(_ estimate: Int?, for id: UUID, defaults: UserDefaults) {
        if let estimate, !Self.choices.contains(estimate) { return }
        minutes[id.uuidString] = estimate
        save(to: defaults)
    }

    private func save(to defaults: UserDefaults) { defaults.set(minutes, forKey: Self.key) }
}

public struct TaskRecommendation {
    public let task: TodoItem
    public let estimatedMinutes: Int?
    public let reason: String

    public static func choose(from items: [TodoItem], estimates: TaskEstimates, availableMinutes: Int, now: Date = .now) -> Self? {
        guard availableMinutes > 0 else { return nil }
        let pending = items.filter { !$0.isCompleted }
        let fitting = pending.filter { estimates[$0.id].map { $0 <= availableMinutes } ?? false }
        // If no estimate fits, suggest a first step on an unestimated task.
        let candidates = fitting.isEmpty ? pending.filter { estimates[$0.id] == nil } : fitting
        guard let item = candidates.min(by: { precedes($0, $1, now: now) }) else { return nil }
        return Self(task: item, estimatedMinutes: estimates[item.id], reason: reason(for: item, now: now))
    }

    private static func urgency(of item: TodoItem, now: Date) -> DeadlineUrgency {
        DeadlineUrgency.evaluate(dueDates: item.dueDate.map { [$0] } ?? [], now: now)
    }

    private static func precedes(_ lhs: TodoItem, _ rhs: TodoItem, now: Date) -> Bool {
        let leftUrgency = urgency(of: lhs, now: now), rightUrgency = urgency(of: rhs, now: now)
        if leftUrgency != rightUrgency { return leftUrgency.rawValue > rightUrgency.rawValue }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        let leftDue = lhs.dueDate ?? .distantFuture, rightDue = rhs.dueDate ?? .distantFuture
        if leftDue != rightDue { return leftDue < rightDue }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func reason(for item: TodoItem, now: Date) -> String {
        let urgency = urgency(of: item, now: now)
        if urgency == .overdue { return "已到截止时间" }
        if urgency != .normal { return urgency.title }
        if item.priority == .high { return "高优先级" }
        return item.dueDate == nil ? "可以现在推进" : "有截止时间"
    }
}
