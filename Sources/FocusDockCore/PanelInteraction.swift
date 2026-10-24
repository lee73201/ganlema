import Foundation

/// The controller owns timers; this deterministic state machine owns their meaning.
public struct PanelInteraction {
    public static let hoverDelay: TimeInterval = 0.25
    public static let collapseDelay: TimeInterval = 0.55
    public private(set) var isExpanded = false
    public private(set) var isPinned = false
    public private(set) var isInside = false
    public private(set) var isEditing = false
    public private(set) var isDragging = false
    public private(set) var isMenuTracking = false
    private var requiresPointerExit = false

    public enum Event {
        case enter, leave, hoverElapsed, collapseElapsed, click, reveal, collapse
        case editing(Bool), dragging(Bool), menuTracking(Bool)
    }
    public enum Effect: Equatable { case none, cancelTimers, scheduleOpen, scheduleClose }
    public init() {}

    @discardableResult public mutating func handle(_ event: Event) -> Effect {
        switch event {
        case .enter:
            isInside = true
            return isExpanded || isDragging || isMenuTracking || requiresPointerExit ? .cancelTimers : .scheduleOpen
        case .leave:
            isInside = false
            requiresPointerExit = false
            return canCollapse ? .scheduleClose : .cancelTimers
        case .hoverElapsed:
            if isInside && !isDragging && !isMenuTracking && !requiresPointerExit { isExpanded = true }
        case .collapseElapsed:
            if canCollapse && !isInside { isExpanded = false }
        case .click:
            requiresPointerExit = false
            isExpanded = true
            isPinned.toggle()
            return !isPinned && !isInside && canCollapse ? .scheduleClose : .cancelTimers
        case .reveal:
            requiresPointerExit = false
            isExpanded = true
            isPinned = true
            return .cancelTimers
        case .collapse:
            guard !isEditing && !isDragging && !isMenuTracking else { return .none }
            requiresPointerExit = isInside
            isPinned = false
            isExpanded = false
            return .cancelTimers
        case let .editing(value):
            isEditing = value
            if value { isExpanded = true }
            return !value && !isInside && canCollapse ? .scheduleClose : .cancelTimers
        case let .dragging(value):
            isDragging = value
            return !value && !isInside && canCollapse ? .scheduleClose : .cancelTimers
        case let .menuTracking(value):
            isMenuTracking = value
            if !value && isInside && !isExpanded && !isDragging && !requiresPointerExit { return .scheduleOpen }
            return !value && !isInside && canCollapse ? .scheduleClose : .cancelTimers
        }
        return .none
    }

    private var canCollapse: Bool { isExpanded && !isPinned && !isEditing && !isDragging && !isMenuTracking }
}
