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

struct CaptureSession: Identifiable {
    let id = UUID()
    let input: String
    let cards: [ParsedTask]
}

struct TaskEditorSession: Identifiable {
    let id = UUID()
    let item: TodoItem?
    var draft: TaskDraft { item.map(TaskDraft.init(item:)) ?? TaskDraft() }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private func handleSizingShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command || modifiers == [.command, .shift],
              let controller = windowController as? PanelWindowController else { return false }
        switch event.charactersIgnoringModifiers {
        case "=", "+": controller.scaleWindow(1.15); return true
        case "-": controller.scaleWindow(1 / 1.15); return true
        default: return false
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleSizingShortcut(event) || super.performKeyEquivalent(with: event)
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && handleSizingShortcut(event) { return }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) {
        (windowController as? PanelWindowController)?.escape()
    }
}

@MainActor
final class PanelWindowController: NSWindowController, ObservableObject, NSWindowDelegate {
    let repository: TaskRepository
    let habits: HabitRepository
    @Published private(set) var interaction = PanelInteraction()
    @Published private(set) var editor: TaskEditorSession?
    @Published private(set) var editingHabit: Habit?
    @Published private(set) var capture: CaptureSession?
    @Published private(set) var voicePresented = false
    @Published private(set) var captureSaved = UUID()
    @Published private(set) var urgency = DeadlineUrgency.normal
    @Published var deadlineGrowthEnabled: Bool {
        didSet { defaults.set(deadlineGrowthEnabled, forKey: "deadlineGrowthEnabled"); updateUrgency() }
    }
    let speech = NativeSpeechService()
    let reminders = NativeReminderService()
    var hasEditor: Bool { editor != nil || editingHabit != nil || capture != nil || voicePresented }
    @Published var errorMessage: String?
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "theme"); window?.appearance = theme.appearance }
    }

    private var openTimer: Task<Void, Never>?
    private var closeTimer: Task<Void, Never>?
    private var voiceStartTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuTrackingDepth = 0
    private var collapseAfterMenu = false
    private var displayID: String?
    private var placement = FocusDockCore.WindowPlacement()
    private var dragOrigin: NSPoint?
    private var resizeOrigin: NSRect?
    private var manualSize: PanelSizePreference?
    private var applyingFrame = false
    private var nativeResizeActive = false
    private var composerFocused = false
    private var materialView: PanelMaterialView<DockView>?
    private var pendingUrgency = DeadlineUrgency.normal
    private var subscriptions = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?
    private let defaults: UserDefaults

    init(repository: TaskRepository, habits: HabitRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.habits = habits
        self.defaults = defaults
        deadlineGrowthEnabled = defaults.object(forKey: "deadlineGrowthEnabled") as? Bool ?? true
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
        panel.delegate = self
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
        repository.$items.sink { [weak self] items in
            self?.reminders.update(items: items)
            self?.updateUrgency(items: items)
        }.store(in: &subscriptions)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.updateUrgency()
            if let self { self.reminders.update(items: self.repository.items) }
        }.store(in: &subscriptions)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateUrgency()
                if let self { self.reminders.update(items: self.repository.items) }
            }
        }
        reminders.onOpen = { [weak self] id in
            self?.reveal()
            if let item = self?.repository.items.first(where: { $0.id == id && !$0.isCompleted }) { self?.beginEditing(item) }
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(repository:)") }

    deinit {
        openTimer?.cancel()
        closeTimer?.cancel()
        voiceStartTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
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
        applyPendingUrgency()
    }

    private func cancelTimers() { openTimer?.cancel(); closeTimer?.cancel(); openTimer = nil; closeTimer = nil }

    func beginEditing(_ item: TodoItem? = nil) {
        editor = TaskEditorSession(item: item)
        editingHabit = nil
        syncEditingState()
        window?.makeKeyAndOrderFront(nil)
    }
    func endEditing() {
        editor = nil; editingHabit = nil; capture = nil; voicePresented = false
        voiceStartTask?.cancel(); voiceStartTask = nil
        speech.cancel()
        syncEditingState()
    }
    func beginCapture(_ input: String) {
        let cards = LocalTaskParser().parse(input)
        guard !cards.isEmpty else { return }
        speech.cancel(); voicePresented = false; editor = nil; editingHabit = nil
        capture = CaptureSession(input: input, cards: cards)
        composerFocused = false; syncEditingState(); window?.makeKeyAndOrderFront(nil)
    }
    func beginVoiceCapture() {
        editor = nil; editingHabit = nil; capture = nil; voicePresented = true
        composerFocused = false; syncEditingState(); window?.makeKeyAndOrderFront(nil)
        voiceStartTask?.cancel()
        voiceStartTask = Task { [weak self] in
            guard let self, self.voicePresented, !Task.isCancelled else { return }
            do { try await self.speech.start() } catch { /* displayed inline by speech service */ }
        }
    }
    func confirmCapture(_ cards: [ParsedTask]) {
        do {
            try repository.addBatch(cards.map(\.draft))
            let wantsReminders = cards.contains { ($0.draft.dueDate.map { $0 > Date() } ?? false) && !$0.draft.reminderOffsets.isEmpty }
            endEditing(); captureSaved = UUID()
            if wantsReminders { Task { [weak self] in await self?.reminders.enable() } }
        } catch { errorMessage = error.localizedDescription }
    }
    private func updateUrgency(items: [TodoItem]? = nil) {
        pendingUrgency = deadlineGrowthEnabled ? DeadlineUrgency.evaluate(dueDates: (items ?? repository.items).filter { !$0.isCompleted }.compactMap(\.dueDate)) : .normal
        applyPendingUrgency()
    }
    private func applyPendingUrgency() {
        guard urgency != pendingUrgency, !interaction.isEditing, !interaction.isDragging, !interaction.isMenuTracking else { return }
        urgency = pendingUrgency
        applyFrame()
    }
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
    func removeCheckIn(_ record: HabitCheckIn) { perform { try habits.removeCheckIn(record) } }
    func deleteHabit(_ habit: Habit) { perform { try habits.delete(habit) } }
    func save(_ draft: TaskDraft, item: TodoItem?) {
        do {
            if let item { try repository.update(item, with: draft) } else { try repository.add(draft) }
            endEditing()
            if let due = draft.dueDate, due > .now, !draft.reminderOffsets.isEmpty { Task { [weak self] in await self?.reminders.enable() } }
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
            if displayID != screen.focusDockID { loadWindowSize(for: screen) }
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
    func resizeBegan() {
        guard interaction.isExpanded else { return }
        resizeOrigin = window?.frame; send(.dragging(true))
    }
    func resizeMoved(_ delta: NSSize) {
        guard let initial = resizeOrigin, let screen = window?.screen ?? NSScreen.main else { return }
        applyingFrame = true
        window?.setFrame(PanelSizePreference.resizedFrame(from: initial, delta: delta, in: screen.visibleFrame), display: true)
        applyingFrame = false
    }
    func resizeEnded() {
        guard resizeOrigin != nil else { return }
        resizeOrigin = nil
        rememberWindowSize()
        send(.dragging(false))
        send(window?.frame.contains(NSEvent.mouseLocation) == true ? .enter : .leave)
    }
    func windowWillStartLiveResize(_ notification: Notification) {
        guard interaction.isExpanded, !applyingFrame else { return }
        nativeResizeActive = true; send(.dragging(true))
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        guard nativeResizeActive else { return }
        nativeResizeActive = false; rememberWindowSize(); send(.dragging(false))
        send(window?.frame.contains(NSEvent.mouseLocation) == true ? .enter : .leave)
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !applyingFrame, interaction.isExpanded else { return frameSize }
        return PanelSizePreference(frameSize).constrained(to: (sender.screen ?? NSScreen.main)?.visibleFrame.size ?? frameSize)
    }
    private func rememberWindowSize() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        displayID = screen.focusDockID
        manualSize = PanelSizePreference(window.frame.size)
        if let data = try? JSONEncoder().encode(manualSize) { defaults.set(data, forKey: "expandedSize.\(screen.focusDockID)") }
        placement = FocusDockCore.WindowPlacement(topRight: NSPoint(x: window.frame.maxX, y: window.frame.maxY), in: screen.visibleFrame)
        savePosition(); applyFrame()
    }
    private func loadWindowSize(for screen: NSScreen) {
        manualSize = defaults.data(forKey: "expandedSize.\(screen.focusDockID)").flatMap { try? JSONDecoder().decode(PanelSizePreference.self, from: $0) }
    }
    func scaleWindow(_ factor: CGFloat) {
        if !interaction.isExpanded { reveal() }
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let size = PanelSizePreference(width: window.frame.width * factor, height: window.frame.height * factor).constrained(to: screen.visibleFrame.size)
        manualSize = PanelSizePreference(size)
        if let displayID, let data = try? JSONEncoder().encode(manualSize) { defaults.set(data, forKey: "expandedSize.\(displayID)") }
        applyFrame()
    }
    func resetWindowSize() {
        manualSize = nil
        if let displayID { defaults.removeObject(forKey: "expandedSize.\(displayID)") }
        applyFrame()
    }
    func resetPosition() { placement = FocusDockCore.WindowPlacement(); applyFrame(); savePosition() }

    private func restoreForAvailableScreen() {
        let wanted = displayID ?? defaults.string(forKey: "lastDisplay")
        guard let screen = NSScreen.screens.first(where: { $0.focusDockID == wanted }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        select(screen)
    }
    private func select(_ screen: NSScreen) {
        displayID = screen.focusDockID
        loadWindowSize(for: screen)
        if let data = defaults.data(forKey: "placement.\(screen.focusDockID)"),
           let saved = try? JSONDecoder().decode(FocusDockCore.WindowPlacement.self, from: data) { placement = saved }
        else { placement = FocusDockCore.WindowPlacement() }
        applyFrame()
        defaults.set(screen.focusDockID, forKey: "lastDisplay")
    }
    private func applyFrame() {
        guard let screen = NSScreen.screens.first(where: { $0.focusDockID == displayID }) ?? NSScreen.main else { return }
        guard let window else { return }
        let size = interaction.isExpanded ? PanelSizePreference.effective(manual: manualSize, urgency: urgency, visibleSize: screen.visibleFrame.size) : urgency.capsuleSize
        applyingFrame = true
        if interaction.isExpanded {
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: min(PanelSizePreference.minimum.width, screen.visibleFrame.width), height: min(PanelSizePreference.minimum.height, screen.visibleFrame.height))
            window.maxSize = screen.visibleFrame.size
        } else {
            window.styleMask.remove(.resizable)
            window.minSize = .zero; window.maxSize = screen.visibleFrame.size
        }
        materialView?.setExpanded(interaction.isExpanded)
        window.setFrame(placement.frame(size: size, in: screen.visibleFrame), display: true)
        applyingFrame = false
    }
    func shutdown() { voiceStartTask?.cancel(); speech.cancel(); savePosition() }
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
