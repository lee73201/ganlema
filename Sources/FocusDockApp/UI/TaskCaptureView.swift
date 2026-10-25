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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("确认 \(cards.count) 条待办").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { controller.endEditing() } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("关闭确认")
            }.padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("原文与重新解析") {
                        TextEditor(text: $input).font(.system(size: 11)).frame(height: 44)
                            .scrollContentBackground(.hidden).accessibilityLabel("待解析原文")
                        HStack {
                            Text("本机解析 · 请核对时间").font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            Button("重新解析") { cards = LocalTaskParser().parse(input); parsedInput = input }.font(.system(size: 10))
                        }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    if input != parsedInput { Text("原文已修改，请重新解析后保存。").font(.system(size: 10)).foregroundStyle(.orange) }
                    ForEach($cards) { $card in
                        VStack(alignment: .leading, spacing: 12) {
                            EditorTitleFields(draft: $card.draft, accessibilityTitle: "确认任务名称", onClose: { cards.removeAll { $0.id == card.id } })
                            DeadlineEditorRow(date: $card.draft.dueDate)
                            ReminderOptionsView(offsets: $card.draft.reminderOffsets, isEnabled: card.draft.dueDate != nil)
                            PriorityEditorRow(priority: $card.draft.priority)
                            ForEach(card.warnings, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                        }
                        if card.id != cards.last?.id { Divider().padding(.vertical, 6).opacity(0.4) }
                    }
                    Text("核对后保存；勾选提醒时需允许系统通知。")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }.padding(.vertical, 4)
                    .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
            }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorFooter(saveTitle: "确认并保存", enabled: valid, cancel: { controller.endEditing() }, save: { controller.confirmCapture(cards) })
        }.padding(.horizontal, 18).padding(.top, 2).frame(maxWidth: 680)
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
                Button(speech.state == .finishing ? "用当前文字解析" : "解析待办") { controller.beginCapture(text) }.buttonStyle(.borderedProminent)
                    .disabled(speech.state == .requesting || speech.state == .listening || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(.horizontal, 20).padding(.bottom, 14)
            .onAppear { text = speech.transcript }
            .onChange(of: speech.transcript) { _, value in text = value }
            .background(OverlayScrollerStyle().frame(width: 0, height: 0).allowsHitTesting(false))
    }
    private var status: String {
        switch speech.state {
        case .idle: return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未得到识别文字，可重新录音或直接输入" : "已保留识别文字，可修改后解析并确认保存"
        case .requesting: return "正在请求语音识别与麦克风权限…"
        case .listening: return "正在聆听，最长 55 秒…"
        case .finishing: return "正在等待最终结果，已有文字会保留…"
        }
    }
}
