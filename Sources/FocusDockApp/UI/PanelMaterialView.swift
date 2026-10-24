import AppKit
import SwiftUI

/// A real AppKit backdrop, composited from the desktop behind this NSPanel.
final class PanelMaterialView<Content: View>: NSView {
    let effect = NSVisualEffectView()
    let host: NSHostingView<Content>
    override var isOpaque: Bool { false }

    init(host: NSHostingView<Content>) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = false
        effect.wantsLayer = true
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        for view in [effect, host] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(host:)") }
    func setExpanded(_ expanded: Bool) {
        layer?.cornerRadius = expanded ? 18 : 25
        layer?.masksToBounds = true
        effect.layer?.cornerRadius = expanded ? 18 : 25
        effect.layer?.masksToBounds = true
    }
}
