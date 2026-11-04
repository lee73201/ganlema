import Foundation

public enum PinnedBackdrop {
    public static let range = 0.35...1.0
    public static let defaultOpacity = 0.78

    public static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultOpacity
    }

    public static func opacity(pinned: Bool, preference: Double, reduceTransparency: Bool) -> Double {
        pinned && !reduceTransparency ? normalized(preference) : 1
    }
}
