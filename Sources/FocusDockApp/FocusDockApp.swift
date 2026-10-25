import AppKit
import FocusDockCore

@main
struct FocusDockApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var dock: PanelWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        do {
            // Optional developer-only isolation; normal launches always use the original stores.
            let environment = ProcessInfo.processInfo.environment
            let directory = environment["FOCUSDOCK_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            let repository = try TaskRepository(storeURL: directory?.appendingPathComponent("tasks.store"))
            let habits = try HabitRepository(storeURL: directory?.appendingPathComponent("habits.store"))
            let preferences = environment["FOCUSDOCK_PREFERENCES_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? .standard
            let controller = PanelWindowController(repository: repository, habits: habits, defaults: preferences)
            dock = controller
            installMenu()
            controller.showDock()
        } catch {
            let alert = NSAlert()
            alert.messageText = "干了吗无法打开本地数据"
            alert.informativeText = "数据未被重置。请检查磁盘空间或备份后重试。\n\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(title: "干了吗", action: nil, keyEquivalent: "")
        applicationItem.submenu = makeDockMenu()
        mainMenu.addItem(applicationItem)

        let editMenu = NSMenu(title: "编辑")
        for (title, action, key, shift) in [
            ("撤销", "undo:", "z", false), ("重做", "redo:", "z", true),
            ("剪切", "cut:", "x", false), ("复制", "copy:", "c", false),
            ("粘贴", "paste:", "v", false), ("全选", "selectAll:", "a", false)
        ] {
            let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            editMenu.addItem(item)
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "干了吗")
        item.menu = makeDockMenu()
        statusItem = item
    }

    private func makeDockMenu() -> NSMenu {
        let menu = NSMenu(title: "干了吗")
        menu.addItem(menuItem("打开干了吗", action: #selector(reveal), key: ""))
        menu.addItem(menuItem("移到鼠标所在屏幕", action: #selector(moveToCurrentScreen), key: ""))
        let sizingMenu = NSMenu(title: "窗口大小")
        sizingMenu.addItem(menuItem("放大窗口", action: #selector(enlargeWindow), key: "="))
        sizingMenu.addItem(menuItem("缩小窗口", action: #selector(reduceWindow), key: "-"))
        sizingMenu.addItem(menuItem("恢复默认窗口大小", action: #selector(resetWindowSize), key: ""))
        let sizingItem = NSMenuItem(title: "窗口大小", action: nil, keyEquivalent: "")
        sizingItem.submenu = sizingMenu
        menu.addItem(sizingItem)
        menu.addItem(menuItem("重置当前屏幕位置", action: #selector(resetPosition), key: ""))
        menu.addItem(menuItem("悬浮外观设置…", action: #selector(appearanceSettings), key: ","))
        menu.addItem(.separator())
        let themeMenu = NSMenu()
        for theme in AppTheme.allCases {
            let option = menuItem(theme.title, action: #selector(changeTheme(_:)), key: "")
            option.representedObject = theme.rawValue
            themeMenu.addItem(option)
        }
        let themeItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("退出干了吗", action: #selector(quit), key: "q"))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(changeTheme(_:)), let raw = menuItem.representedObject as? String {
            menuItem.state = dock?.theme.rawValue == raw ? .on : .off
        }
        return true
    }
    @objc private func appearanceSettings() { dock?.openAppearanceSettings() }
    @objc private func reveal() { dock?.reveal() }
    @objc private func moveToCurrentScreen() { dock?.moveToPointerScreen() }
    @objc private func enlargeWindow() { dock?.scaleWindow(1.15) }
    @objc private func reduceWindow() { dock?.scaleWindow(1 / 1.15) }
    @objc private func resetWindowSize() { dock?.resetWindowSize() }
    @objc private func resetPosition() { dock?.resetPosition() }
    @objc private func changeTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let theme = AppTheme(rawValue: raw) { dock?.theme = theme }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dock?.reveal()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { dock?.shutdown() }
}
