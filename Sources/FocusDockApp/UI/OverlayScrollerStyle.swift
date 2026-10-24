import AppKit
import SwiftUI

/// Keep native overlay scrollers throughout this panel, including nested note editors.
struct OverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollerStyleView { ScrollerStyleView() }
    func updateNSView(_ view: ScrollerStyleView, context: Context) { view.configureSoon() }
}

final class ScrollerStyleView: NSView {
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configureSoon() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureSoon() }
    func configureSoon() {
        DispatchQueue.main.async { [weak self] in
            func style(_ view: NSView) {
                if let scroll = view as? NSScrollView {
                    scroll.scrollerStyle = .overlay
                    scroll.autohidesScrollers = true
                    scroll.drawsBackground = false
                    scroll.hasHorizontalScroller = false
                    scroll.horizontalScrollElasticity = .none
                    scroll.verticalScroller?.controlSize = .mini
                }
                view.subviews.forEach(style)
            }
            if let root = self?.window?.contentView { style(root) }
        }
    }
}
