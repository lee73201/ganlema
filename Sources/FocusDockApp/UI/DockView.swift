import SwiftUI
import FocusDockCore

struct DockStyle {
    static let accent = Color(red: 0.44, green: 0.59, blue: 0.51)
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
    @Namespace private var tabHighlight

    var body: some View {
        Group {
            if controller.interaction.isExpanded { expanded } else { capsule }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: controller.interaction.isExpanded ? 18 : 25)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: controller.interaction.isExpanded ? 18 : 25))
        .preferredColorScheme(controller.theme.colorScheme)
        .tint(DockStyle.accent)
        .onChange(of: composerFocused) { _, value in controller.setComposerFocused(value) }
        .onChange(of: repository.items.count) { old, new in if new > old { tab = .tasks } }
        .alert("操作未完成", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("好", role: .cancel) { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
    }

    private var capsule: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .regular)).foregroundStyle(DockStyle.accent)
            Text("干了吗").font(.system(size: 13, weight: .semibold))
            Text("\(repository.items.filter { !$0.isCompleted }.count)")
                .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(DragRegion(controller: controller, onClick: { controller.togglePin() }).frame(maxWidth: .infinity, maxHeight: .infinity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("干了吗，\(repository.items.filter { !$0.isCompleted }.count) 项待办")
        .accessibilityAddTraits(.isButton).accessibilityAction { controller.togglePin() }
        .help("悬停展开 · 点击锁定 · 拖动移动")
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                clockHeader
                progress
                tabs
            }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            if let session = controller.editor {
                TaskEditorView(session: session, controller: controller).id(session.id)
            } else if let habit = controller.editingHabit {
                HabitEditorView(habit: habit, controller: controller).id(habit.id)
            } else {
                Group {
                    if tab == .habits { habitList } else { taskList }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                composer
            }
        }
    }

    private var clockHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60), by: 60)) { context in
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.timeFormatter.string(from: context.date))
                        .font(.system(size: 34, weight: .light)).monospacedDigit()
                    Text(context.date, format: .dateTime.month().day().weekday(.wide))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(DragRegion(controller: controller).frame(maxWidth: .infinity, maxHeight: .infinity))
            .help("拖动以移动悬浮窗")
            Button { controller.togglePin() } label: {
                Image(systemName: controller.interaction.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12)).foregroundStyle(controller.interaction.isPinned ? DockStyle.accent : .secondary)
                    .frame(width: 24, height: 26)
            }.buttonStyle(.plain).accessibilityLabel(controller.interaction.isPinned ? "取消锁定" : "锁定展开")
            Menu {
                Picker("外观", selection: $controller.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Divider()
                Button("收起窗口", systemImage: "minus") { controller.collapse() }.disabled(controller.hasEditor)
                Button("移到鼠标所在屏幕") { controller.moveToPointerScreen() }
                Button("重置当前屏幕位置") { controller.resetPosition() }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 24, height: 26)
            .accessibilityLabel("设置")
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = TaskDaySummary(items: repository.items, date: context.date)
            VStack(spacing: 7) {
                HStack {
                    Text("今日完成").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(summary.completed) / \(summary.total)").foregroundStyle(.secondary)
                    Text("\(summary.percentage)%").foregroundStyle(DockStyle.accent).frame(minWidth: 30, alignment: .trailing)
                }.font(.system(size: 10, weight: .medium)).monospacedDigit()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.07))
                        Capsule().fill(DockStyle.accent.opacity(0.8)).frame(width: proxy.size.width * summary.fraction)
                    }
                }.frame(height: 3)
                .accessibilityLabel("今日完成 \(summary.completed) 项，共 \(summary.total) 项，\(summary.percentage)%")
            }
            .help("统计今日到期、今日新建且无截止时间，以及今日完成的任务。")
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(DockTab.allCases) { item in
                Button {
                    composerFocused = false
                    withAnimation(.easeInOut(duration: 0.16)) { tab = item }
                } label: {
                    Text(item.rawValue).font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 29)
                        .background {
                            if tab == item {
                                RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.075))
                                    .matchedGeometryEffect(id: "selectedTab", in: tabHighlight)
                            }
                        }
                }.buttonStyle(.plain).accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                    .disabled(controller.hasEditor)
            }
        }.padding(3).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
    }

    private var taskList: some View {
        let items = repository.items.filter { $0.isCompleted == (tab == .completed) }.sorted {
            tab == .completed ? ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) : false
        }
        return Group {
            if items.isEmpty {
                emptyState(symbol: tab == .completed ? "checkmark.circle" : "list.bullet",
                           title: tab == .completed ? "还没有已完成任务" : "暂时没有待办",
                           subtitle: tab == .completed ? "完成的任务会保留在这里。" : "在下方记下下一件事。")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in TaskRowView(item: item, controller: controller) }
                    }.padding(.horizontal, 16).padding(.vertical, 3)
                        .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
                }.scrollIndicators(.visible).scrollBounceBehavior(.basedOnSize).id(tab)
            }
        }
    }

    private var habitList: some View {
        let reference = Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
        let days = HabitCalendar.week(containing: reference)
        return VStack(spacing: 8) {
            HStack(spacing: 9) {
                Text(weekOffset == 0 ? "本周" : days[0].formatted(.dateTime.month().day()))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if weekOffset != 0 { Button("本周") { weekOffset = 0 }.font(.system(size: 10)) }
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上一周")
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下一周")
            }.buttonStyle(.plain).font(.system(size: 10)).padding(.horizontal, 20).frame(height: 20)
            if habits.habits.isEmpty {
                emptyState(symbol: "square.grid.2x2", title: "给习惯留一个位置", subtitle: "在下方添加阅读、运动或其他习惯。")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        ForEach(habits.habits) { habit in
                            HabitRowView(habit: habit, days: days, repository: habits, controller: controller)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 3)
                        .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
                }.scrollIndicators(.visible).scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField(tab == .habits ? "添加打卡习惯…" : "添加待办…", text: tab == .habits ? $habitInput : $taskInput)
                    .textFieldStyle(.plain).font(.system(size: 12)).focused($composerFocused)
                    .onSubmit(addFromComposer)
                    .accessibilityLabel(tab == .habits ? "新增习惯名称" : "新增待办标题")
                Button {} label: { Image(systemName: "mic").font(.system(size: 13)) }
                    .buttonStyle(.plain).frame(width: 24, height: 24)
                    .disabled(true).help("语音输入将在后续版本提供")
                    .accessibilityLabel("语音输入，暂未启用")
                Button(action: addFromComposer) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                        .foregroundStyle(DockStyle.accent)
                }.buttonStyle(.plain).accessibilityLabel(tab == .habits ? "添加习惯" : "添加待办")
            }.padding(.horizontal, 20).frame(height: 52)
        }
    }

    private func addFromComposer() {
        if tab == .habits {
            if controller.addHabit(habitInput) { habitInput = "" }
        } else if taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composerFocused = false
            controller.beginEditing()
        } else if controller.addTask(taskInput) {
            taskInput = ""
            tab = .tasks
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
