import AppKit
import SwiftUI
import FocusDockCore

/// Shared by regular editing and parsed task confirmation. All bindings target TaskDraft.
struct EditorTitleFields: View {
    @Binding var draft: TaskDraft
    var accessibilityTitle = "待办标题"
    var focusOnAppear = false
    var onClose: (() -> Void)?
    @FocusState private var focused: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 17, weight: .regular)).foregroundStyle(DockStyle.accent)
                .frame(width: 35, height: 35)
                .background(DockStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                TextField("任务名称", text: $draft.title, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                    .lineLimit(1...3).focused($focused).accessibilityLabel(accessibilityTitle)
                TextField("添加描述（可选）", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1...3).accessibilityLabel("待办备注")
            }.padding(.top, 2).frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 25, height: 25)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityLabel("关闭编辑")
            }
        }.onAppear { if focusOnAppear { focused = true } }
    }
}

struct EditorSection<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.045), lineWidth: 0.5))
    }
}

struct DeadlineEditorRow: View {
    @Binding var date: Date?
    @State private var parkedDate = Date().addingTimeInterval(3600)
    @State private var showCalendar = false
    private var enabled: Binding<Bool> {
        Binding(get: { date != nil }, set: { date = $0 ? parkedDate : nil })
    }
    private var selection: Binding<Date> {
        Binding(get: { date ?? parkedDate }, set: { parkedDate = $0; date = $0 })
    }
    var body: some View {
        EditorSection {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("截止时间", systemImage: "clock").font(.system(size: 11, weight: .medium)).fixedSize()
                    Toggle("设置截止时间", isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini).fixedSize()
                        .accessibilityLabel("设置截止时间")
                    HStack(spacing: 2) {
                        CompactDateTimeField(date: selection, isEnabled: date != nil)
                            .frame(minWidth: 128, maxWidth: .infinity).frame(height: 25)
                        Button { NSApp.activate(ignoringOtherApps: true); showCalendar.toggle() } label: {
                            Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 22, height: 25)
                        }.buttonStyle(.plain).disabled(date == nil).accessibilityLabel("打开截止日期日历")

                    }.padding(.horizontal, 5)
                        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
                        .opacity(date == nil ? 0.45 : 1)
                }
                if showCalendar && date != nil {
                    VStack(alignment: .trailing, spacing: 6) {
                        DatePicker("截止日期", selection: selection, displayedComponents: [.date])
                            .datePickerStyle(.graphical).labelsHidden().frame(width: 224)
                        Button("完成日期选择") { showCalendar = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(DockStyle.accent)
                    }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
                }
                if let date, date < .now {
                    Text("已过去的截止时间，请核对").font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
        }
        .onAppear { if let date { parkedDate = date } }
        .onChange(of: date) { _, value in if let value { parkedDate = value } else { showCalendar = false } }
    }
}

/// AppKit field without a bezel, white fill or stepper. Keyboard/date editing stays native.
private struct CompactDateTimeField: NSViewRepresentable {
    @Binding var date: Date
    var isEnabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = EditorDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.datePickerMode = .single
        picker.locale = Locale(identifier: "zh_CN")
        picker.calendar = Calendar(identifier: .gregorian)
        picker.timeZone = .autoupdatingCurrent
        picker.isBordered = false; picker.isBezeled = false; picker.drawsBackground = false
        picker.focusRingType = .none
        picker.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        picker.textColor = .labelColor
        picker.controlSize = .small
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.target = context.coordinator; picker.action = #selector(Coordinator.changed(_:))
        picker.setAccessibilityLabel("截止日期和时间")
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        // Avoid resetting a segment while the user is typing into the field editor.
        if abs(picker.dateValue.timeIntervalSince(date)) > 0.5 { picker.dateValue = date }
        picker.isEnabled = isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 148, height: 25)
    }
    final class Coordinator: NSObject {
        var parent: CompactDateTimeField
        init(_ parent: CompactDateTimeField) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.date = sender.dateValue }
    }
}

