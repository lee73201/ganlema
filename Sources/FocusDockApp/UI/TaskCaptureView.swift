import SwiftUI
import FocusDockCore

struct TaskCaptureView: View {
    let session: CaptureSession
    @ObservedObject var controller: PanelWindowController
    @State private var input: String
    @State private var cards: [ParsedTask]
    @State private var parsedInput: String
    init(session: CaptureSession, controller: PanelWindowController) {
        self.session = session; self.controller = controller
        _input = State(initialValue: session.input); _parsedInput = State(initialValue: session.input)
        _cards = State(initialValue: session.cards)
    }
    private var valid: Bool { !cards.isEmpty && cards.allSatisfy { !$0.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && input == parsedInput }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("确认 \(cards.count) 条待办").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("取消") { controller.endEditing() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $input).font(.system(size: 12)).frame(height: 48)
                        .scrollContentBackground(.hidden).padding(6).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("待解析原文")
                    HStack {
                        Text("本机解析 · 请核对时间").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("重新解析") { cards = LocalTaskParser().parse(input); parsedInput = input }.font(.system(size: 10))
                    }
                    if input != parsedInput { Text("原文已修改，请重新解析后保存。").font(.system(size: 10)).foregroundStyle(.orange) }
                    ForEach($cards) { $card in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .top) {
                                TextField("任务名称", text: $card.draft.title, axis: .vertical).lineLimit(1...3)
                                    .textFieldStyle(.plain).font(.system(size: 12, weight: .medium)).accessibilityLabel("确认任务名称")
                                Button { cards.removeAll { $0.id == card.id } } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.secondary) }
                                    .buttonStyle(.plain).accessibilityLabel("移除解析卡片：\(card.draft.title)")
                            }
                            Toggle("截止时间", isOn: Binding(get: { card.draft.dueDate != nil }, set: { card.draft.dueDate = $0 ? .now.addingTimeInterval(3600) : nil }))
                                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 10))
                            if card.draft.dueDate != nil {
                                DatePicker("截止", selection: Binding(get: { card.draft.dueDate ?? .now }, set: { card.draft.dueDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact).font(.system(size: 11))
                                ReminderOptionsView(offsets: $card.draft.reminderOffsets)
                            }
                            Picker("优先级", selection: $card.draft.priority) {
                                ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).controlSize(.small)
                            ForEach(card.warnings, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("保存后才写入待办；勾选提醒后会申请系统权限。请核对任务与时间。")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 2)
                    .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
            }.scrollIndicators(.hidden)
            Button("确认并保存") { controller.confirmCapture(cards) }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(!valid)
                .keyboardShortcut("s", modifiers: .command)
        }.padding(.horizontal, 20).padding(.bottom, 14)
    }
}

struct ReminderOptionsView: View {
    @Binding var offsets: [TimeInterval]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("系统提醒").font(.system(size: 10)).foregroundStyle(.secondary)
            let choices = ReminderPlan.normalized(ReminderPlan.defaultOffsets + offsets)
            ForEach(choices, id: \.self) { offset in
                Toggle(ReminderPlan.label(offset), isOn: Binding(get: { offsets.contains(offset) }, set: { selected in
                    offsets = selected ? ReminderPlan.normalized(offsets + [offset]) : offsets.filter { $0 != offset }
                })).toggleStyle(.checkbox).font(.system(size: 10))
            }
        }
    }
}

struct VoiceCaptureView: View {
    @ObservedObject var controller: PanelWindowController
    @ObservedObject var speech: NativeSpeechService
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("说出你的待办").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("取消") { controller.endEditing() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text(status).font(.system(size: 11)).foregroundStyle(speech.isBusy ? DockStyle.accent : .secondary)
            TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(8).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("语音识别文字，可手动修改")
                .disabled(speech.isBusy)
            if let error = speech.errorMessage { Text(error).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Text(speech.modeDescription).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                if speech.state == .listening {
                    Button("结束录音") { speech.finish() }.buttonStyle(.bordered)
                } else if !speech.isBusy {
                    Button("重新录音") { Task { try? await speech.start() } }.buttonStyle(.bordered)
                }
                Spacer()
                Button("解析待办") { controller.beginCapture(text) }.buttonStyle(.borderedProminent)
                    .disabled(speech.isBusy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(.horizontal, 20).padding(.bottom, 14)
            .onChange(of: speech.transcript) { _, value in text = value }
            .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
    }
    private var status: String {
        switch speech.state {
        case .idle: return "可修改识别文字，再解析并确认保存"
        case .requesting: return "正在请求语音识别与麦克风权限…"
        case .listening: return "正在聆听，最长 55 秒…"
        case .finishing: return "正在整理识别结果…"
        }
    }
}
