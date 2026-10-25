import Foundation
import Testing
import FocusDockCore

@Test func firstUpgradeRetainsClassicCapsuleAndDelays() {
    let name = "local.focusdock.test.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let value = FloatingAppearance.load(from: defaults)
    #expect(value.shape == .classic && value.scale == .medium && value.size() == DeadlineUrgency.normal.capsuleSize)
    #expect(value.hoverDelay == PanelInteraction.hoverDelay && value.collapseDelay == PanelInteraction.collapseDelay)
}
@Test func appearanceSettingsRoundTripAndNeverTouchTaskOrWindowPreferences() {
    let name = "local.focusdock.test.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("keep", forKey: "placement.display")
    for shape in CapsuleShape.allCases {
        var value = FloatingAppearance(); value.shape = shape; value.scale = .large; value.content = .deadline; value.colorMode = .custom
        value.opacity = 0.31; value.hoverDelay = 0.8; value.collapseDelay = 1.7; value.cornerRadius = 8; value.red = 0.2; value.shadow = .subtle; value.edgeSnap = false
        value.save(to: defaults)
        #expect(FloatingAppearance.load(from: defaults) == value)
    }
    #expect(defaults.string(forKey: "placement.display") == "keep")
    defaults.set(Data("invalid".utf8), forKey: FloatingAppearance.defaultsKey)
    #expect(FloatingAppearance.load(from: defaults) == FloatingAppearance())
}
@Test func presetsScalesAndRadiiStayBounded() {
    for shape in CapsuleShape.allCases {
        for scale in CapsuleScale.allCases {
            var value = FloatingAppearance(); value.shape = shape; value.scale = scale
            let size = value.size()
            #expect(size.width > 0 && size.height >= 17 && size.width < 300)
            #expect(value.radius(in: size) <= size.height / 2)
            if shape == .circle { #expect(size.width == size.height) }
        }
    }
    var invalid = FloatingAppearance(); invalid.opacity = .nan; invalid.hoverDelay = -1; invalid.collapseDelay = 90; invalid.red = 20; invalid.cornerRadius = -9
    #expect(invalid.normalized.opacity == 0.65 && invalid.normalized.hoverDelay == 0.1 && invalid.normalized.collapseDelay == 3)
    #expect(invalid.normalized.red == 1 && invalid.normalized.cornerRadius == 4)
}
@Test func roundedTransparentCornersAreExcludedButCenterAndEdgesAreInteractive() {
    let size = CGSize(width: 52, height: 52)
    #expect(!FloatingGeometry.contains(CGPoint(x: 1, y: 1), size: size, radius: 26))
    #expect(FloatingGeometry.contains(CGPoint(x: 26, y: 26), size: size, radius: 26))
    #expect(FloatingGeometry.contains(CGPoint(x: 2, y: 26), size: size, radius: 26))
    #expect(!FloatingGeometry.contains(CGPoint(x: 53, y: 26), size: size, radius: 26))
}
@Test func autoExpansionUsesAvailableSideAndNeverLeavesNegativeOriginScreen() {
    let screen = CGRect(x: -1440, y: -80, width: 1440, height: 900), size = CGSize(width: 368, height: 506)
    let left = CGRect(x: -1430, y: -60, width: 52, height: 52)
    let frame = FloatingGeometry.expandedFrame(capsule: left, size: size, screen: screen)
    #expect(frame.minX == left.minX && frame.minY == left.minY && screen.contains(frame))
    let right = CGRect(x: -62, y: 750, width: 52, height: 52)
    let other = FloatingGeometry.expandedFrame(capsule: right, size: size, screen: screen)
    #expect(other.maxX == right.maxX && other.maxY == right.maxY && screen.contains(other))
}
@Test func edgeSnapRespectsThresholdAndClampsSmallDisplays() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = FloatingGeometry.snapped(CGRect(x: 2, y: 3, width: 176, height: 50), in: screen)
    #expect(frame.origin == CGPoint(x: 8, y: 8))
    let away = CGRect(x: 300, y: 300, width: 176, height: 50)
    #expect(FloatingGeometry.snapped(away, in: screen) == away)
    #expect(screen.contains(FloatingGeometry.snapped(CGRect(x: -90, y: 999, width: 52, height: 52), in: screen)))
}
@Test func focusWallClockPauseResumeAndReopeningAreAccurate() throws {
    let start = Date(timeIntervalSince1970: 10000), id = UUID()
    var value = FocusSession(taskID: id, taskTitle: "test", minutes: 25, now: start)
    #expect(value.duration == 1500 && value.remaining(at: start.addingTimeInterval(60)) == 1440)
    value.pause(at: start.addingTimeInterval(60))
    #expect(value.remaining(at: start.addingTimeInterval(800)) == 1440 && !value.isFinished(at: start.addingTimeInterval(5000)))
    value.resume(at: start.addingTimeInterval(900))
    let decoded = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(value))
    #expect(decoded == value && decoded.taskID == id)
    #expect(decoded.remaining(at: start.addingTimeInterval(1000)) == 1340)
    #expect(decoded.isFinished(at: start.addingTimeInterval(2340)))
    #expect(decoded.remaining(at: start.addingTimeInterval(9000)) == 0)
    #expect(FocusSession(taskID: id, taskTitle: "test", minutes: 50, now: start).duration == 3000)
}
@Test @MainActor func quickEditsPreserveOtherTaskFieldsAndSurviveRestart() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qa-quickedit-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("tasks.store")
    let repo = try TaskRepository(storeURL: url)
    let task = try repo.add(TaskDraft(title: "before", notes: "retain", category: "work", reminderOffsets: [2700,0]))
    let id = task.id, created = task.createdAt
    var draft = TaskDraft(item: task); draft.title = "after"; draft.priority = .high; draft.dueDate = Date(timeIntervalSince1970: 90000)
    try repo.update(task, with: draft)
    let reopened = try TaskRepository(storeURL: url), saved = try #require(reopened.items.first)
    #expect(saved.id == id && saved.createdAt == created && saved.notes == "retain" && saved.category == "work")
    #expect(saved.title == "after" && saved.priority == .high && saved.dueDate == draft.dueDate && saved.reminderOffsets == [2700,0])
}
@Test func expansionDirectionCanRemainStableWhileResizingOrDragging() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let capsule = CGRect(x: 650, y: 700, width: 176, height: 50)
    let frame = FloatingGeometry.expandedFrame(capsule: capsule, size: CGSize(width: 620, height: 700), screen: screen, expandLeft: false, expandDown: true)
    #expect(frame.minX == capsule.minX && frame.maxY == capsule.maxY)
    #expect(screen.contains(frame))
    let smallScreen = CGRect(x: -100, y: -200, width: 280, height: 320)
    #expect(FloatingGeometry.expandedFrame(capsule: capsule, size: CGSize(width: 900, height: 900), screen: smallScreen) == smallScreen)
}
@Test func pausingAnExpiredFocusDoesNotFreezeAnUnfinishedZeroTimer() {
    let start = Date(timeIntervalSince1970: 10000)
    var session = FocusSession(taskID: UUID(), taskTitle: "test", minutes: 25, now: start)
    session.pause(at: start.addingTimeInterval(1501))
    #expect(session.isFinished(at: start.addingTimeInterval(1501)) && session.pausedRemaining == nil)
    session.resume(at: start.addingTimeInterval(1600))
    #expect(session.isFinished(at: start.addingTimeInterval(1600)))
}
@Test func draggingAcrossScreenKeepsCollapseReopenAnchorStable() {
    let screen = CGRect(x: -1440, y: -80, width: 1440, height: 900)
    for x in [-1432.0, -900.0, -420.0] {
        for y in [-72.0, 200.0] {
            let expanded = CGRect(x: x, y: y, width: 412, height: 560)
            for shape in CapsuleShape.allCases {
                var appearance = FloatingAppearance(); appearance.shape = shape
                let content = appearance.size()
                let capsule = FloatingGeometry.capsuleFrame(attachedTo: expanded, size: CGSize(width: content.width + 8, height: content.height + 8), screen: screen)
                let reopened = FloatingGeometry.expandedFrame(capsule: capsule, size: expanded.size, screen: screen)
                #expect(abs(reopened.minX - expanded.minX) < 0.01 && abs(reopened.minY - expanded.minY) < 0.01)
            }
        }
    }
}
@Test func changingPresetKeepsNearestVisibleEdgesWithoutJumping() {
    let screen = CGRect(x: -1440, y: -80, width: 1440, height: 900)
    for initial in [CGRect(x: -1432, y: 700, width: 228, height: 70), CGRect(x: -236, y: -72, width: 228, height: 70)] {
        for shape in CapsuleShape.allCases {
            for scale in CapsuleScale.allCases {
                var settings = FloatingAppearance(); settings.shape = shape; settings.scale = scale
                let content = settings.size()
                let changed = FloatingGeometry.resizedCapsuleFrame(from: initial, size: CGSize(width: content.width + 8, height: content.height + 8), screen: screen)
                #expect(screen.contains(changed))
                if initial.midX < screen.midX { #expect(changed.minX == initial.minX) } else { #expect(changed.maxX == initial.maxX) }
                if initial.midY >= screen.midY { #expect(changed.maxY == initial.maxY) } else { #expect(changed.minY == initial.minY) }
            }
        }
    }
}
