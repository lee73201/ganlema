import SwiftUI
import FocusDockCore

struct HabitRowView: View {
    let habit: Habit
    let days: [Date]
    @ObservedObject var repository: HabitRepository
    @ObservedObject var controller: PanelWindowController
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Button { controller.beginEditingHabit(habit) } label: {
                    Text(habit.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("编辑习惯：\(habit.name)")
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let streak = repository.streak(for: habit, asOf: context.date)
                    if streak > 0 { Text("连续 \(streak) 天").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Button { controller.deleteHabit(habit) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.tertiary)
                }.buttonStyle(.plain).accessibilityLabel("删除习惯：\(habit.name)")
            }
            HStack(spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.element) { index, date in
                    let checked = repository.isChecked(habit, on: date)
                    VStack(spacing: 5) {
                        Text(weekdays[index]).font(.system(size: 9)).foregroundStyle(.secondary.opacity(0.7))
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
        }.padding(11).background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
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
