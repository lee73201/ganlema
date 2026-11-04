import SwiftUI

private struct EditorHostKey: EnvironmentKey {
    static let defaultValue = EditingHost.panel
}

extension EnvironmentValues {
    var editorHost: EditingHost {
        get { self[EditorHostKey.self] }
        set { self[EditorHostKey.self] = newValue }
    }
}

struct EditingFlowView: View {
    @ObservedObject var controller: PanelWindowController

    var body: some View {
        if let session = controller.capture {
            TaskCaptureView(session: session, controller: controller).id(session.id)
        } else if controller.voicePresented {
            VoiceCaptureView(controller: controller, speech: controller.speech)
        } else if let session = controller.editor {
            TaskEditorView(session: session, controller: controller).id(session.id)
        } else if let habit = controller.editingHabit {
            HabitEditorView(habit: habit, controller: controller).id(habit.id)
        }
    }
}
