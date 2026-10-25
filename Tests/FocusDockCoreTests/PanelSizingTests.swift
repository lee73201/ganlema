import Foundation
import Testing
import FocusDockCore

@Test func userPanelSizeClampsToUsableMinimumAndScreen() {
    #expect(PanelSizePreference(width: 1, height: 1).constrained(to: CGSize(width: 1440, height: 900)) == CGSize(width: 340, height: 400))
    #expect(PanelSizePreference(width: 2000, height: 2000).constrained(to: CGSize(width: 1440, height: 900)) == CGSize(width: 1440, height: 900))
    #expect(PanelSizePreference(width: 400, height: 500).constrained(to: CGSize(width: 300, height: 350)) == CGSize(width: 300, height: 350))
}
@Test func savedManualSizeTakesPriorityAndDefaultsKeepDeadlineGrowth() throws {
    let saved = PanelSizePreference(width: 620, height: 710)
    let decoded = try JSONDecoder().decode(PanelSizePreference.self, from: JSONEncoder().encode(saved))
    #expect(decoded == saved)
    #expect(PanelSizePreference.effective(manual: decoded, urgency: .overdue, visibleSize: CGSize(width: 1440, height: 900)) == CGSize(width: 620, height: 710))
    #expect(PanelSizePreference.effective(manual: nil, urgency: .imminent, visibleSize: CGSize(width: 1440, height: 900)) == DeadlineUrgency.imminent.panelSize)
}
@Test func resizingStaysInsideNegativeOriginDisplayAndPreservesUsableFrame() {
    let screen = CGRect(x: -1440, y: -80, width: 1440, height: 900)
    let initial = CGRect(x: -600, y: 100, width: 368, height: 506)
    let enlarged = PanelSizePreference.resizedFrame(from: initial, delta: CGSize(width: 450, height: -180), in: screen)
    #expect(enlarged.size == CGSize(width: 818, height: 686))
    #expect(screen.contains(enlarged))
    let reduced = PanelSizePreference.resizedFrame(from: initial, delta: CGSize(width: -2000, height: 2000), in: screen)
    #expect(reduced.size == CGSize(width: 340, height: 400) && screen.contains(reduced))
}
