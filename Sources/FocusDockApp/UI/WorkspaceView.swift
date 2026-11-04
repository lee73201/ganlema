import AppKit
import SwiftUI
import FocusDockCore

private enum WorkspacePage: String, CaseIterable, Identifiable {
    case today = "今天"
    case tasks = "全部待办"
    case completed = "已完成"
    case habits = "打卡"

    var id: Self { self }
    var canSearch: Bool { self == .today || self == .tasks }
    var symbol: String {
        switch self {
        case .today: return "clock"
        case .tasks: return "list.bullet"
        case .completed: return "checkmark.circle"
        case .habits: return "calendar"
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var dock: PanelWindowController
    @ObservedObject var repository: TaskRepository
    @ObservedObject var habits: HabitRepository
    @State private var page = WorkspacePage.today
    @State private var taskInput = ""
    @State private var habitInput = ""
    @State private var weekOffset = 0
    @State private var searchVisible = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var isEditing: Bool { dock.editingHost == .workspace }
    private var pending: [TodoItem] { repository.items.filter { !$0.isCompleted } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let agenda = TodayAgenda(items: repository.items, now: context.date)
            HStack(spacing: 0) {
                sidebar(todayCount: agenda.overdue.count + agenda.dueToday.count + agenda.addedToday.count)
                Rectangle().fill(.primary.opacity(0.09)).frame(width: 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    if isEditing {
                        EditingFlowView(controller: dock)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 20).padding(.top, 44)
                    } else {
                        header(date: context.date)
                        FocusTimerBar(timer: dock.focusTimer, controller: dock).padding(.horizontal, 12)
                        content(agenda)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        DeletionUndoBar(undo: dock.deletionUndo, controller: dock).padding(.horizontal, 12)
                        composer
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .environment(\.editorHost, .workspace)
        .preferredColorScheme(dock.theme.colorScheme)
        .onChange(of: dock.captureSaved) { _, saved in
            guard saved?.host == .workspace else { return }
            taskInput = ""
            clearSearch()
            if page != .today && page != .tasks { page = .tasks }
        }
        .onChange(of: page) { _, _ in clearSearch() }
        .alert("操作未完成", isPresented: Binding(
            get: { dock.errorMessage != nil && dock.workspaceWindow?.isKeyWindow == true },
            set: { if !$0 { dock.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { dock.errorMessage = nil }
        } message: {
            Text(dock.errorMessage ?? "")
        }
    }

    private func sidebar(todayCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(spacing: 4) {
                Image(nsImage: WorkspaceBrand.icon).resizable().scaledToFit()
                    .frame(width: 52, height: 52).accessibilityHidden(true)
                Text("干了吗").font(.system(size: 14, weight: .semibold))
            }.frame(maxWidth: .infinity).padding(.bottom, 20)
            ForEach(WorkspacePage.allCases) { destination in
                let count = destination == .today ? todayCount : destination == .tasks ? pending.count : nil
                Button { page = destination } label: {
                    HStack(spacing: 8) {
                        Image(systemName: destination.symbol)
                            .foregroundStyle(page == destination ? DockStyle.accent : .secondary)
                            .frame(width: 18).accessibilityHidden(true)
                        Text(destination.rawValue).fontWeight(page == destination ? .semibold : .regular)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 4)
                        if let count { Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 10).frame(height: 33).contentShape(Rectangle())
                    .background(page == destination ? DockStyle.accent.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain).accessibilityAddTraits(page == destination ? .isSelected : [])
                .accessibilityLabel(destination.rawValue)
                .accessibilityValue(count.map { "\($0) 项" } ?? "")
                .disabled(isEditing)
            }
            Spacer()
            DockStyle.separator.padding(.horizontal, 8).padding(.bottom, 5)
            Button { dock.openAppearanceSettings() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 18).accessibilityHidden(true)
                    Text("设置")
                    Spacer()
                }.padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.top, 50).padding(.bottom, 15)
        .frame(width: 164)
        .background(WorkspaceSidebarMaterial())
    }

    private func header(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.rawValue).font(.system(size: 30, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    if page == .today {
                        Text(date, format: .dateTime.month().day().weekday(.wide)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if page.canSearch {
                    Button {
                        if searchVisible { clearSearch() } else { searchVisible = true }
                    } label: {
                        Image(systemName: searchVisible ? "xmark" : "magnifyingglass")
                            .font(.system(size: 15)).frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(searchVisible ? "关闭搜索" : "搜索待办")
                    .accessibilityLabel(searchVisible ? "关闭搜索" : "搜索待办")
                    .keyboardShortcut("f", modifiers: .command)
                }
                Menu {
                    Button("展开悬浮面板") { dock.reveal() }
                    Button(dock.interaction.isQuiet ? "关闭安静胶囊" : "开启安静胶囊") { dock.toggleQuietMode() }
                        .disabled(!dock.canToggleQuietMode)
                    Divider()
                    Picker("外观", selection: $dock.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(.secondary)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 28, height: 28)
                    .accessibilityLabel("主窗口选项")
            }
            if searchVisible && page.canSearch {
                TextField("搜索标题、备注或类别", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("搜索待办")
                    .focused($searchFocused)
                    .onAppear { searchFocused = true }
                    .onExitCommand(perform: clearSearch)
            }
        }
        .padding(.horizontal, 26).padding(.top, 33).padding(.bottom, 14)
    }

    @ViewBuilder private func content(_ agenda: TodayAgenda) -> some View {
        switch page {
        case .today:
            let overdue = matching(agenda.overdue)
            let due = matching(agenda.dueToday)
            let added = matching(agenda.addedToday)
            VStack(spacing: 14) {
                TodayOverview(agenda: agenda).padding(.horizontal, 26)
                if overdue.isEmpty && due.isEmpty && added.isEmpty {
                    emptyTasks("今天没有待办", help: "后续事项和未排期的任务在「全部待办」。")
                } else {
                    taskScroll {
                        taskSection("已逾期", items: overdue, symbol: "exclamationmark.circle")
                        taskSection("今天到期", items: due, symbol: "calendar")
                        taskSection("今天新增 · 无截止", items: added, symbol: "plus.circle")
                    }
                }
            }
        case .tasks:
            let items = matching(pending)
            if items.isEmpty {
                emptyTasks("暂时没有待办", help: "用底部输入框记下下一件事。")
            } else {
                taskScroll {
                    if search.isEmpty { TaskRecommendationView(items: items, controller: dock, timer: dock.focusTimer) }
                    ForEach(items) { TaskRowView(item: $0, controller: dock) }
                }
            }
        case .completed:
            CompletionListView(repository: repository, habits: habits, controller: dock).padding(.horizontal, 10)
        case .habits:
            HabitListView(habits: habits, controller: dock, weekOffset: $weekOffset).padding(.horizontal, 10)
        }
    }

    private func taskScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, content: content)
                .padding(.horizontal, 26).padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .id(page)
    }

    @ViewBuilder private func taskSection(_ title: String, items: [TodoItem], symbol: String) -> some View {
        if !items.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title)
                Text("\(items.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.top, 10).padding(.bottom, 5)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            ForEach(items) { TaskRowView(item: $0, controller: dock) }
        }
    }

    private func emptyTasks(_ title: String, help: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: search.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 20)).accessibilityHidden(true)
            Text(search.isEmpty ? title : "没有匹配的待办").font(.system(size: 14, weight: .medium))
            Text(search.isEmpty ? help : "试试别的关键词。").font(.system(size: 12))
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            DockStyle.separator
            HStack(spacing: 12) {
                Button(action: submit) {
                    Image(systemName: "plus").font(.system(size: 14)).frame(width: 28, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(page == .habits ? "添加习惯" : "添加待办")
                TextField(page == .habits ? "添加打卡习惯…" : "添加待办…", text: page == .habits ? $habitInput : $taskInput)
                    .textFieldStyle(.plain).font(.system(size: 13)).onSubmit(submit)
                    .accessibilityLabel(page == .habits ? "新增习惯名称" : "新增待办标题")
                if page != .habits {
                    Button { dock.beginVoiceCapture(in: .workspace) } label: {
                        Image(systemName: "mic").font(.system(size: 14)).frame(width: 28, height: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("语音添加待办")
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8).frame(height: 38)
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 26).padding(.vertical, 12)
        }
    }

    private func submit() {
        if page == .habits {
            if dock.addHabit(habitInput) { habitInput = "" }
        } else if taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dock.beginEditing(in: .workspace)
        } else {
            dock.beginCapture(taskInput, in: .workspace)
        }
    }

    private func clearSearch() {
        searchVisible = false
        searchFocused = false
        search = ""
    }

    private func matching(_ items: [TodoItem]) -> [TodoItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedStandardContains(query) || $0.notes.localizedStandardContains(query)
                || ($0.category?.localizedStandardContains(query) ?? false)
        }
    }
}

private enum WorkspaceBrand {
    static let icon: NSImage = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) } ?? NSApplication.shared.applicationIconImage ?? NSImage()
}

private struct WorkspaceSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct TodayOverview: View {
    let agenda: TodayAgenda

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.primary.opacity(0.10), lineWidth: 5)
                    if agenda.progress.fraction > 0 {
                        Circle().trim(from: 0, to: agenda.progress.fraction)
                            .stroke(DockStyle.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text("\(agenda.progress.completed)/\(agenda.progress.total)").font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }.frame(width: 59, height: 59).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日进度").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("\(agenda.progress.percentage)%").font(.system(size: 25, weight: .semibold)).monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日进度 \(agenda.progress.completed) 项，共 \(agenda.progress.total) 项，\(agenda.progress.percentage)%")
            Rectangle().fill(.primary.opacity(0.10)).frame(width: 1, height: 48).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Label("最近截止", systemImage: "clock").font(.system(size: 12)).foregroundStyle(.secondary)
                if let task = agenda.nextDeadline, let date = task.dueDate {
                    Text(task.title).font(.system(size: 15, weight: .medium)).lineLimit(1).help(task.title)
                    Text(date, format: .dateTime.month().day().hour().minute()).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text("暂无即将到期的任务").font(.system(size: 14, weight: .medium)).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }
}
