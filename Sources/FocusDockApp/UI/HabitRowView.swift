import SwiftUI
import FocusDockCore

struct HabitRowView: View {
    let habit: Habit
    let days: [Date]
    @ObservedObject var repository: HabitRepository
    @ObservedObject var controller: PanelWindowController
    @Environment(\.editorHost) private var editorHost
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { controller.beginEditingHabit(habit, in: editorHost) } label: {
                    Text(habit.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("编辑习惯：\(habit.name)")
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let streak = repository.streak(for: habit, asOf: context.date)
                    if streak > 0 { Text("连续 \(streak) 天").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Button { controller.deleteHabit(habit) } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("删除习惯：\(habit.name)")
                    .disabled(controller.editingHabit?.id == habit.id)
            }
            HStack(spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.element) { index, date in
                    let checked = repository.isChecked(habit, on: date)
                    VStack(spacing: 5) {
                        Text(weekdays[index]).font(.system(size: 11)).foregroundStyle(.secondary)
                        Button { controller.toggleHabit(habit, date: date) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(checked ? DockStyle.accent.opacity(0.8) : .primary.opacity(0.045))
                                if checked {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                } else {
                                    Text("\(Calendar.current.component(.day, from: date))").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }.frame(height: 27)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(habit.name)，\(date.formatted(.dateTime.month().day()))，\(checked ? "已打卡" : "未打卡")")
                            .help(date.formatted(.dateTime.year().month().day()))
                    }.frame(maxWidth: .infinity)
                }
            }
        }.padding(.horizontal, 4).padding(.vertical, 12)
            .overlay(alignment: .bottom) { DockStyle.separator }
    }
}

struct HabitEditorView: View {
    let habit: Habit
    @ObservedObject var controller: PanelWindowController
    @State private var name: String
    @FocusState private var focused: Bool
    init(habit: Habit, controller: PanelWindowController) {
        self.habit = habit
        self.controller = controller
        _name = State(initialValue: habit.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("编辑习惯").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("取消") { controller.endEditing() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            TextField("习惯名称", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(save).accessibilityLabel("习惯名称")
            Text("修改名称会保留所有历史打卡记录。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button("保存", action: save).buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("s", modifiers: .command)
        }.padding(20).onAppear { focused = true }
    }
    private func save() { controller.saveHabit(habit, name: name) }
}

struct HabitListView: View {
    @ObservedObject var habits: HabitRepository
    @ObservedObject var controller: PanelWindowController
    @Binding var weekOffset: Int

    var body: some View {
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
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 20)).accessibilityHidden(true)
                    Text("给习惯留一个位置").font(.system(size: 12, weight: .medium))
                    Text("在下方添加阅读、运动或其他习惯。").font(.system(size: 11))
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(habits.habits) { habit in
                            HabitRowView(habit: habit, days: days, repository: habits, controller: controller)
                        }
                    }.padding(.horizontal, DockStyle.inset)
                        .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
                }.scrollIndicators(.visible).scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}
