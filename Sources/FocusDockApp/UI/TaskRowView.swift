import SwiftUI
import FocusDockCore

struct TaskRowView: View {
    let item: TodoItem
    @ObservedObject var controller: PanelWindowController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { controller.toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(item.isCompleted ? DockStyle.accent.opacity(0.65) : .secondary)
                    .frame(width: 22, height: 24)
            }.buttonStyle(.plain).accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
            Button { controller.beginEditing(item) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    metadata
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
            }.buttonStyle(.plain).accessibilityLabel("编辑：\(item.title)")
            Button { controller.delete(item) } label: {
                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 22, height: 24)
            }.buttonStyle(.plain).help("删除任务").accessibilityLabel("删除：\(item.title)")
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var metadata: some View {
        HStack(spacing: 6) {
            if item.isCompleted, let completed = item.completedAt {
                Text("完成于 \(completed.formatted(.dateTime.month().day().hour().minute()))")
                    .foregroundStyle(.tertiary).lineLimit(1)
            } else if let due = item.dueDate {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let overdue = due < context.date
                    let soon = due.timeIntervalSince(context.date) < 24 * 3600
                    HStack(spacing: 3) {
                        if soon { Circle().fill(Color.orange.opacity(0.7)).frame(width: 3, height: 3) }
                        Text((overdue ? "已逾期 · " : "") + due.formatted(.dateTime.month().day().hour().minute()))
                            .lineLimit(1)
                    }.foregroundStyle(soon ? Color.orange.opacity(0.85) : .secondary)
                }
            }
            if let category = item.category, !category.isEmpty {
                Text(category).foregroundStyle(.tertiary).lineLimit(1)
            }
            if item.priority == .high && !item.isCompleted {
                Image(systemName: "flag.fill").foregroundStyle(.secondary).accessibilityLabel("高优先级")
            }
        }.font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .leading)
    }
}
