import SwiftUI
import FocusDockCore

struct TaskEditorView: View {
    let session: TaskEditorSession
    @ObservedObject var controller: PanelWindowController
    @State private var draft: TaskDraft
    init(session: TaskEditorSession, controller: PanelWindowController) {
        self.session = session; self.controller = controller
        _draft = State(initialValue: session.draft)
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    EditorTitleFields(draft: $draft, focusOnAppear: true, onClose: { controller.endEditing() }).padding(.bottom, 4)
                    DeadlineEditorRow(date: $draft.dueDate)
                    ReminderOptionsView(offsets: $draft.reminderOffsets, isEnabled: draft.dueDate != nil)
                    PriorityEditorRow(priority: $draft.priority)
                    HStack(spacing: 8) {
                        Image(systemName: "tag").foregroundStyle(.tertiary)
                        TextField("类别（可选）", text: Binding(get: { draft.category ?? "" }, set: { draft.category = $0 }))
                            .textFieldStyle(.plain).accessibilityLabel("任务类别")
                    }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 5)
                }.padding(.top, 6).padding(.bottom, 4)
                    .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
            }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorFooter(enabled: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         cancel: { controller.endEditing() }, save: save)
        }.padding(.horizontal, 18).frame(maxWidth: 680)
    }
    private func save() {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.save(draft, item: session.item)
    }
}
