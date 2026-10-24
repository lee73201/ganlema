import AppKit
import SwiftUI

/// Native screen coordinates allow dragging between displays with different origins.
struct DragRegion: NSViewRepresentable {
    let controller: PanelWindowController
    var onClick: (() -> Void)?
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.onStart = { controller.dragBegan() }
        view.onMove = { controller.dragMoved($0) }
        view.onEnd = { controller.dragEnded() }
        view.onClick = onClick
    }
}

final class DragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var onStart: (() -> Void)?
    var onMove: ((NSSize) -> Void)?
    var onEnd: (() -> Void)?
    var onClick: (() -> Void)?
    private var start = NSPoint.zero
    private var dragging = false
    override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; dragging = false }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let delta = NSSize(width: point.x - start.x, height: point.y - start.y)
        guard dragging || hypot(delta.width, delta.height) > 3 else { return }
        if !dragging { dragging = true; onStart?() }
        onMove?(delta)
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { onEnd?() } else { onClick?() }
        dragging = false
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
