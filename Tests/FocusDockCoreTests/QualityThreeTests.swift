import Foundation
import Testing
import FocusDockCore

@Test @MainActor func deletedTaskUndoPreservesIdentityCompletionAndRemindersAcrossReopen() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qa-undo-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("tasks.store"), repo = try TaskRepository(storeURL: url)
    let item = try repo.add(TaskDraft(title: "undo", notes: "keep", dueDate: .now.addingTimeInterval(7200), priority: .high, category: "category", reminderOffsets: [2700,0]))
    try repo.toggleCompletion(item)
    let snapshot = DeletedTaskSnapshot(item)
    try repo.delete(item); #expect(repo.items.isEmpty)
    try repo.restore(snapshot)
    let reopened = try TaskRepository(storeURL: url), restored = try #require(reopened.items.first)
    #expect(restored.id == snapshot.id && restored.createdAt == snapshot.createdAt && restored.completedAt == snapshot.completedAt && restored.isCompleted)
    #expect(restored.notes == "keep" && restored.category == "category" && restored.priority == .high && restored.reminderOffsets == [2700,0] && restored.dueDate == snapshot.draft.dueDate)
    #expect(throws: DeletionRestoreError.self) { try repo.restore(snapshot) }
    #expect(repo.items.count == 1)
}
@Test @MainActor func habitDeletionUndoRestoresAllHistoricalCheckIns() throws {
    let repo = try HabitRepository(inMemory: true), habit = try repo.add(name: "reading")
    let days = HabitCalendar.week(containing: .now)
    try repo.toggle(habit, on: days[0]); try repo.toggle(habit, on: days[2])
    let snapshot = DeletedHabitSnapshot(habit, records: repo.checkIns)
    try repo.delete(habit); #expect(repo.habits.isEmpty && repo.checkIns.isEmpty)
    try repo.restore(snapshot)
    #expect(repo.habits.first?.id == snapshot.id && repo.habits.first?.createdAt == snapshot.createdAt)
    #expect(Set(repo.checkIns.map(\.dayKey)) == Set(snapshot.records.map(\.dayKey)))
    #expect(throws: DeletionRestoreError.self) { try repo.restore(snapshot) }
    #expect(repo.habits.count == 1 && repo.checkIns.count == 2)
}
@Test @MainActor func individualCheckInUndoRequiresParentAndNeverDuplicates() throws {
    let repo = try HabitRepository(inMemory: true), habit = try repo.add(name: "water")
    try repo.toggle(habit, on: .now)
    let record = try #require(repo.checkIns.first), snapshot = DeletedCheckInSnapshot(record)
    try repo.removeCheckIn(record); try repo.restore(snapshot)
    #expect(repo.checkIns.count == 1)
    #expect(throws: DeletionRestoreError.self) { try repo.restore(snapshot) }
    try repo.delete(habit)
    #expect(throws: DeletionRestoreError.self) { try repo.restore(snapshot) }
}
@Test @MainActor func multipleDeletesUndoNewestFirstAndExpireAtTenSeconds() throws {
    var date = Date(timeIntervalSince1970: 1000), restored: [Int] = []
    let queue = DeletionUndo(clock: { date })
    queue.offer("one") { restored.append(1) }
    date = date.addingTimeInterval(2); queue.offer("two") { restored.append(2) }
    try queue.undo(); try queue.undo()
    #expect(restored == [2,1] && queue.entries.isEmpty)
    queue.offer("expired") { restored.append(3) }
    date = date.addingTimeInterval(10); try queue.undo()
    #expect(restored == [2,1] && queue.entries.isEmpty)
}
@Test @MainActor func failedUndoRemainsAvailableForRetry() throws {
    enum Failure: Error { case disk }
    let queue = DeletionUndo(); var attempts = 0
    queue.offer("retry") { attempts += 1; if attempts == 1 { throw Failure.disk } }
    #expect(throws: Failure.self) { try queue.undo() }
    #expect(queue.entries.count == 1)
    try queue.undo(); #expect(attempts == 2 && queue.entries.isEmpty)
}
@Test func countdownFormatsPausedRunningAndFinishedSessions() {
    let now = Date(timeIntervalSince1970: 1000)
    var session = FocusSession(taskID: UUID(), taskTitle: "task", minutes: 25, now: now)
    #expect(FocusCountdown.text(session: session, now: now) == "25:00")
    #expect(FocusCountdown.text(session: session, now: now.addingTimeInterval(1.1)) == "24:59")
    session.pause(at: now.addingTimeInterval(60))
    #expect(FocusCountdown.text(session: session, now: now.addingTimeInterval(3600)) == "24:00")
    session.resume(at: now.addingTimeInterval(3600))
    #expect(FocusCountdown.text(session: session, now: now.addingTimeInterval(6000)) == "00:00")
}
