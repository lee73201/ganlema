import Foundation
import FocusDockCore

// Explicit developer tool. It is not linked into FocusDock.app and never runs on normal launch.
@main struct QAFixtures {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard directory.lastPathComponent.hasPrefix("qa-") else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let taskURL = directory.appendingPathComponent("tasks.store")
        let habitURL = directory.appendingPathComponent("habits.store")
        guard !FileManager.default.fileExists(atPath: taskURL.path), !FileManager.default.fileExists(atPath: habitURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let tasks = try TaskRepository(storeURL: taskURL)
        let habits = try HabitRepository(storeURL: habitURL)
        if CommandLine.arguments[2] == "populated" {
            for index in 0..<36 {
                let title: String
                if index == 0 {
                    title = "检查长任务标题的自动换行与截断：整理本季度所有项目的设计反馈、讨论记录以及后续行动计划，确保文字始终限制在悬浮面板内部"
                } else if index == 6 { title = String(repeating: "LongUnbrokenTitle", count: 10) }
                else { title = ["整理项目笔记", "完成设计评审", "准备周会材料", "阅读技术文档"][index % 4] + " · \(index + 1)" }
                let item = try tasks.add(TaskDraft(title: title, notes: "仅用于隔离视觉验收", dueDate: index % 3 == 0 ? .now.addingTimeInterval(Double(index - 2) * 3600) : nil,
                                                  priority: index % 6 == 0 ? .high : .normal, category: index % 2 == 0 ? "工作" : nil))
                if index > 27 { try tasks.toggleCompletion(item) }
            }
            let week = HabitCalendar.week(containing: .now)
            for (index, name) in ["喝水", "阅读", "运动", "睡前整理和复盘当天计划并准备第二天的安排", "保持专注"].enumerated() {
                let habit = try habits.add(name: name)
                for day in week.prefix(index + 1) { try habits.toggle(habit, on: day) }
            }
        }
        print("Isolated QA stores ready: \(tasks.items.count) tasks, \(habits.habits.count) habits")
    }
}
