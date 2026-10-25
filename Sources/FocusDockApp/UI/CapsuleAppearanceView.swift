import SwiftUI
import FocusDockCore

extension FloatingAppearance {
    var accentColor: Color { colorMode == .custom ? Color(red: red, green: green, blue: blue) : DockStyle.accent }
    var scheme: ColorScheme? { colorMode == .light ? .light : colorMode == .dark ? .dark : nil }
    var appAppearance: NSAppearance? { colorMode == .light ? NSAppearance(named: .aqua) : colorMode == .dark ? NSAppearance(named: .darkAqua) : nil }
}

/// Shared by the live panel and settings previews; sizes and corner paths come from Core.
struct CapsuleAppearanceView: View {
    let appearance: FloatingAppearance
    @Environment(\.colorScheme) private var inheritedScheme
    private var effectiveScheme: ColorScheme { appearance.shape == .island ? .dark : appearance.scheme ?? inheritedScheme }
    private var textColor: Color { effectiveScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.85) }
    var count: Int
    var deadline: String?
    var urgent: Bool
    private var compact: Bool { appearance.shape == .circle || appearance.shape == .strip }
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            if appearance.content == .icon || !compact {
                Image(systemName: appearance.shape == .strip ? "line.3.horizontal" : "checkmark.circle.fill")
                    .font(.system(size: appearance.shape == .strip ? 10 : 20 * appearance.scale.factor))
                    .foregroundStyle(appearance.accentColor)
            }
            if appearance.content != .icon {
                if appearance.shape == .circle {
                    Text("\(count)").font(.system(size: 17, weight: .semibold)).monospacedDigit()
                } else if appearance.shape == .strip {
                    Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                } else {
                    Text(appearance.content == .deadline ? (deadline ?? "暂无截止任务") : "干了吗")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if appearance.content == .count { Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(textColor.opacity(0.65)) }
                }
            }
            if urgent && appearance.shape != .circle { Circle().fill(.orange.opacity(0.8)).frame(width: 4, height: 4) }
        }
        .padding(.horizontal, compact ? 3 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(textColor)
        .environment(\.colorScheme, effectiveScheme)
    }
}

struct FocusTimerBar: View {
    @ObservedObject var timer: FocusTimer
    var body: some View {
        if let session = timer.session {
            HStack(spacing: 8) {
                Image(systemName: timer.finished ? "checkmark.circle" : "timer").foregroundStyle(DockStyle.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.finished ? "本次专注完成" : session.taskTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if timer.finished { Text("任务仍保留待办，可自行标记完成").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                let seconds = Int(ceil(session.remaining(at: timer.now)))
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: 13, weight: .medium, design: .monospaced))
                if !timer.finished {
                    Button { timer.togglePause() } label: { Image(systemName: session.pausedRemaining == nil ? "pause.fill" : "play.fill") }
                        .help(session.pausedRemaining == nil ? "暂停专注" : "继续专注").accessibilityLabel(session.pausedRemaining == nil ? "暂停专注" : "继续专注")
                }
                Button { timer.stop() } label: { Image(systemName: "xmark") }.help("结束专注").accessibilityLabel("结束专注")
            }.buttonStyle(.plain).padding(10).background(DockStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}
