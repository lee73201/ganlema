import AppKit
import SwiftUI
import FocusDockCore

/// Native desktop backdrop. The small clear margin hosts a custom subtle shadow without
/// expanding the interactive path. Expanded panels retain their independent original layout.
final class PanelMaterialView<Content: View>: NSView {
    let effect = NSVisualEffectView()
    let host: NSHostingView<Content>
    private let surface = NSView()
    private let tint = NSView()
    private var edges: [NSLayoutConstraint] = []
    private var expandedState = false
    private var appearanceState = FloatingAppearance()
    override var isOpaque: Bool { false }
    init(host: NSHostingView<Content>) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true; surface.wantsLayer = true
        surface.layer?.masksToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        edges = [surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor), surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor)]
        NSLayoutConstraint.activate(edges)
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.isEmphasized = false; effect.wantsLayer = true
        host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
        tint.wantsLayer = true
        for view in [effect, tint, host] {
            view.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: surface.leadingAnchor), view.trailingAnchor.constraint(equalTo: surface.trailingAnchor), view.topAnchor.constraint(equalTo: surface.topAnchor), view.bottomAnchor.constraint(equalTo: surface.bottomAnchor)])
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(host:)") }
    override func layout() { super.layout(); updateMask() }
    private func updateMask() {
        let radius = expandedState ? 18 : appearanceState.radius(in: surface.bounds.size)
        surface.layer?.cornerRadius = radius
        layer?.shadowPath = CGPath(roundedRect: surface.frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    func configure(expanded: Bool, appearance: FloatingAppearance) {
        expandedState = expanded; appearanceState = appearance
        let inset: CGFloat = expanded ? 0 : 4
        edges[0].constant = inset; edges[1].constant = -inset; edges[2].constant = inset; edges[3].constant = -inset
        effect.material = expanded ? .popover : appearance.material == .menu ? .menu : appearance.material == .hud ? .hudWindow : .popover
        effect.appearance = !expanded && appearance.shape == .island ? NSAppearance(named: .darkAqua) : nil
        effect.alphaValue = expanded ? 1 : appearance.opacity
        tint.layer?.backgroundColor = !expanded && appearance.shape == .island ? NSColor.black.withAlphaComponent(0.7 + appearance.opacity * 0.2).cgColor : NSColor.clear.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = !expanded && appearance.shadow == .subtle ? 0.16 : 0
        layer?.shadowRadius = 3; layer?.shadowOffset = CGSize(width: 0, height: -1)
        needsLayout = true; updateMask()
    }
}
