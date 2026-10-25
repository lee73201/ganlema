import AppKit
import SwiftUI

struct ResizeRegion: NSViewRepresentable {
    let controller: PanelWindowController
    func makeNSView(context: Context) -> ResizeHandleView { ResizeHandleView() }
    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.begin = { controller.resizeBegan() }
        view.move = { controller.resizeMoved($0) }
        view.end = { controller.resizeEnded() }
        view.reset = { controller.resetWindowSize() }
    }
}
final class ResizeHandleView: NSView {
    var begin: (() -> Void)?
    var move: ((NSSize) -> Void)?
    var end: (() -> Void)?
    var reset: (() -> Void)?
    private var initial = NSPoint.zero
    private var resizing = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        initial = screenPoint(for: event); resizing = false
        if event.clickCount == 2 { reset?() }
    }
    override func mouseDragged(with event: NSEvent) {
        let location = screenPoint(for: event)
        let delta = NSSize(width: location.x - initial.x, height: location.y - initial.y)
        guard resizing || hypot(delta.width, delta.height) > 2 else { return }
        if !resizing { resizing = true; begin?() }
        move?(delta)
    }
    override func mouseUp(with event: NSEvent) { if resizing { end?() }; resizing = false }
    private func screenPoint(for event: NSEvent) -> NSPoint {
        (event.window ?? window)?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func resetCursorRects() {
        if #available(macOS 15, *) { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all)) }
        else { addCursorRect(bounds, cursor: .crosshair) }
    }
}
