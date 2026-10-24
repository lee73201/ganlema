import Foundation

// Phase two contracts only. No microphone, network, or notification permissions are requested.
public protocol SpeechService {
    func transcribe() async throws -> String
    func stop() async
}

public struct TaskSuggestion: Sendable {
    public var title: String
    public var detail: String
    public init(title: String, detail: String) { self.title = title; self.detail = detail }
}

public protocol AIService {
    func suggestions(for taskTitle: String, dueDate: Date?) async throws -> [TaskSuggestion]
}

public protocol ReminderService {
    func schedule(taskID: UUID, title: String, dueDate: Date) async throws
    func cancel(taskID: UUID) async
}
