import AppKit
import Combine
import SwiftUI

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    private let dock: PanelWindowController
    private var themeUpdates: AnyCancellable?

    init(dock: PanelWindowController) {
        self.dock = dock
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init(window: window)
        window.title = "干了吗 · 主窗口"
        window.identifier = NSUserInterfaceItemIdentifier("FocusDock.workspace")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 620, height: 450)
        window.isReleasedWhenClosed = false
        window.delegate = self
        dock.workspaceWindow = window
        let host = NSHostingView(rootView: WorkspaceView(dock: dock, repository: dock.repository, habits: dock.habits))
        host.sizingOptions = []
        window.contentView = host
        window.center()
        themeUpdates = dock.$theme.sink { [weak window] theme in window?.appearance = theme.appearance }
    }

    required init?(coder: NSCoder) { fatalError("Use init(dock:)") }

    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if dock.editingHost == .workspace && dock.voicePresented { dock.endEditing() }
        Task { @MainActor [weak self] in
            guard self?.window?.isVisible == false else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
