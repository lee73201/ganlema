import SwiftUI
import FocusDockCore

struct CompletionListView: View {
    @ObservedObject var repository: TaskRepository
    @ObservedObject var habits: HabitRepository
    @ObservedObject var controller: PanelWindowController
    var body: some View {
        let entries = CompletionEntry.all(tasks: repository.items, habits: habits.habits, records: habits.checkIns)
        let groups = Dictionary(grouping: entries) { HabitCalendar.key(for: $0.date) }
        if entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary)
                Text("还没有完成记录").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("完成的待办和每日打卡会出现在这里。") .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                        Text(dayTitle(key)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.top, 8).padding(.bottom, 3)
                        ForEach(groups[key] ?? []) { entry in
                            switch entry.source {
                            case .task(let item): TaskRowView(item: item, controller: controller)
                            case .habit(let habit, let record): habitRow(habit, record: record)
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 3)
                    .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
            }.scrollIndicators(.visible).scrollBounceBehavior(.basedOnSize)
        }
    }
    private func dayTitle(_ key: String) -> String {
        guard let date = HabitCalendar.date(for: key) else { return key }
        return date.formatted(.dateTime.year().month().day().weekday(.wide))
    }
    private func habitRow(_ habit: Habit, record: HabitCheckIn) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { controller.removeCheckIn(record) } label: {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .light))
                    .foregroundStyle(DockStyle.accent.opacity(0.65)).frame(width: 22, height: 24)
            }.buttonStyle(.plain).accessibilityLabel("取消打卡：\(habit.name)，\(record.dayKey)")
            VStack(alignment: .leading, spacing: 5) {
                Text(habit.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text("打卡 · \(record.dayKey)").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.padding(.top, 3)
            Button { controller.removeCheckIn(record) } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 22, height: 24)
            }.buttonStyle(.plain).accessibilityLabel("删除本次打卡：\(habit.name)，\(record.dayKey)")
        }.padding(.horizontal, 10).padding(.vertical, 9)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct NotificationControl: View {
    @ObservedObject var reminders: NativeReminderService
    @ObservedObject var controller: PanelWindowController
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: reminders.isAuthorized ? "bell.badge" : "bell.slash")
                .font(.system(size: 12)).foregroundStyle(reminders.isDenied ? Color.orange.opacity(0.85) : .secondary)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help(reminders.status)
            .accessibilityLabel("系统提醒：\(reminders.status)")
            .onChange(of: presented) { _, value in controller.setNotificationGuidePresented(value) }
            .onDisappear { controller.setNotificationGuidePresented(false) }
            .popover(isPresented: $presented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(reminders.isAuthorized ? "系统提醒已开启" : reminders.isDenied ? "系统提醒未开启" : "开启截止提醒", systemImage: reminders.isAuthorized ? "bell.badge" : "bell.slash")
                        .font(.system(size: 13, weight: .semibold))
                    Text(reminders.isDenied ? "截止提醒暂时无法送达。打开系统设置，在通知列表中选择「干了吗」，开启「允许通知」。" : reminders.isAuthorized ? "\(reminders.status)。系统勿扰和休眠仍可能影响提醒。" : "允许通知后，才能收到任务的截止提醒。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if reminders.settingsOpenFailed { Text("未能打开设置，请手动前往系统设置 → 通知 → 干了吗。").font(.system(size: 10)).foregroundStyle(.orange) }
                    HStack {
                        Button("重新检查") { Task { await reminders.refreshAndSync() } }
                        Spacer()
                        Button(reminders.isAuthorized || reminders.isDenied ? "打开通知设置" : "允许通知") {
                            if reminders.isAuthorized || reminders.isDenied { reminders.openSettings() }
                            else { Task { await reminders.enable() } }
                        }.buttonStyle(.borderedProminent).tint(DockStyle.accent)
                    }.font(.system(size: 11))
                }.padding(16).frame(width: 270)
                .task { await reminders.refreshAndSync() }
            }
    }
}
