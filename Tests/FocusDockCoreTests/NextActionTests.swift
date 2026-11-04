import Foundation
import Testing
import FocusDockCore

@Test func recommendationUsesFittingEstimatesBeforeUnknownAndRanksByUrgency() throws {
    let suite = "FocusDockTests.estimates.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let now = Date(timeIntervalSince1970: 10_000)
    let overdueLong = TodoItem(title: "Long overdue", dueDate: now.addingTimeInterval(-60))
    let overdueUnknown = TodoItem(title: "Unknown overdue", dueDate: now.addingTimeInterval(-120))
    let soon = TodoItem(title: "Soon", dueDate: now.addingTimeInterval(3600))
    let high = TodoItem(title: "High priority", priority: .high)
    let completed = TodoItem(title: "Already done", dueDate: now.addingTimeInterval(-60))
    completed.isCompleted = true
    let items = [overdueLong, overdueUnknown, soon, high, completed]
    var estimates = TaskEstimates(defaults: defaults, existingIDs: Set(items.map(\.id)))
    estimates.set(50, for: overdueLong.id, defaults: defaults)
    estimates.set(15, for: soon.id, defaults: defaults)
    estimates.set(15, for: high.id, defaults: defaults)
    estimates.set(5, for: completed.id, defaults: defaults)

    let fitting = try #require(TaskRecommendation.choose(from: items, estimates: estimates, availableMinutes: 15, now: now))
    #expect(fitting.task.id == soon.id && fitting.estimatedMinutes == 15)
    #expect(fitting.reason == "2 小时内到期")
    let fallback = try #require(TaskRecommendation.choose(from: items, estimates: estimates, availableMinutes: 5, now: now))
    #expect(fallback.task.id == overdueUnknown.id && fallback.estimatedMinutes == nil)
    #expect(TaskRecommendation.choose(from: [overdueLong, completed], estimates: estimates, availableMinutes: 15, now: now) == nil)
    #expect(TaskRecommendation.choose(from: items, estimates: estimates, availableMinutes: 50, now: now)?.task.id == overdueLong.id)
    #expect(TaskRecommendation.choose(from: [soon, high], estimates: estimates, availableMinutes: 15, now: now.addingTimeInterval(-86_400))?.task.id == high.id)
}

@Test func taskEstimatesPersistClearAndPruneDeletedIDs() throws {
    let suite = "FocusDockTests.estimates.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let kept = UUID(), deleted = UUID()
    var estimates = TaskEstimates(defaults: defaults, existingIDs: [kept, deleted])
    estimates.set(25, for: kept, defaults: defaults)
    estimates.set(90, for: deleted, defaults: defaults)
    estimates.set(999, for: kept, defaults: defaults)
    var reopened = TaskEstimates(defaults: defaults, existingIDs: [kept])
    #expect(reopened[kept] == 25)
    #expect(reopened[deleted] == nil)
    reopened.set(nil, for: kept, defaults: defaults)
    let cleared = TaskEstimates(defaults: defaults, existingIDs: [kept, deleted])
    #expect(cleared[kept] == nil && cleared[deleted] == nil)
}

@Test func pausedFocusNotePersistsAndLegacySessionsStillDecode() throws {
    let start = Date(timeIntervalSince1970: 10_000)
    var session = FocusSession(taskID: UUID(), taskTitle: "Report", minutes: 15, now: start)
    #expect(session.duration == 900)
    session.pause(at: start.addingTimeInterval(20))
    session.setResumeNote("核对报告第三页")
    let payload = try JSONEncoder().encode(session)
    var restored = try JSONDecoder().decode(FocusSession.self, from: payload)
    #expect(restored.pausedRemaining == 880 && restored.resumeNote == "核对报告第三页")
    restored.resume(at: start.addingTimeInterval(1200))
    #expect(restored.pausedRemaining == nil && restored.resumeNote == "核对报告第三页")
    restored.setResumeNote(String(repeating: "字", count: 300))
    #expect(restored.resumeNote?.count == FocusSession.resumeNoteLimit)
    restored.setResumeNote("  ")
    #expect(restored.resumeNote == nil)
    var legacy = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    legacy.removeValue(forKey: "resumeNote")
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    let migrated = try JSONDecoder().decode(FocusSession.self, from: legacyData)
    #expect(migrated.pausedRemaining == 880 && migrated.resumeNote == nil)
}

@Test func quietCapsuleBlocksHoverAndQueuedEventsButAllowsIntentionalOpen() {
    var panel = PanelInteraction()
    #expect(panel.handle(.enter) == .scheduleOpen)
    #expect(panel.handle(.quietMode(true)) == .cancelTimers)
    panel.handle(.hoverElapsed)
    #expect(!panel.isExpanded)
    panel.handle(.menuTracking(true))
    #expect(panel.handle(.menuTracking(false)) == .cancelTimers)
    #expect(panel.handle(.enter) == .cancelTimers)
    panel.handle(.openUnpinned)
    #expect(panel.isExpanded && !panel.isPinned)
    #expect(panel.handle(.leave) == .scheduleClose)
    panel.handle(.collapseElapsed)
    panel.handle(.click)
    #expect(panel.isExpanded && panel.isPinned)
    panel.handle(.collapse)
    panel.handle(.reveal)
    #expect(panel.isExpanded && panel.isPinned)
    panel.handle(.collapse)
    panel.handle(.enter)
    #expect(panel.handle(.quietMode(false)) == .scheduleOpen)
    panel.handle(.hoverElapsed)
    #expect(panel.isExpanded && !panel.isQuiet)
}

@Test func pinnedBackdropClampsAndRespectsSystemContrastPreference() {
    #expect(PinnedBackdrop.opacity(pinned: true, preference: 0.61, reduceTransparency: false) == 0.61)
    #expect(PinnedBackdrop.opacity(pinned: false, preference: 0.61, reduceTransparency: false) == 1)
    #expect(PinnedBackdrop.opacity(pinned: true, preference: 0.61, reduceTransparency: true) == 1)
    #expect(PinnedBackdrop.normalized(0) == PinnedBackdrop.range.lowerBound)
    #expect(PinnedBackdrop.normalized(2) == PinnedBackdrop.range.upperBound)
    #expect(PinnedBackdrop.normalized(.nan) == PinnedBackdrop.defaultOpacity)
}
