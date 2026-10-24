import Foundation
import CoreGraphics

// Dependency-free checks for machines whose Command Line Tools omit SwiftDataMacros.
// These exercise the real production logic. They do not validate SwiftData or the UI.
var passed = 0
func check(_ name: String, _ body: () throws -> Void) rethrows {
    try body()
    passed += 1
    print("PASS: \(name)")
}
func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(condition(), "Expectation failed", file: file, line: line)
}

check("250ms hover and cancelled hover") {
    var state = PanelInteraction()
    expect(PanelInteraction.hoverDelay == 0.25)
    expect(state.handle(.enter) == .scheduleOpen)
    state.handle(.leave)
    state.handle(.hoverElapsed)
    expect(!state.isExpanded)
    state.handle(.enter)
    state.handle(.hoverElapsed)
    expect(state.isExpanded && !state.isPinned)
}
check("550ms delayed collapse and reentry") {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.hoverElapsed)
    expect(PanelInteraction.collapseDelay == 0.55)
    expect(state.handle(.leave) == .scheduleClose)
    expect(state.handle(.enter) == .cancelTimers)
    state.handle(.collapseElapsed)
    expect(state.isExpanded)
    state.handle(.leave)
    state.handle(.collapseElapsed)
    expect(!state.isExpanded)
}
check("pin and unpin outside panel") {
    var state = PanelInteraction()
    state.handle(.click)
    state.handle(.leave)
    state.handle(.collapseElapsed)
    expect(state.isExpanded && state.isPinned)
    expect(state.handle(.click) == .scheduleClose)
    state.handle(.collapseElapsed)
    expect(!state.isExpanded && !state.isPinned)
}
check("editing, dragging, and menu reveal") {
    var state = PanelInteraction()
    state.handle(.editing(true))
    state.handle(.leave)
    state.handle(.collapseElapsed)
    state.handle(.collapse)
    expect(state.isExpanded)
    expect(state.handle(.editing(false)) == .scheduleClose)
    state.handle(.dragging(true))
    state.handle(.collapseElapsed)
    expect(state.isExpanded)
    expect(state.handle(.dragging(false)) == .scheduleClose)
    state.handle(.collapseElapsed)
    expect(!state.isExpanded)
    state.handle(.reveal)
    expect(state.isExpanded && state.isPinned)
    state.handle(.collapse)
    expect(!state.isExpanded && !state.isPinned)
}
try check("negative display origin, persisted anchor, resolution change") {
    let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let placement = WindowPlacement(topRight: CGPoint(x: -40, y: 820), in: screen)
    let frame = placement.frame(size: CGSize(width: 392, height: 576), in: screen)
    expect(frame.maxX == -40 && frame.maxY == 820 && screen.contains(frame))
    let restored = try JSONDecoder().decode(WindowPlacement.self, from: JSONEncoder().encode(placement))
    expect(restored == placement)
    let changed = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    expect(changed.contains(restored.frame(size: CGSize(width: 392, height: 576), in: changed)))
}
check("all edges clamp and small display fits") {
    let screen = CGRect(x: 0, y: 25, width: 800, height: 600)
    for x in [-3.0, 0, 0.5, 1, 4] {
        for y in [-3.0, 0, 0.5, 1, 4] {
            expect(screen.contains(WindowPlacement(horizontal: x, vertical: y).frame(size: CGSize(width: 392, height: 576), in: screen)))
        }
    }
    let small = CGRect(x: 20, y: -100, width: 300, height: 400)
    expect(WindowPlacement().frame(size: CGSize(width: 392, height: 576), in: small) == small)
}
check("collapsed drag does not expand mid-gesture") {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.dragging(true))
    expect(state.handle(.enter) == .cancelTimers)
    state.handle(.hoverElapsed)
    expect(!state.isExpanded)
    state.handle(.dragging(false))
    expect(state.handle(.enter) == .scheduleOpen)
    state.handle(.hoverElapsed)
    expect(state.isExpanded)
}
check("menus hold panel open and resume hover after dismissal") {
    var state = PanelInteraction()
    state.handle(.enter)
    state.handle(.hoverElapsed)
    state.handle(.menuTracking(true))
    state.handle(.leave)
    state.handle(.collapseElapsed)
    state.handle(.collapse)
    expect(state.isExpanded)
    expect(state.handle(.menuTracking(false)) == .scheduleClose)
    state.handle(.collapseElapsed)
    expect(!state.isExpanded)
    state.handle(.menuTracking(true))
    state.handle(.enter)
    state.handle(.hoverElapsed)
    expect(!state.isExpanded)
    expect(state.handle(.menuTracking(false)) == .scheduleOpen)
}
print("\(passed) logic checks passed. SwiftData and UI are not covered by this runner.")
