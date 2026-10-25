import Foundation
import CoreGraphics

/// User size is separate from the normalized position and from deadline-driven default sizing.
public struct PanelSizePreference: Codable, Equatable {
    public static let minimum = CGSize(width: 340, height: 400)
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public init(_ size: CGSize) { self.init(width: size.width, height: size.height) }
    public func constrained(to visibleSize: CGSize) -> CGSize {
        let maxWidth = max(0, visibleSize.width); let maxHeight = max(0, visibleSize.height)
        let safeWidth = width.isFinite ? width : 368
        let safeHeight = height.isFinite ? height : 506
        return CGSize(width: min(maxWidth, max(min(Self.minimum.width, maxWidth), safeWidth)),
                      height: min(maxHeight, max(min(Self.minimum.height, maxHeight), safeHeight)))
    }
    public static func effective(manual: Self?, urgency: DeadlineUrgency, visibleSize: CGSize) -> CGSize {
        (manual ?? Self(urgency.panelSize)).constrained(to: visibleSize)
    }
    public static func resizedFrame(from initial: CGRect, delta: CGSize, in visible: CGRect) -> CGRect {
        let size = Self(width: initial.width + delta.width, height: initial.height - delta.height).constrained(to: visible.size)
        let origin = CGPoint(x: min(max(initial.minX, visible.minX), visible.maxX - size.width),
                             y: min(max(initial.maxY - size.height, visible.minY), visible.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }
}
