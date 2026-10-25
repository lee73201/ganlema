import Foundation

// Native services request permissions only in response to user actions.
@MainActor public protocol SpeechService: AnyObject {
    func start() async throws
    func finish()
    func cancel()
}

public struct TaskSuggestion: Sendable {
    public var title: String
    public var detail: String
    public init(title: String, detail: String) { self.title = title; self.detail = detail }
}

public protocol AIService {
    func suggestions(for taskTitle: String, dueDate: Date?) async throws -> [TaskSuggestion]
}

@MainActor public protocol ReminderService: AnyObject {
    func refreshAuthorization() async
    func enable() async
    func update(items: [TodoItem])
}
