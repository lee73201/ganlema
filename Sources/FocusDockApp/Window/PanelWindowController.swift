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
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           let controller = windowController as? PanelWindowController,
           !controller.acceptsPointer(event.locationInWindow) {
            ignoresMouseEvents = true; return
        }
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
    @Published var floatingAppearance: FloatingAppearance {
        didSet {
            floatingAppearance.save(to: defaults)
            if oldValue.size(urgency: urgency) != floatingAppearance.size(urgency: urgency), let window, let screen = window.screen {
                if interaction.isExpanded { updateAnchor(from: window.frame, in: screen) }
                else {
                    let frame = FloatingGeometry.resizedCapsuleFrame(from: window.frame, size: capsuleWindowSize, screen: screen.visibleFrame)
                    placement = FocusDockCore.WindowPlacement(topRight: NSPoint(x: frame.maxX, y: frame.maxY), in: screen.visibleFrame)
                }
                savePosition()
            }
            applyFrame(); cancelTimers(); send(interaction.isInside ? .enter : .leave); refreshPointer()
        }
    }
    let focusTimer: FocusTimer
    private var settingsWindow: NSWindow?
    private var pointerTimer: AnyCancellable?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var expandsLeft = true
    private var expandsDown = true
    var nearestDeadlineTitle: String? { repository.items.filter { !$0.isCompleted && $0.dueDate != nil }.min { $0.dueDate! < $1.dueDate! }?.title }
    var capsuleRadius: CGFloat { let size = window?.frame.size ?? capsuleWindowSize; return floatingAppearance.radius(in: NSSize(width: max(0, size.width - 8), height: max(0, size.height - 8))) }
    private var capsuleWindowSize: NSSize { let size = floatingAppearance.size(urgency: urgency); return NSSize(width: size.width + 8, height: size.height + 8) }
    let speech = NativeSpeechService()
    let reminders = NativeReminderService()
    var hasEditor: Bool { editor != nil || editingHabit != nil || capture != nil || voicePresented }
    @Published var errorMessage: String?
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "theme"); applyFrame() }
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
    private var quickEditors = Set<UUID>()
    private var materialView: PanelMaterialView<DockView>?
    private var pendingUrgency = DeadlineUrgency.normal
    private var subscriptions = Set<AnyCancellable>()
    private var wakeObserver: NSObjectProtocol?
    private let defaults: UserDefaults

    init(repository: TaskRepository, habits: HabitRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.habits = habits
        self.defaults = defaults
        floatingAppearance = FloatingAppearance.load(from: defaults)
        focusTimer = FocusTimer(defaults: defaults)
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
        panel.initialFirstResponder = host
        host.onEnter = { [weak self] in self?.refreshPointer() }
        host.onLeave = { [weak self] in self?.refreshPointer() }
        let material = PanelMaterialView(host: host)
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
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in Task { @MainActor in self?.refreshPointer() } }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in self?.refreshPointer() }; return event
        }
        pointerTimer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refreshPointer() }
        repository.$items.sink { [weak self] items in
            if let self, let session = self.focusTimer.session, !items.contains(where: { $0.id == session.taskID && !$0.isCompleted }) { self.focusTimer.stop() }
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
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        openTimer?.cancel()
        closeTimer?.cancel()
        voiceStartTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func showDock() { window?.orderFrontRegardless() }
    func reveal() { send(.reveal); window?.makeKeyAndOrderFront(nil) }
    func togglePin() {
        if !interaction.isExpanded && !floatingAppearance.clickToPin { send(.enter); send(.hoverElapsed); window?.makeKeyAndOrderFront(nil); return }
        send(.click); if interaction.isPinned { window?.makeKeyAndOrderFront(nil) }
    }
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
                do { try await Task.sleep(for: .seconds(self?.floatingAppearance.normalized.hoverDelay ?? PanelInteraction.hoverDelay)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.send(.hoverElapsed)
            }
        case .scheduleClose:
            cancelTimers()
            closeTimer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(self?.floatingAppearance.normalized.collapseDelay ?? PanelInteraction.collapseDelay)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.send(.collapseElapsed)
            }
        case .none: break
        }
        if wasExpanded != interaction.isExpanded {
            if interaction.isExpanded, let frame = window?.frame, let screen = window?.screen {
                expandsLeft = frame.midX >= screen.visibleFrame.midX
                expandsDown = frame.midY >= screen.visibleFrame.midY
            }
            applyFrame(animated: true)
        }
        applyPendingUrgency()
        if ProcessInfo.processInfo.environment["FOCUSDOCK_DEBUG_INTERACTION"] == "1" {
            window?.setAccessibilityHelp("inside=\(interaction.isInside) pinned=\(interaction.isPinned) editing=\(interaction.isEditing) dragging=\(interaction.isDragging) menu=\(interaction.isMenuTracking) depth=\(menuTrackingDepth) event=\(String(describing: event))")
        }
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
    func setQuickEditing(_ id: UUID, active: Bool) { if active { quickEditors.insert(id) } else { quickEditors.remove(id) }; syncEditingState() }
    private func syncEditingState() { send(.editing(hasEditor || composerFocused || !quickEditors.isEmpty)) }
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
    func quickUpdate(_ item: TodoItem, title: String? = nil, dueDate: Date?? = nil, priority: TaskPriority? = nil) {
        var draft = TaskDraft(item: item)
        if let title { draft.title = title }; if let dueDate { draft.dueDate = dueDate }; if let priority { draft.priority = priority }
        do {
            try repository.update(item, with: draft)
            if dueDate != nil, let due = draft.dueDate, due > .now, !draft.reminderOffsets.isEmpty { Task { [weak self] in await self?.reminders.enable() } }
        } catch { errorMessage = error.localizedDescription }
    }
    func toggle(_ item: TodoItem) {
        perform { try repository.toggleCompletion(item) }
        if item.isCompleted && focusTimer.session?.taskID == item.id { focusTimer.stop() }
    }
    func delete(_ item: TodoItem) {
        let id = item.id; perform { try repository.delete(item) }
        if !repository.items.contains(where: { $0.id == id }) && focusTimer.session?.taskID == id { focusTimer.stop() }
    }
    func startFocus(_ item: TodoItem, minutes: Int) { focusTimer.start(item, minutes: minutes) }
    func openAppearanceSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 740), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "悬浮外观 · 干了吗"; panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 580)
        let host = NSHostingView(rootView: AppearanceSettingsView(controller: self))
        let glass = PanelMaterialView(host: host); glass.configure(expanded: true, appearance: floatingAppearance)
        panel.contentView = glass; panel.center(); settingsWindow = panel
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func acceptsPointer(_ local: NSPoint) -> Bool {
        guard let window else { return false }
        if interaction.isExpanded { return FloatingGeometry.contains(local, size: window.frame.size, radius: 18) }
        return FloatingGeometry.contains(NSPoint(x: local.x - 4, y: local.y - 4), size: NSSize(width: window.frame.width - 8, height: window.frame.height - 8), radius: capsuleRadius)
    }
    private func refreshPointer() {
        guard let window, !interaction.isDragging else { return }
        let point = NSEvent.mouseLocation
        let local = NSPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        let inside = acceptsPointer(local)
        // A borderless transparent NSPanel is rectangular at the window-server level.
        // Polling independently lets rounded empty corners pass through, then re-enables on entry.
        window.ignoresMouseEvents = !inside
        if inside != interaction.isInside { send(inside ? .enter : .leave) }
        if ProcessInfo.processInfo.environment["FOCUSDOCK_DEBUG_INTERACTION"] == "1" {
            window.setAccessibilityHelp("inside=\(interaction.isInside) pinned=\(interaction.isPinned) editing=\(interaction.isEditing) dragging=\(interaction.isDragging) menu=\(interaction.isMenuTracking) depth=\(menuTrackingDepth) pointer=\(point) local=\(local) frame=\(window.frame)")
        }
    }
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
            var frame = window.frame
            if floatingAppearance.edgeSnap { frame = FloatingGeometry.snapped(frame, in: screen.visibleFrame) }
            if interaction.isExpanded {
                expandsLeft = frame.midX >= screen.visibleFrame.midX
                expandsDown = frame.midY >= screen.visibleFrame.midY
                let capsule = FloatingGeometry.capsuleFrame(attachedTo: frame, size: capsuleWindowSize, screen: screen.visibleFrame)
                placement = FocusDockCore.WindowPlacement(topRight: NSPoint(x: capsule.maxX, y: capsule.maxY), in: screen.visibleFrame)
            } else { updateAnchor(from: frame, in: screen) }
            applyFrame()
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
        updateAnchor(from: window.frame, in: screen)
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
    private func updateAnchor(from frame: NSRect, in screen: NSScreen) {
        let size = capsuleWindowSize
        let point = interaction.isExpanded ? NSPoint(x: expandsLeft ? frame.maxX : frame.minX + size.width, y: expandsDown ? frame.maxY : frame.minY + size.height) : NSPoint(x: frame.maxX, y: frame.maxY)
        placement = FocusDockCore.WindowPlacement(topRight: point, in: screen.visibleFrame)
    }
    private func applyFrame(animated: Bool = false) {
        guard let screen = NSScreen.screens.first(where: { $0.focusDockID == displayID }) ?? NSScreen.main else { return }
        guard let window else { return }
        let size = interaction.isExpanded ? PanelSizePreference.effective(manual: manualSize, urgency: urgency, visibleSize: screen.visibleFrame.size) : capsuleWindowSize
        applyingFrame = true
        if interaction.isExpanded {
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: min(PanelSizePreference.minimum.width, screen.visibleFrame.width), height: min(PanelSizePreference.minimum.height, screen.visibleFrame.height))
            window.maxSize = screen.visibleFrame.size
        } else {
            window.styleMask.remove(.resizable)
            window.minSize = .zero; window.maxSize = screen.visibleFrame.size
        }
        let capsule = placement.frame(size: capsuleWindowSize, in: screen.visibleFrame)
        var target = capsule
        if interaction.isExpanded {
            target = FloatingGeometry.expandedFrame(capsule: capsule, size: size, screen: screen.visibleFrame, expandLeft: expandsLeft, expandDown: expandsDown)
        }
        window.appearance = interaction.isExpanded ? theme.appearance : floatingAppearance.appAppearance
        window.hasShadow = interaction.isExpanded || floatingAppearance.shadow == .standard
        // Keep geometry and the material's native layer mask in the same transaction.
        // A short AppKit animation interpolates the actual panel frame, not just SwiftUI content.
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                window.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in Task { @MainActor in
                guard let self else { return }; self.materialView?.configure(expanded: self.interaction.isExpanded, appearance: self.floatingAppearance)
            } }
        } else { window.setFrame(target, display: true) }
        materialView?.configure(expanded: interaction.isExpanded, appearance: floatingAppearance)
        window.invalidateShadow()
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
    override var acceptsFirstResponder: Bool { true }
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
