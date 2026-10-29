import Combine
import Foundation
import SwiftData

public enum HabitRepositoryError: LocalizedError {
    case emptyName
    public var errorDescription: String? { "请为打卡习惯填写名称。" }
}

@MainActor
public final class HabitRepository: ObservableObject {
    private let container: ModelContainer
    private let context: ModelContext
    @Published public private(set) var habits: [Habit] = []
    @Published public private(set) var checkIns: [HabitCheckIn] = []

    public init(storeURL: URL? = nil, inMemory: Bool = false) throws {
        let schema = Schema([Habit.self, HabitCheckIn.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true).appendingPathComponent("FocusDock", isDirectory: true)
            let url = storeURL ?? folder.appendingPathComponent("habits.store")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        context.autosaveEnabled = false
        try reload()
    }
    @discardableResult public func add(name: String) throws -> Habit {
        let habit = Habit(name: try validated(name))
        context.insert(habit)
        try commit()
        return habit
    }
    public func rename(_ habit: Habit, name: String) throws {
        habit.name = try validated(name)
        try commit()
    }
    public func delete(_ habit: Habit) throws {
        for record in checkIns where record.habitID == habit.id { context.delete(record) }
        context.delete(habit)
        try commit()
    }
    public func isChecked(_ habit: Habit, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let key = HabitCalendar.key(for: date, calendar: calendar)
        return checkIns.contains { $0.habitID == habit.id && $0.dayKey == key }
    }
    public func toggle(_ habit: Habit, on date: Date, calendar: Calendar = .autoupdatingCurrent) throws {
        let dayKey = HabitCalendar.key(for: date, calendar: calendar)
        if let record = checkIns.first(where: { $0.habitID == habit.id && $0.dayKey == dayKey }) {
            context.delete(record)
        } else {
            context.insert(HabitCheckIn(habitID: habit.id, dayKey: dayKey))
        }
        try commit()
    }
    public func removeCheckIn(_ record: HabitCheckIn) throws {
        guard let current = checkIns.first(where: { $0.key == record.key }) else { return }
        context.delete(current)
        try commit()
    }
    public func streak(for habit: Habit, asOf date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let keys = Set(checkIns.filter { $0.habitID == habit.id }.map(\.dayKey))
        return HabitCalendar.streak(dayKeys: keys, asOf: date, calendar: calendar)
    }
    public func restore(_ snapshot: DeletedHabitSnapshot) throws {
        guard !habits.contains(where: { $0.id == snapshot.id }) else { throw DeletionRestoreError.alreadyExists }
        let habit = Habit(name: snapshot.name); habit.id = snapshot.id; habit.createdAt = snapshot.createdAt
        context.insert(habit)
        for record in snapshot.records { context.insert(HabitCheckIn(habitID: record.habitID, dayKey: record.dayKey)) }
        try commit()
    }
    public func restore(_ snapshot: DeletedCheckInSnapshot) throws {
        guard habits.contains(where: { $0.id == snapshot.habitID }) else { throw DeletionRestoreError.missingHabit }
        guard !checkIns.contains(where: { $0.habitID == snapshot.habitID && $0.dayKey == snapshot.dayKey }) else { throw DeletionRestoreError.alreadyExists }
        context.insert(HabitCheckIn(habitID: snapshot.habitID, dayKey: snapshot.dayKey)); try commit()
    }
    private func validated(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw HabitRepositoryError.emptyName }
        return name
    }
    private func commit() throws {
        do { try context.save(); try reload() }
        catch { context.rollback(); try? reload(); throw error }
    }
    private func reload() throws {
        habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
        checkIns = try context.fetch(FetchDescriptor<HabitCheckIn>())
    }
}
