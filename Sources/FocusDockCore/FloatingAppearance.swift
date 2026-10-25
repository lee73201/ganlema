import Foundation
import CoreGraphics

public enum CapsuleShape: String, CaseIterable, Codable, Identifiable {
    case classic, rectangle, circle, island, strip
    public var id: String { rawValue }
    public var title: String {
        switch self { case .classic: return "经典胶囊"; case .rectangle: return "圆角矩形"; case .circle: return "圆形按钮"; case .island: return "灵动岛"; case .strip: return "极简细条" }
    }
}
public enum CapsuleScale: String, CaseIterable, Codable { case small, medium, large
    public var factor: Double { switch self { case .small: return 0.85; case .medium: return 1; case .large: return 1.2 } }
    public var title: String { switch self { case .small: return "小"; case .medium: return "中"; case .large: return "大" } }
}
public enum CapsuleColorMode: String, CaseIterable, Codable { case system, light, dark, custom
    public var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色"; case .custom: return "自定义强调色" } }
}
public enum CapsuleMaterial: String, CaseIterable, Codable { case popover, menu, hud
    public var title: String { switch self { case .popover: return "标准毛玻璃"; case .menu: return "轻透菜单"; case .hud: return "HUD 毛玻璃" } }
}
public enum CapsuleShadow: String, CaseIterable, Codable { case off, subtle, standard
    public var title: String { switch self { case .off: return "关闭"; case .subtle: return "轻微"; case .standard: return "标准" } }
}
public enum CapsuleContent: String, CaseIterable, Codable { case icon, count, deadline
    public var title: String { switch self { case .icon: return "图标"; case .count: return "待办数量"; case .deadline: return "最近截止任务" } }
}
/// Versioned independently of SwiftData. Missing/invalid settings safely use the original capsule.
public struct FloatingAppearance: Codable, Equatable {
    public var shape = CapsuleShape.classic
    public var scale = CapsuleScale.medium
    public var colorMode = CapsuleColorMode.system
    public var material = CapsuleMaterial.popover
    public var shadow = CapsuleShadow.standard
    public var content = CapsuleContent.count
    public var opacity = 0.65
    public var cornerRadius = 12.0
    public var red = 0.44
    public var green = 0.59
    public var blue = 0.51
    public var hoverDelay = 0.25
    public var collapseDelay = 0.55
    public var clickToPin = true
    public var edgeSnap = true
    public init() {}
    public static let defaultsKey = "floatingAppearance.v1"
    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: defaultsKey), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value.normalized
    }
    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(normalized) { defaults.set(data, forKey: Self.defaultsKey) }
    }
    public var normalized: Self {
        var value = self
        func bound(_ n: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double { n.isFinite ? min(max(n, range.lowerBound), range.upperBound) : fallback }
        value.opacity = bound(opacity, 0.15...1, 0.65)
        value.cornerRadius = bound(cornerRadius, 4...24, 12)
        value.red = bound(red, 0...1, 0.44); value.green = bound(green, 0...1, 0.59); value.blue = bound(blue, 0...1, 0.51)
        value.hoverDelay = bound(hoverDelay, 0.1...1.5, 0.25)
        value.collapseDelay = bound(collapseDelay, 0.15...3, 0.55)
        return value
    }
    public func size(urgency: DeadlineUrgency = .normal) -> CGSize {
        let base: CGSize
        switch shape {
        case .classic: base = urgency.capsuleSize
        case .rectangle: base = CGSize(width: 172, height: 48)
        case .circle: base = CGSize(width: 52, height: 52)
        case .island: base = CGSize(width: 206, height: 40)
        case .strip: base = CGSize(width: 112, height: 20)
        }
        return CGSize(width: base.width * scale.factor, height: base.height * scale.factor)
    }
    public func radius(in size: CGSize) -> CGFloat {
        switch shape {
        case .classic, .circle, .strip: return min(size.width, size.height) / 2
        case .rectangle: return min(normalized.cornerRadius, size.height / 2)
        case .island: return min(18 * scale.factor, size.height / 2)
        }
    }
}

public enum FloatingGeometry {
    /// Keep the capsule's stored anchor untouched. Grow toward whichever side has more room.
    public static func expandedFrame(capsule: CGRect, size: CGSize, screen: CGRect, expandLeft: Bool? = nil, expandDown: Bool? = nil) -> CGRect {
        let width = min(size.width, screen.width), height = min(size.height, screen.height)
        let x = (expandLeft ?? (capsule.midX >= screen.midX)) ? capsule.maxX - width : capsule.minX
        let y = (expandDown ?? (capsule.midY >= screen.midY)) ? capsule.maxY - height : capsule.minY
        return CGRect(x: min(max(x, screen.minX), screen.maxX - width), y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
    }
    /// Size/shape changes retain the nearest visible edge rather than moving a small
    /// circle away from the left edge just to preserve a historical top-right anchor.
    public static func resizedCapsuleFrame(from frame: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let width = min(size.width, screen.width), height = min(size.height, screen.height)
        let x = frame.midX < screen.midX ? frame.minX : frame.maxX - width
        let y = frame.midY >= screen.midY ? frame.maxY - height : frame.minY
        return CGRect(x: min(max(x, screen.minX), screen.maxX - width), y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
    }
    /// Attach a collapsed entry to the nearest side after dragging an expanded panel.
    /// Reopening with automatic direction must reconstruct the same expanded frame.
    public static func capsuleFrame(attachedTo frame: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let x = frame.midX >= screen.midX ? frame.maxX - size.width : frame.minX
        let y = frame.midY >= screen.midY ? frame.maxY - size.height : frame.minY
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
    public static func snapped(_ frame: CGRect, in screen: CGRect, distance: CGFloat = 18, inset: CGFloat = 8) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.minX, screen.minX), screen.maxX - f.width)
        f.origin.y = min(max(f.minY, screen.minY), screen.maxY - f.height)
        if abs(f.minX - screen.minX) < distance { f.origin.x = screen.minX + inset }
        else if abs(f.maxX - screen.maxX) < distance { f.origin.x = screen.maxX - inset - f.width }
        if abs(f.minY - screen.minY) < distance { f.origin.y = screen.minY + inset }
        else if abs(f.maxY - screen.maxY) < distance { f.origin.y = screen.maxY - inset - f.height }
        f.origin.x = min(max(f.minX, screen.minX), screen.maxX - f.width)
        f.origin.y = min(max(f.minY, screen.minY), screen.maxY - f.height)
        return f
    }
    public static func contains(_ point: CGPoint, size: CGSize, radius: CGFloat) -> Bool {
        let rect = CGRect(origin: .zero, size: size)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(point)
    }
}
