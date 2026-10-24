import Foundation
import CoreGraphics

/// A normalized top-right anchor survives resolution and display arrangement changes.
public struct WindowPlacement: Codable, Equatable {
    public var horizontal: Double
    public var vertical: Double
    public init(horizontal: Double = 0.97, vertical: Double = 0.92) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public init(topRight: CGPoint, in visibleFrame: CGRect) {
        horizontal = (topRight.x - visibleFrame.minX) / max(visibleFrame.width, 1)
        vertical = (topRight.y - visibleFrame.minY) / max(visibleFrame.height, 1)
    }

    public func frame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = visibleFrame.minX + horizontal * visibleFrame.width - width
        let y = visibleFrame.minY + vertical * visibleFrame.height - height
        return CGRect(x: min(max(x, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(y, visibleFrame.minY), visibleFrame.maxY - height), width: width, height: height)
    }
}
