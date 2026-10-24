import Foundation
import CoreGraphics
import Testing
import FocusDockCore

@Test func hoverMustStillBeInsideWhenDelayEnds() {
    var state = PanelInteraction()
    #expect(PanelInteraction.hoverDelay == 0.25)
    #expect(state.handle(.enter) == .scheduleOpen)
    state.handle(.leave)
    state.handle(.hoverElapsed)
    #expect(!state.isExpanded)
    state.handle(.enter)
    state.handle(.hoverElapsed)
    #expect(state.isExpanded)
    #expect(!state.isPinned)
}

@Test func reentryCancelsCollapseAndPinSurvivesLeaving() {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.hoverElapsed)
    #expect(state.handle(.leave) == .scheduleClose)
    #expect(state.handle(.enter) == .cancelTimers)
    state.handle(.collapseElapsed)
    #expect(state.isExpanded)
    state.handle(.click)
    state.handle(.leave)
    state.handle(.collapseElapsed)
    #expect(state.isExpanded && state.isPinned)
    #expect(state.handle(.click) == .scheduleClose)
    state.handle(.collapseElapsed)
    #expect(!state.isExpanded)
}

@Test func editingAndDraggingPreventUnexpectedCollapse() {
    var state = PanelInteraction()
    state.handle(.editing(true))
    state.handle(.leave)
    state.handle(.collapseElapsed)
    state.handle(.collapse)
    #expect(state.isExpanded)
    #expect(state.handle(.editing(false)) == .scheduleClose)
    state.handle(.dragging(true))
    state.handle(.collapseElapsed)
    #expect(state.isExpanded)
    #expect(state.handle(.dragging(false)) == .scheduleClose)
    state.handle(.collapseElapsed)
    #expect(!state.isExpanded)
}

@Test func menuRevealPinsAndEscapeCollapses() {
    var state = PanelInteraction()
    state.handle(.reveal)
    #expect(state.isExpanded && state.isPinned)
    state.handle(.collapse)
    #expect(!state.isExpanded && !state.isPinned)
}

@Test func manualCollapseWaitsForPointerExitBeforeHoverReopens() {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.click)
    state.handle(.collapse)
    #expect(state.handle(.enter) == .cancelTimers)
    state.handle(.hoverElapsed)
    #expect(!state.isExpanded)
    state.handle(.leave)
    #expect(state.handle(.enter) == .scheduleOpen)
    state.handle(.hoverElapsed)
    #expect(state.isExpanded)
    state.handle(.collapse)
    state.handle(.click)
    #expect(state.isExpanded && state.isPinned)
}

@Test func collapsedDragDoesNotExpandMidGesture() {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.dragging(true))
    #expect(state.handle(.enter) == .cancelTimers)
    state.handle(.hoverElapsed)
    #expect(!state.isExpanded)
    state.handle(.collapse)
    #expect(state.isDragging)
    state.handle(.dragging(false))
    #expect(state.handle(.enter) == .scheduleOpen)
    state.handle(.hoverElapsed)
    #expect(state.isExpanded)
}

@Test func openMenuPreventsCollapseAndResumesWhenDismissed() {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.hoverElapsed)
    state.handle(.menuTracking(true))
    state.handle(.leave)
    state.handle(.collapseElapsed)
    state.handle(.collapse)
    #expect(state.isExpanded)
    #expect(state.handle(.menuTracking(false)) == .scheduleClose)
    state.handle(.collapseElapsed)
    #expect(!state.isExpanded)
    state.handle(.menuTracking(true))
    state.handle(.enter)
    state.handle(.hoverElapsed)
    #expect(!state.isExpanded)
    #expect(state.handle(.menuTracking(false)) == .scheduleOpen)
}

@Test func placementHandlesNegativeDisplayOriginsAndResolutionChanges() throws {
    let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let placement = WindowPlacement(topRight: CGPoint(x: -40, y: 820), in: screen)
    let frame = placement.frame(size: CGSize(width: 392, height: 576), in: screen)
    #expect(frame.maxX == -40)
    #expect(frame.maxY == 820)
    #expect(screen.contains(frame))
    let restored = try JSONDecoder().decode(WindowPlacement.self, from: JSONEncoder().encode(placement))
    let resizedScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    #expect(resizedScreen.contains(restored.frame(size: CGSize(width: 392, height: 576), in: resizedScreen)))
}

@Test func placementClampsAllEdgesAndSmallScreens() {
    let screen = CGRect(x: 0, y: 25, width: 800, height: 600)
    for x in [-3.0, 0, 0.5, 1, 4] {
        for y in [-3.0, 0, 0.5, 1, 4] {
            let frame = WindowPlacement(horizontal: x, vertical: y).frame(size: CGSize(width: 392, height: 576), in: screen)
            #expect(screen.contains(frame))
        }
    }
    let tiny = CGRect(x: 20, y: -100, width: 300, height: 400)
    #expect(WindowPlacement().frame(size: CGSize(width: 392, height: 576), in: tiny) == tiny)
}

@Test @MainActor func repositoryRejectsBlankTitlesAndSortsActionableTasks() throws {
    let repository = try TaskRepository(inMemory: true)
    #expect(throws: TaskRepositoryError.self) { try repository.add(TaskDraft(title: " \n ")) }
    let normal = try repository.add(TaskDraft(title: "  普通任务  "))
    let high = try repository.add(TaskDraft(title: "高优先级", priority: .high))
    #expect(normal.title == "普通任务")
    #expect(repository.items.first?.id == high.id)
    try repository.toggleCompletion(high)
    #expect(repository.items.first?.id == normal.id)
    #expect(high.completedAt != nil)
    try repository.toggleCompletion(high)
    #expect(high.completedAt == nil)
    #expect(throws: TaskRepositoryError.self) { try repository.update(normal, with: TaskDraft(title: "\n")) }
    #expect(normal.title == "普通任务")
}

@Test @MainActor func swiftDataCRUDSurvivesReopeningTheStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusDockTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("tasks.store")
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    let taskID: UUID = try autoreleasepool {
        let repository = try TaskRepository(storeURL: store)
        let item = try repository.add(TaskDraft(title: "第一版", notes: "本地笔记", dueDate: due, priority: .high))
        try repository.toggleCompletion(item)
        return item.id
    }
    try autoreleasepool {
        let reopened = try TaskRepository(storeURL: store)
        let item = try #require(reopened.items.first)
        #expect(item.id == taskID)
        #expect(item.title == "第一版" && item.notes == "本地笔记")
        #expect(item.dueDate == due && item.priority == .high)
        #expect(item.isCompleted && item.completedAt != nil)
        try reopened.update(item, with: TaskDraft(title: "修改后的任务", priority: .low))
        try reopened.toggleCompletion(item)
    }
    try autoreleasepool {
        let reopened = try TaskRepository(storeURL: store)
        let item = try #require(reopened.items.first)
        #expect(item.title == "修改后的任务" && item.priority == .low)
        #expect(item.dueDate == nil && !item.isCompleted && item.completedAt == nil)
        try reopened.delete(item)
    }
    let final = try TaskRepository(storeURL: store)
    #expect(final.items.isEmpty)
}
