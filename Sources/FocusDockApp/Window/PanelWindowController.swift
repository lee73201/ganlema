import AppKit
import Combine
import SwiftUI
import FocusDockCore

enum AppTheme: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
    var appearance: NSAppearance? {
        switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

struct TaskEditorSession: Identifiable {
    let id = UUID()
    let item: TodoItem?
    var draft: TaskDraft { item.map(TaskDraft.init(item:)) ?? TaskDraft() }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        (windowController as? PanelWindowController)?.escape()
    }
}

@MainActor
final class PanelWindowController: NSWindowController, ObservableObject {
    let repository: TaskRepository
    let habits: HabitRepository
    @Published private(set) var interaction = PanelInteraction()
    @Published private(set) var editor: TaskEditorSession?
    @Published private(set) var editingHabit: Habit?
    var hasEditor: Bool { editor != nil || editingHabit != nil }
    @Published var errorMessage: String?
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "theme"); window?.appearance = theme.appearance }
    }

    private var openTimer: Task<Void, Never>?
    private var closeTimer: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuTrackingDepth = 0
    private var collapseAfterMenu = false
    private var displayID: String?
    private var placement = FocusDockCore.WindowPlacement()
    private var dragOrigin: NSPoint?
    private var composerFocused = false
    private var materialView: PanelMaterialView<DockView>?
    private let collapsedSize = NSSize(width: 176, height: 50)
    private let expandedSize = NSSize(width: 368, height: 506)
    private let defaults: UserDefaults

    init(repository: TaskRepository, habits: HabitRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.habits = habits
        self.defaults = defaults
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        super.init(window: nil)
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "干了吗"
        panel.identifier = NSUserInterfaceItemIdentifier("FocusDock.panel")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = theme.appearance
        window = panel
        let host = TrackingHostingView(rootView: DockView(controller: self, repository: repository, habits: habits))
        host.sizingOptions = []
        host.onEnter = { [weak self] in self?.send(.enter) }
        host.onLeave = { [weak self] in self?.send(.leave) }
        let material = PanelMaterialView(host: host)
        material.setExpanded(false)
        materialView = material
        panel.contentView = material
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restoreForAvailableScreen() }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.menuTrackingDepth += 1
                    self.send(.menuTracking(true))
                }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                    if self.menuTrackingDepth == 0 {
                        self.send(self.window?.frame.contains(NSEvent.mouseLocation) == true ? .enter : .leave)
                        self.send(.menuTracking(false))
                        if self.collapseAfterMenu {
                            self.collapseAfterMenu = false
                            self.send(.collapse)
                        }
                    }
                }
            }
        ]
        restoreForAvailableScreen()
    }
    required init?(coder: NSCoder) { fatalError("Use init(repository:)") }

    deinit {
        openTimer?.cancel()
        closeTimer?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func showDock() { window?.orderFrontRegardless() }
    func reveal() { send(.reveal); window?.makeKeyAndOrderFront(nil) }
    func togglePin() { send(.click); if interaction.isPinned { window?.makeKeyAndOrderFront(nil) } }
    func escape() { if hasEditor { endEditing() } else { collapse() } }
    func collapse() {
        guard !hasEditor else { return }
        composerFocused = false
        syncEditingState()
        if interaction.isMenuTracking { collapseAfterMenu = true } else { send(.collapse) }
    }

    private func send(_ event: PanelInteraction.Event) {
        let wasExpanded = interaction.isExpanded
        let effect = interaction.handle(event)
        switch effect {
        case .cancelTimers: cancelTimers()
        case .scheduleOpen:
            cancelTimers()
            openTimer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(PanelInteraction.hoverDelay)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.send(.hoverElapsed)
            }
        case .scheduleClose:
            cancelTimers()
            closeTimer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(PanelInteraction.collapseDelay)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.send(.collapseElapsed)
            }
        case .none: break
        }
        if wasExpanded != interaction.isExpanded { applyFrame() }
    }

    private func cancelTimers() { openTimer?.cancel(); closeTimer?.cancel(); openTimer = nil; closeTimer = nil }

    func beginEditing(_ item: TodoItem? = nil) {
        editor = TaskEditorSession(item: item)
        editingHabit = nil
        syncEditingState()
        window?.makeKeyAndOrderFront(nil)
    }
    func endEditing() { editor = nil; editingHabit = nil; syncEditingState() }
    func setComposerFocused(_ focused: Bool) { composerFocused = focused; syncEditingState() }
    private func syncEditingState() { send(.editing(hasEditor || composerFocused)) }
    func beginEditingHabit(_ habit: Habit) {
        editor = nil
        editingHabit = habit
        syncEditingState()
        window?.makeKeyAndOrderFront(nil)
    }
    func saveHabit(_ habit: Habit, name: String) {
        do { try habits.rename(habit, name: name); endEditing() }
        catch { errorMessage = error.localizedDescription }
    }
    func addHabit(_ name: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do { try habits.add(name: name); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func addTask(_ title: String) -> Bool {
        do { try repository.add(TaskDraft(title: title)); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func toggleHabit(_ habit: Habit, date: Date) { perform { try habits.toggle(habit, on: date) } }
    func deleteHabit(_ habit: Habit) { perform { try habits.delete(habit) } }
    func save(_ draft: TaskDraft, item: TodoItem?) {
        do {
            if let item { try repository.update(item, with: draft) } else { try repository.add(draft) }
            endEditing()
        } catch { errorMessage = error.localizedDescription }
    }
    func toggle(_ item: TodoItem) { perform { try repository.toggleCompletion(item) } }
    func delete(_ item: TodoItem) { perform { try repository.delete(item) } }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    func dragBegan() { dragOrigin = window?.frame.origin; send(.dragging(true)) }
    func dragMoved(_ delta: NSSize) {
        guard let origin = dragOrigin else { return }
        window?.setFrameOrigin(NSPoint(x: origin.x + delta.width, y: origin.y + delta.height))
    }
    func dragEnded() {
        dragOrigin = nil
        guard let window else { return }
        let screen = NSScreen.screens.max { a, b in
            area(a.visibleFrame.intersection(window.frame)) < area(b.visibleFrame.intersection(window.frame))
        }
        if let screen {
            displayID = screen.focusDockID
            placement = FocusDockCore.WindowPlacement(topRight: NSPoint(x: window.frame.maxX, y: window.frame.maxY), in: screen.visibleFrame)
            applyFrame()
            // Persist the clamped anchor, so the next hover does not jump after an offscreen drag.
            placement = FocusDockCore.WindowPlacement(topRight: NSPoint(x: window.frame.maxX, y: window.frame.maxY), in: screen.visibleFrame)
            savePosition()
        }
        send(.dragging(false))
        send(window.frame.contains(NSEvent.mouseLocation) ? .enter : .leave)
    }

    func moveToPointerScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        select(screen)
        reveal()
    }
    func resetPosition() { placement = FocusDockCore.WindowPlacement(); applyFrame(); savePosition() }

    private func restoreForAvailableScreen() {
        let wanted = displayID ?? defaults.string(forKey: "lastDisplay")
        guard let screen = NSScreen.screens.first(where: { $0.focusDockID == wanted }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        select(screen)
    }
    private func select(_ screen: NSScreen) {
        displayID = screen.focusDockID
        if let data = defaults.data(forKey: "placement.\(screen.focusDockID)"),
           let saved = try? JSONDecoder().decode(FocusDockCore.WindowPlacement.self, from: data) { placement = saved }
        else { placement = FocusDockCore.WindowPlacement() }
        applyFrame()
        defaults.set(screen.focusDockID, forKey: "lastDisplay")
    }
    private func applyFrame() {
        guard let screen = NSScreen.screens.first(where: { $0.focusDockID == displayID }) ?? NSScreen.main else { return }
        let size = interaction.isExpanded ? expandedSize : collapsedSize
        materialView?.setExpanded(interaction.isExpanded)
        window?.setFrame(placement.frame(size: size, in: screen.visibleFrame), display: true)
    }
    func savePosition() {
        guard let displayID, let data = try? JSONEncoder().encode(placement) else { return }
        defaults.set(data, forKey: "placement.\(displayID)")
        defaults.set(displayID, forKey: "lastDisplay")
    }
    private func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}

private extension NSScreen {
    var focusDockID: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return "display-\(number?.stringValue ?? localizedName)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

private final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var onEnter: (() -> Void)?
    var onLeave: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onLeave?() }
}
