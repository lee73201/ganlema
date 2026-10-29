import SwiftUI
import FocusDockCore

struct DeletionUndoBar: View {
    @ObservedObject var undo: DeletionUndo
    @ObservedObject var controller: PanelWindowController
    var body: some View {
        if let entry = undo.latest {
            HStack(spacing: 8) {
                Text(entry.title).font(.system(size: 11)).lineLimit(1)
                if undo.entries.count > 1 { Text("\(undo.entries.count) 项可撤销").font(.system(size: 9)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Text("\(max(0, Int(ceil(entry.expires.timeIntervalSince(undo.now)))))s").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                Button("撤销删除") { controller.undoDeletion() }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(DockStyle.accent)
                    .padding(5).contentShape(Rectangle())
            }.padding(.horizontal, 12).frame(height: 38)
                .background(DockStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.vertical, 5)
        }
    }
}