struct ReminderOptionsView: View {
    @Binding var offsets: [TimeInterval]
    var isEnabled = true
    @State private var customPresented = false
    var body: some View {
        EditorSection {
            VStack(alignment: .leading, spacing: 9) {
                Label("提醒我", systemImage: "bell").font(.system(size: 11, weight: .medium))
                WrappingPillLayout(spacing: 6) {
                    ForEach(ReminderPlan.normalized(ReminderPlan.defaultOffsets + [1800] + offsets), id: \.self) { offset in
                        let checked = offsets.contains(offset)
                        Button {
                            offsets = checked ? offsets.filter { $0 != offset } : ReminderPlan.normalized(offsets + [offset])
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).opacity(checked ? 1 : 0).frame(width: 9)
                                Text(offset == 0 ? "到期时" : ReminderPlan.label(offset)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            }.padding(.horizontal, 9).frame(height: 27)
                                .foregroundStyle(checked ? Color.white : Color.secondary)
                                .background(checked ? DockStyle.accent.opacity(0.88) : Color.primary.opacity(0.025), in: Capsule())
                                .overlay(Capsule().strokeBorder(.primary.opacity(checked ? 0 : 0.07), lineWidth: 0.5))
                        }.buttonStyle(.plain).accessibilityLabel(ReminderPlan.label(offset))
                            .accessibilityValue(checked ? "已选" : "未选").accessibilityAddTraits(checked ? .isSelected : [])
                    }
                    Button { NSApp.activate(ignoringOtherApps: true); customPresented.toggle() } label: {
                        Label("自定义时间", systemImage: "plus").font(.system(size: 10)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).frame(height: 27)
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                    }.buttonStyle(.plain).accessibilityLabel("自定义提醒时间")

                }.disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
                if customPresented && isEnabled {
                    CustomReminderView { value in
                        offsets = ReminderPlan.normalized(offsets + [value]); customPresented = false
                    }
                }
                if !isEnabled { Text("添加截止时间后可启用提醒").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }
        }
    }
}

/// Wrap pills at their actual width; selection never changes a pill's reserved checkmark width.
private struct WrappingPillLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (index, rect) in layout.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading,
                                 proposal: ProposedViewSize(rect.size))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let width = max(1, width)
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var frames: [CGRect] = []
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = CGSize(width: min(width, natural.width), height: natural.height)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: frames.isEmpty ? 0 : y + rowHeight), frames)
    }
}

private struct CustomReminderView: View {
    let add: (TimeInterval) -> Void
    @State private var amount = "30"
    @State private var unit = 60.0
    @FocusState private var amountFocused: Bool
    private var seconds: TimeInterval? {
        guard let amount = Int(amount), amount > 0 else { return nil }
        let seconds = Double(amount) * unit
        return seconds <= 366 * 86400 ? seconds : nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提前提醒").font(.system(size: 12, weight: .semibold))
            HStack {
                TextField("时长", text: $amount).textFieldStyle(.roundedBorder).frame(width: 66).focused($amountFocused).accessibilityLabel("自定义提醒数值")
                Picker("单位", selection: $unit) {
                    Text("分钟").tag(60.0); Text("小时").tag(3600.0); Text("天").tag(86400.0)
                }.labelsHidden().frame(width: 95)
            }
            Button("添加提醒") { if let seconds { add(seconds) } }.buttonStyle(.borderedProminent).disabled(seconds == nil)
        }.padding(.top, 5).onAppear { amountFocused = true }
    }
}

struct PriorityEditorRow: View {
    @Binding var priority: TaskPriority
    var body: some View {
        EditorSection {
            HStack(spacing: 12) {
                Label("优先级", systemImage: "flag").font(.system(size: 11, weight: .medium)).fixedSize()
                HStack(spacing: 2) {
                    ForEach(TaskPriority.allCases) { value in
                        Button { priority = value } label: {
                            Text(value.title).font(.system(size: 11, weight: priority == value ? .semibold : .regular))
                                .foregroundStyle(priority == value ? Color.primary : Color.secondary)
                                .frame(maxWidth: .infinity).frame(height: 27)
                                .background(priority == value ? DockStyle.accent.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel("优先级：\(value.title)")
                            .accessibilityAddTraits(priority == value ? .isSelected : [])
                    }
                }.padding(2).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct EditorFooter: View {
    var saveTitle = "保存任务"
    var enabled = true
    let cancel: () -> Void
    let save: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Divider().opacity(0.45)
            HStack(spacing: 10) {
                Button("取消", action: cancel).buttonStyle(EditorActionStyle(primary: false)).keyboardShortcut(.cancelAction)
                Button(saveTitle, action: save).buttonStyle(EditorActionStyle(primary: true)).disabled(!enabled)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }.padding(.top, 8).padding(.bottom, 14)
    }
}
private struct EditorActionStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 34)
            .foregroundStyle(primary ? Color.white : Color.primary.opacity(0.8))
            .background(primary ? DockStyle.accent : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(primary ? 0 : 0.07), lineWidth: 0.5))
            .opacity((enabled ? 1 : 0.45) * (configuration.isPressed ? 0.8 : 1))
    }
}

private final class EditorDatePicker: NSDatePicker {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
