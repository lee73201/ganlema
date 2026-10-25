import Foundation
import CoreGraphics

public enum DeadlineUrgency: Int, CaseIterable {
    case normal, day, soon, imminent, overdue
    public static func evaluate(dueDates: [Date], now: Date = .now) -> Self {
        guard let next = dueDates.min() else { return .normal }
        let remaining = next.timeIntervalSince(now)
        if remaining <= 0 { return .overdue }
        if remaining <= 30 * 60 { return .imminent }
        if remaining <= 2 * 3600 { return .soon }
        if remaining <= 24 * 3600 { return .day }
        return .normal
    }
    public var capsuleSize: CGSize {
        switch self {
        case .normal: return CGSize(width: 176, height: 50)
        case .day: return CGSize(width: 188, height: 54)
        case .soon: return CGSize(width: 204, height: 58)
        case .imminent, .overdue: return CGSize(width: 220, height: 62)
        }
    }
    public var panelSize: CGSize {
        switch self {
        case .normal: return CGSize(width: 368, height: 506)
        case .day: return CGSize(width: 380, height: 520)
        case .soon: return CGSize(width: 396, height: 540)
        case .imminent, .overdue: return CGSize(width: 412, height: 560)
        }
    }
    public var title: String {
        switch self {
        case .normal: return ""
        case .day: return "24 小时内到期"
        case .soon: return "2 小时内到期"
        case .imminent: return "30 分钟内到期"
        case .overdue: return "有待办已逾期"
        }
    }
}

public struct PlannedReminder: Identifiable, Equatable {
    public var id: String
    public var taskID: UUID
    public var title: String
    public var dueDate: Date
    public var fireDate: Date
    public var offset: TimeInterval
}

public enum ReminderPlan {
    public static let defaultOffsets: [TimeInterval] = [86400, 7200, 0]
    public static func normalized(_ offsets: [TimeInterval]) -> [TimeInterval] {
        Array(Set(offsets.filter { $0.isFinite && $0 >= 0 && $0 <= 366 * 86400 })).sorted(by: >)
    }
    public static func make(taskID: UUID, title: String, dueDate: Date, offsets: [TimeInterval] = defaultOffsets, now: Date = .now) -> [PlannedReminder] {
        normalized(offsets).compactMap { offset in
            let fire = dueDate.addingTimeInterval(-offset)
            guard fire > now else { return nil }
            return PlannedReminder(id: "ganlema.\(taskID.uuidString).\(offset)", taskID: taskID, title: title, dueDate: dueDate, fireDate: fire, offset: offset)
        }
    }
    public static func label(_ offset: TimeInterval) -> String {
        if offset == 0 { return "到期" }
        if offset.truncatingRemainder(dividingBy: 86400) == 0 { return "提前 \(Int(offset / 86400)) 天" }
        if offset.truncatingRemainder(dividingBy: 3600) == 0 { return "提前 \(Int(offset / 3600)) 小时" }
        return "提前 \(Int(offset / 60)) 分钟"
    }
}

public struct PendingReminderSnapshot {
    public var id: String
    public var title: String
    public var body: String
    public var fireDate: Date?
    public init(id: String, title: String, body: String, fireDate: Date?) {
        self.id = id; self.title = title; self.body = body; self.fireDate = fireDate
    }
}

/// Reconcile only this app's requests; edited deadlines replace stable IDs and completed tasks cancel.
public struct ReminderQueueChange {
    public let removeIDs: [String]
    public let upsert: [PlannedReminder]
    public init(desired: [PlannedReminder], pending: [PendingReminderSnapshot], body: (PlannedReminder) -> String) {
        let ids = Set(desired.map(\.id))
        removeIDs = pending.filter { $0.id.hasPrefix("ganlema.") && !ids.contains($0.id) }.map(\.id)
        upsert = desired.filter { reminder in
            guard let old = pending.first(where: { $0.id == reminder.id }), let fire = old.fireDate else { return true }
            return old.title != reminder.title || old.body != body(reminder) || abs(fire.timeIntervalSince(reminder.fireDate)) >= 1
        }
    }
}
