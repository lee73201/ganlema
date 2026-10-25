import AppKit
import SwiftUI
import FocusDockCore

struct TaskRowView: View {
    let item: TodoItem
    @ObservedObject var controller: PanelWindowController
    @State private var title = ""
    @State private var editingDate = false
    @State private var editingTitle = false
    @State private var quickDate: Date?

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
                    if editingTitle {
                        InlineTitleField(text: $title, label: "快速编辑标题：\(item.title)", completed: item.isCompleted) {
                            commitTitle(); editingTitle = false
                        } onCancel: {
                            title = item.title; editingTitle = false
                        }.frame(height: 20)
                    } else {
                        Button { NSApp.activate(ignoringOtherApps: true); controller.window?.makeKeyAndOrderFront(nil); title = item.title; editingTitle = true } label: {
                            Text(item.title).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .lineLimit(3).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityLabel("快速编辑标题：\(item.title)")
                    }
                    metadata
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
                Menu {
                    Button("专注 25 分钟") { editingTitle = false; commitTitle(); controller.startFocus(item, minutes: 25) }
                    Button("专注 50 分钟") { editingTitle = false; commitTitle(); controller.startFocus(item, minutes: 50) }
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
        .onChange(of: item.title) { _, value in if !editingTitle { title = value } }
        .onChange(of: editingTitle) { _, active in
            if !active { commitTitle() }
            controller.setQuickEditing(item.id, active: active || editingDate)
        }
        .onChange(of: editingDate) { _, active in controller.setQuickEditing(item.id, active: active || editingTitle) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: controller.window)) { _ in
            if editingTitle { commitTitle(); editingTitle = false }
        }
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
                editingTitle = false; quickDate = item.dueDate; editingDate.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    if let due = item.dueDate { Text(due.formatted(.dateTime.month().day().hour().minute())).lineLimit(1) }
                    else { Text("日期") }
                }.foregroundStyle((item.dueDate.map { $0 < .now.addingTimeInterval(86400) } ?? false) ? Color.orange.opacity(0.85) : .secondary)
            }.buttonStyle(.plain).help("在列表中编辑截止时间").accessibilityLabel("快速编辑日期：\(item.title)")
            Menu {
                ForEach(TaskPriority.allCases) { priority in
                    Button { editingTitle = false; controller.quickUpdate(item, priority: priority) } label: {
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

/// Explicit native field-editor focus for a nonactivating floating panel. Keyboard input
/// cannot silently continue into the bottom composer when this inline editor appears.
private struct InlineTitleField: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let completed: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = InlineNativeTextField(string: text)
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.font = .systemFont(ofSize: 12, weight: .medium)
        field.textColor = completed ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(label)
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(field)
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.currentEditor() == nil && field.stringValue != text { field.stringValue = text }
        field.setAccessibilityLabel(label)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTitleField
        private var ended = false
        init(_ parent: InlineTitleField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if !ended, let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func controlTextDidEndEditing(_ notification: Notification) { finish(cancel: false) }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard !textView.hasMarkedText() else { return false }
                parent.text = textView.string; finish(cancel: false, resigning: control.window); return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finish(cancel: true, resigning: control.window); return true }
            return false
        }
        private func finish(cancel: Bool, resigning window: NSWindow? = nil) {
            guard !ended else { return }; ended = true
            window?.makeFirstResponder(nil)
            if cancel { parent.onCancel() } else { parent.onCommit() }
        }
    }
}
private final class InlineNativeTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
