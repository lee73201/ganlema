import SwiftUI
import FocusDockCore

struct TaskEditorView: View {
    let session: TaskEditorSession
    @ObservedObject var controller: PanelWindowController
    @State private var draft: TaskDraft
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @FocusState private var titleFocused: Bool

    init(session: TaskEditorSession, controller: PanelWindowController) {
        self.session = session
        self.controller = controller
        let draft = session.draft
        _draft = State(initialValue: draft)
        _hasDeadline = State(initialValue: draft.dueDate != nil)
        _deadline = State(initialValue: draft.dueDate ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.item == nil ? "新建待办" : "编辑待办")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("取消") { controller.endEditing() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("想完成什么")
                        TextField("写下你的下一步", text: $draft.title)
                            .textFieldStyle(.roundedBorder).focused($titleFocused)
                            .onSubmit { save() }
                            .accessibilityLabel("待办标题")
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("备注")
                        TextEditor(text: $draft.notes)
                            .font(.system(size: 12)).scrollContentBackground(.hidden)
                            .padding(7).frame(height: 50)
                            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityLabel("待办备注")
                    }
                    TextField("类别（可选）", text: Binding(get: { draft.category ?? "" }, set: { draft.category = $0 }))
                        .textFieldStyle(.roundedBorder).accessibilityLabel("任务类别")
                    Picker("优先级", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("设置截止时间", isOn: $hasDeadline).toggleStyle(.switch).font(.system(size: 12))
                        if hasDeadline {
                            DatePicker("截止", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact).font(.system(size: 12))
                            if deadline < .now {
                                Label("这个截止时间已经过去", systemImage: "clock.badge.exclamationmark")
                                    .font(.system(size: 10)).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
            }
            .scrollIndicators(.hidden)
            Button { save() } label: {
                Text("保存待办").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 20).padding(.bottom, 14).padding(.top, 4)
        .onAppear { titleFocused = true }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
    private func save() {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft.dueDate = hasDeadline ? deadline : nil
        controller.save(draft, item: session.item)
    }
}
