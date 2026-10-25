import Foundation

/// Wall-clock deadlines survive sleep/restarts. Independent of task records and completion.
public struct FocusSession: Codable, Equatable {
    public let taskID: UUID
    public let taskTitle: String
    public let duration: TimeInterval
    public private(set) var endsAt: Date
    public private(set) var pausedRemaining: TimeInterval?
    public init(taskID: UUID, taskTitle: String, minutes: Int, now: Date = .now) {
        self.taskID = taskID; self.taskTitle = taskTitle
        duration = TimeInterval(minutes == 50 ? 50 * 60 : 25 * 60)
        endsAt = now.addingTimeInterval(duration)
    }
    public func remaining(at now: Date) -> TimeInterval { max(0, pausedRemaining ?? endsAt.timeIntervalSince(now)) }
    public func isFinished(at now: Date) -> Bool { pausedRemaining == nil && remaining(at: now) == 0 }
    public mutating func pause(at now: Date) { let value = remaining(at: now); if pausedRemaining == nil && value > 0 { pausedRemaining = value } }
    public mutating func resume(at now: Date) { if let remaining = pausedRemaining { endsAt = now.addingTimeInterval(remaining); pausedRemaining = nil } }
}
