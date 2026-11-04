import SwiftUI
import FocusDockCore

struct DockStyle {
    static let accent = Color(red: 0.44, green: 0.59, blue: 0.51)
    static let inset: CGFloat = 16
    static var separator: some View { Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5).allowsHitTesting(false) }
    static func deadlineColor(in scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.70, blue: 0.45) : Color(red: 0.55, green: 0.28, blue: 0.10)
    }
}

enum DockTab: String, CaseIterable, Identifiable {
    case tasks = "待办", completed = "已完成", habits = "打卡"
    var id: String { rawValue }
}

struct DockView: View {
    @ObservedObject var controller: PanelWindowController
    @ObservedObject var repository: TaskRepository
    @ObservedObject var habits: HabitRepository
    @State private var tab = DockTab.tasks
    @State private var taskInput = ""
    @State private var habitInput = ""
    @State private var weekOffset = 0
    @FocusState private var composerFocused: Bool
    @State private var opacityControlsVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if controller.interaction.isExpanded { expanded } else { capsule }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: controller.interaction.isExpanded ? 18 : controller.capsuleRadius)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5).allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if controller.interaction.isExpanded {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8)).foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 18, height: 18).overlay(ResizeRegion(controller: controller))
                    .padding(2).help("拖动调整大小 · 双击恢复默认大小")
                    .accessibilityLabel("调整窗口大小")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: controller.interaction.isExpanded ? 18 : controller.capsuleRadius))
        .preferredColorScheme(controller.interaction.isExpanded ? controller.theme.colorScheme : (controller.floatingAppearance.shape == .island ? .dark : controller.floatingAppearance.scheme))
        .onChange(of: controller.interaction.isPinned) { _, pinned in
            if !pinned { opacityControlsVisible = false }
        }
        .onChange(of: composerFocused) { _, value in controller.setComposerFocused(value) }
        .onChange(of: controller.captureSaved) { _, saved in
            if saved?.host == .panel { taskInput = ""; tab = .tasks }
        }
        .alert("操作未完成", isPresented: Binding(get: { controller.errorMessage != nil && controller.workspaceWindow?.isKeyWindow != true }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("好", role: .cancel) { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
    }

    private var capsule: some View {
        LiveCapsuleView(controller: controller, repository: repository, timer: controller.focusTimer)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(DragRegion(controller: controller, onClick: controller.openWorkspaceFromDock).frame(maxWidth: .infinity, maxHeight: .infinity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controller.interaction.isQuiet ? "干了吗，安静胶囊" : "干了吗，\(repository.items.filter { !$0.isCompleted }.count) 项待办")
        .accessibilityAddTraits(.isButton).accessibilityAction { controller.openWorkspaceFromDock() }
        .help(controller.interaction.isQuiet ? "安静胶囊 · 点击打开主窗口" : "悬停速览 · 点击打开主窗口 · 拖动移动")
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            if controller.hasPanelEditor && (controller.editor != nil || controller.capture != nil) {
                Color.clear.frame(height: 16)
                    .overlay(DragRegion(controller: controller))
                    .help("拖动以移动编辑窗口")
            } else {
                VStack(spacing: 10) {
                    clockHeader
                    if controller.interaction.isPinned && opacityControlsVisible { opacityControls }
                    progress
                    tabs
                }.padding(.horizontal, DockStyle.inset).padding(.top, 14).padding(.bottom, 8)
            }
            if controller.hasPanelEditor {
                EditingFlowView(controller: controller)
            } else {
                FocusTimerBar(timer: controller.focusTimer, controller: controller)
                Group {
                    if tab == .habits { HabitListView(habits: habits, controller: controller, weekOffset: $weekOffset) }
                    else if tab == .completed { CompletionListView(repository: repository, habits: habits, controller: controller) }
                    else { taskList }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: tab)
                DeletionUndoBar(undo: controller.deletionUndo, controller: controller)
                composer
            }
        }
    }

    private var clockHeader: some View {
        HStack(alignment: .top, spacing: 4) {
            TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60), by: 60)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text("干了吗").font(.system(size: 18, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 5) {
                        Text(Self.timeFormatter.string(from: context.date)).monospacedDigit()
                        Text("·").accessibilityHidden(true)
                        Text(context.date, format: .dateTime.month().day().weekday(.abbreviated)).lineLimit(1)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(DragRegion(controller: controller, onClick: controller.openWorkspaceFromDock).frame(maxWidth: .infinity, maxHeight: .infinity))
            .help("点击打开主窗口 · 拖动以移动悬浮窗")
            Button(action: controller.openWorkspaceFromDock) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).help("打开主窗口").accessibilityLabel("打开主窗口")
            Button { controller.togglePin() } label: {
                Image(systemName: controller.interaction.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(controller.interaction.isPinned ? DockStyle.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(controller.interaction.isPinned ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(controller.interaction.isPinned ? "取消锁定" : "锁定展开")
                .accessibilityValue(controller.interaction.isPinned ? "已固定" : "未固定")
                .help(controller.interaction.isPinned ? "已固定：点击解锁，移开鼠标后自动收起" : "点击固定：移开鼠标仍保持展开")
            if controller.interaction.isPinned {
                Button {
                    opacityControlsVisible.toggle()
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                        .background(opacityControlsVisible ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
                    .accessibilityLabel("固定面板透明度")
                    .accessibilityValue(opacityControlsVisible ? "已展开" : "已收起")
                    .help("调整固定面板的背景透明度")
            }
            NotificationControl(reminders: controller.reminders, controller: controller)
            Menu {
                Button("外观设置…") { controller.openAppearanceSettings() }
                Button(controller.interaction.isQuiet ? "关闭安静胶囊" : "开启安静胶囊") { controller.toggleQuietMode() }
                    .disabled(!controller.canToggleQuietMode)
                Divider()
                Picker("外观", selection: $controller.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Divider()
                Toggle("DDL 临近时增大窗口", isOn: $controller.deadlineGrowthEnabled)
                Button("启用系统提醒") { Task { await controller.reminders.enableOrOpenSettings() } }
                Button("打开主窗口", systemImage: "macwindow", action: controller.openWorkspaceFromDock)
                Button("收起窗口", systemImage: "minus") { controller.collapse() }.disabled(controller.hasPanelEditor)
                Button("移到鼠标所在屏幕") { controller.moveToPointerScreen() }
                Button("放大窗口") { controller.scaleWindow(1.15) }
                Button("缩小窗口") { controller.scaleWindow(1 / 1.15) }
                Button("恢复默认窗口大小") { controller.resetWindowSize() }
                Button("重置当前屏幕位置") { controller.resetPosition() }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 28, height: 28)
            .accessibilityLabel("设置")
        }
    }

    private var opacityControls: some View {
        HStack(spacing: 8) {
            if controller.reduceTransparency {
                Text("系统已开启「降低透明度」").foregroundStyle(.secondary)
            } else {
                Text("背景不透明度").foregroundStyle(.secondary)
                Slider(value: Binding(get: { controller.pinnedBackdropOpacity }, set: controller.setPinnedBackdropOpacity),
                       in: PinnedBackdrop.range)
                    .controlSize(.small)
                    .accessibilityLabel("固定面板背景不透明度")
                Text("\(Int((controller.pinnedBackdropOpacity * 100).rounded()))%")
                    .monospacedDigit().frame(width: 34, alignment: .trailing)
            }
        }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = TaskDaySummary(items: repository.items, date: context.date)
            HStack(spacing: 8) {
                Text("今日完成").foregroundStyle(.secondary)
                Text("\(summary.completed)/\(summary.total)").monospacedDigit()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.12))
                        Capsule().fill(DockStyle.accent).frame(width: proxy.size.width * summary.fraction)
                    }
                }.frame(height: 3).accessibilityHidden(true)
                Text("\(summary.percentage)%").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 30, alignment: .trailing)
            }
            .font(.system(size: 11))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日完成 \(summary.completed) 项，共 \(summary.total) 项，\(summary.percentage)%")
            .help("统计今日到期、今日新建且无截止时间，以及今日完成的任务。")
        }
    }

    private var tabs: some View {
        Picker("任务页面", selection: $tab) {
            ForEach(DockTab.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }.pickerStyle(.segmented).labelsHidden().controlSize(.regular).tint(DockStyle.accent)
            .onChange(of: tab) { _, _ in composerFocused = false }
            .disabled(controller.hasPanelEditor)
    }

    private var taskList: some View {
        let items = repository.items.filter { !$0.isCompleted }
        return Group {
            if items.isEmpty {
                emptyState(symbol: "list.bullet", title: "暂时没有待办", subtitle: "在下方记下下一件事。")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        TaskRecommendationView(items: items, controller: controller, timer: controller.focusTimer)
                        ForEach(items) { item in TaskRowView(item: item, controller: controller) }
                    }.padding(.horizontal, DockStyle.inset)
                        .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
                }.scrollIndicators(.visible).scrollBounceBehavior(.basedOnSize).id(tab)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            DockStyle.separator
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField(tab == .habits ? "添加打卡习惯…" : "如：明天下午三点交报告…", text: tab == .habits ? $habitInput : $taskInput)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($composerFocused)
                    .onSubmit(addFromComposer)
                    .accessibilityLabel(tab == .habits ? "新增习惯名称" : "新增待办标题")
                Button { composerFocused = false; controller.beginVoiceCapture() } label: { Image(systemName: "mic").font(.system(size: 13)) }
                    .buttonStyle(.plain).frame(width: 24, height: 24)
                    .help("说出待办，再确认保存")
                    .accessibilityLabel("语音添加待办")
                Button(action: addFromComposer) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                        .foregroundStyle(DockStyle.accent)
                }.buttonStyle(.plain).accessibilityLabel(tab == .habits ? "添加习惯" : "添加待办")
            }.padding(.horizontal, DockStyle.inset).frame(height: 48)
        }
    }

    private func addFromComposer() {
        if tab == .habits {
            if controller.addHabit(habitInput) { habitInput = "" }
        } else if taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composerFocused = false
            controller.beginEditing()
        } else {
            composerFocused = false
            controller.beginCapture(taskInput)
        }
    }

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
