import SwiftUI
import FocusDockCore

struct TaskRecommendationView: View {
    let items: [TodoItem]
    @ObservedObject var controller: PanelWindowController
    @ObservedObject var timer: FocusTimer
    @State private var isOpen = false
    @State private var minutes = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle").foregroundStyle(DockStyle.accent)
                    Text("现在做哪件").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                }.frame(minHeight: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "已展开" : "已收起")
            if isOpen {
                Picker("空闲时间", selection: $minutes) {
                    ForEach(FocusSession.minuteOptions, id: \.self) { value in
                        Text("\(value) 分钟").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                recommendation
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 4).padding(.bottom, 7)
        .overlay(alignment: .bottom) { DockStyle.separator }
    }

    @ViewBuilder private var recommendation: some View {
        if let result = TaskRecommendation.choose(from: items, estimates: controller.taskEstimates, availableMinutes: minutes, now: timer.now) {
            Text(result.task.title).font(.system(size: 13, weight: .medium)).lineLimit(2).help(result.task.title)
            let detail = result.estimatedMinutes.map { "约 \($0) 分钟" } ?? "未估时，可先做一步"
            Text("\(result.reason) · \(detail)").foregroundStyle(.secondary)
            if timer.session != nil && !timer.finished {
                Text("已有专注计时，可先继续或结束。").foregroundStyle(.secondary)
            } else {
                Button("专注 \(minutes) 分钟", systemImage: "play.fill") {
                    controller.startRecommendedFocus(result.task, minutes: minutes)
                    isOpen = false
                }
                .controlSize(.small)
            }
        } else {
            Text("这段时间没有合适的任务，试试更长的时段。")
                .foregroundStyle(.secondary)
        }
    }
}
