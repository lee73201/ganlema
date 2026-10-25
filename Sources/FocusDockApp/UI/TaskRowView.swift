import AppKit
import SwiftUI
import FocusDockCore

struct TaskRowView: View {
    let item: TodoItem
    @ObservedObject var controller: PanelWindowController
    @State private var title = ""
    @State private var editingDate = false
    @State private var quickDate: Date?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button { commitTitle(); controller.toggle(item) } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(item.isCompleted ? DockStyle.accent.opacity(0.65) : .secondary)
                        .frame(width: 22, height: 24)
                }.buttonStyle(.plain).accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
                VStack(alignment: .leading, spacing: 5) {
                    TextField("任务标题", text: $title, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(1...3).focused($titleFocused).onSubmit { commitTitle(); titleFocused = false }
                        .accessibilityLabel("快速编辑标题：\(item.title)")
                    metadata
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
                Menu {
                    Button("专注 25 分钟") { titleFocused = false; commitTitle(); controller.startFocus(item, minutes: 25) }
                    Button("专注 50 分钟") { titleFocused = false; commitTitle(); controller.startFocus(item, minutes: 50) }
                    Divider()
                    Button("完整编辑") { commitTitle(); controller.beginEditing(item) }
                } label: { Image(systemName: "timer").font(.system(size: 12)).foregroundStyle(.secondary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 20, height: 24)
                    .disabled(item.isCompleted).accessibilityLabel("专注计时：\(item.title)")
                Button { controller.delete(item) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 20, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("删除：\(item.title)")
            }
            if editingDate {
                VStack(spacing: 6) {
                    // The narrower list row places this full native date editor on its own line.
                    Toggle("设置截止时间", isOn: Binding(get: { quickDate != nil }, set: { quickDate = $0 ? .now.addingTimeInterval(3600) : nil }))
                        .toggleStyle(.switch).controlSize(.mini).font(.system(size: 10))
                    if quickDate != nil {
                        DatePicker("日期", selection: Binding(get: { quickDate ?? .now }, set: { quickDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.field).controlSize(.small).frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button("取消") { editingDate = false }
                        Spacer()
                        Button("保存日期") { controller.quickUpdate(item, dueDate: .some(quickDate)); editingDate = false }
                    }.font(.system(size: 10))
                }.padding(8).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .onAppear { title = item.title }
        .onChange(of: item.title) { _, value in if !titleFocused { title = value } }
        .onChange(of: titleFocused) { _, focused in
            controller.setQuickEditing(item.id, active: focused || editingDate)
            if !focused { commitTitle() }
        }
        .onChange(of: editingDate) { _, active in controller.setQuickEditing(item.id, active: active || titleFocused) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: controller.window)) { _ in titleFocused = false }
        .onDisappear { commitTitle(); controller.setQuickEditing(item.id, active: false) }
        .contextMenu { Button("完整编辑") { commitTitle(); controller.beginEditing(item) } }
    }
    private func commitTitle() {
        guard controller.repository.items.contains(where: { $0.id == item.id }) else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { title = item.title; return }
        guard title != item.title else { return }
        controller.quickUpdate(item, title: title)
    }
    private var metadata: some View {
        HStack(spacing: 7) {
            Button {
                titleFocused = false; quickDate = item.dueDate; editingDate.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    if let due = item.dueDate { Text(due.formatted(.dateTime.month().day().hour().minute())).lineLimit(1) }
                    else { Text("日期") }
                }.foregroundStyle((item.dueDate.map { $0 < .now.addingTimeInterval(86400) } ?? false) ? Color.orange.opacity(0.85) : .secondary)
            }.buttonStyle(.plain).help("在列表中编辑截止时间").accessibilityLabel("快速编辑日期：\(item.title)")
            Menu {
                ForEach(TaskPriority.allCases) { priority in
                    Button { titleFocused = false; controller.quickUpdate(item, priority: priority) } label: {
                        Label(priority.title, systemImage: item.priority == priority ? "checkmark" : "flag")
                    }
                }
            } label: {
                Label(item.priority.title, systemImage: item.priority == .high ? "flag.fill" : "flag").foregroundStyle(.secondary)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("快速编辑优先级：\(item.title)")
            if item.isCompleted, let date = item.completedAt { Text(date, format: .dateTime.month().day()).foregroundStyle(.tertiary).lineLimit(1) }
            else if let category = item.category { Text(category).foregroundStyle(.tertiary).lineLimit(1) }
            Spacer(minLength: 0)
        }.font(.system(size: 9))
    }
}
