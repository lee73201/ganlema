import Combine
import Foundation
import SwiftData

public enum TaskRepositoryError: LocalizedError {
    case emptyTitle
    public var errorDescription: String? { "请为待办填写标题。" }
}

@MainActor
public final class TaskRepository: ObservableObject {
    public let container: ModelContainer
    private let context: ModelContext
    @Published public private(set) var items: [TodoItem] = []

    public init(storeURL: URL? = nil, inMemory: Bool = false) throws {
        let schema = Schema([TodoItem.self])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url: URL
            if let storeURL { url = storeURL } else {
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
                    .appendingPathComponent("FocusDock", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                url = folder.appendingPathComponent("tasks.store")
            }
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        try reload()
    }

    @discardableResult
    public func add(_ draft: TaskDraft) throws -> TodoItem {
        let title = try validatedTitle(draft.title)
        let item = TodoItem(title: title, notes: draft.notes, dueDate: draft.dueDate, priority: draft.priority, category: normalizedCategory(draft.category))
        context.insert(item)
        try commit()
        return item
    }

    public func update(_ item: TodoItem, with draft: TaskDraft) throws {
        let title = try validatedTitle(draft.title)
        item.title = title
        item.notes = draft.notes
        item.dueDate = draft.dueDate
        item.priority = draft.priority
        item.category = normalizedCategory(draft.category)
        try commit()
    }

    public func toggleCompletion(_ item: TodoItem) throws {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? Date() : nil
        try commit()
    }

    public func delete(_ item: TodoItem) throws {
        context.delete(item)
        try commit()
    }

    private func validatedTitle(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskRepositoryError.emptyTitle }
        return trimmed
    }

    private func normalizedCategory(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func commit() throws {
        do { try context.save(); try reload() }
        catch { context.rollback(); try? reload(); throw error }
    }

    private func reload() throws {
        items = try context.fetch(FetchDescriptor<TodoItem>()).sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            if $0.priorityRawValue != $1.priorityRawValue { return $0.priorityRawValue > $1.priorityRawValue }
            if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            return $0.createdAt < $1.createdAt
        }
    }
}
