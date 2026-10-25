import Foundation

public struct ParsedTask: Identifiable {
    public let id: UUID
    public var draft: TaskDraft
    public var warnings: [String]
    public init(draft: TaskDraft, warnings: [String] = []) {
        id = UUID(); self.draft = draft; self.warnings = warnings
    }
}

/// Deterministic, local Chinese task capture. Unknown dates stay visible for confirmation.
public struct LocalTaskParser {
    public init() {}
    public func parse(_ input: String, now: Date = .now, calendar source: Calendar = .autoupdatingCurrent) -> [ParsedTask] {
        let calendar = HabitCalendar.calendar(source)
        // Dictation can omit separators between two dated tasks. Split only from the
        // second explicit day+clock, so a leading "提醒我明天…" stays one task.
        let boundaryPattern = "(?:大后天|后天|明天|今天|今晚|(?:下下周|下周|本周|这周|周|星期)[一二三四五六日天])(?:凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)?[0-9零〇一二两三四五六七八九十]+(?:[:：][0-9]{2}|点|时)"
        let punctuated = NSMutableString(string: input)
        if let expression = try? NSRegularExpression(pattern: boundaryPattern) {
            let dates = expression.matches(in: input, range: NSRange(location: 0, length: (input as NSString).length))
            for match in dates.dropFirst().reversed() { punctuated.insert("；", at: match.range.location) }
        }
        let text = (punctuated as String).replacingOccurrences(of: "(?:以及|并且|和)(?=今天|明天|后天|下周|周[一二三四五六日天])", with: "；", options: .regularExpression).replacingOccurrences(of: "然后", with: "；")
            .replacingOccurrences(of: "另外", with: "；").replacingOccurrences(of: "还有", with: "；")
        var clauses = text.components(separatedBy: CharacterSet(charactersIn: "，,。；;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // A separate reminder clause belongs to the preceding task, not a new task.
        var merged: [String] = []
        while !clauses.isEmpty {
            let clause = clauses.removeFirst()
            if clause.contains("提醒"), !merged.isEmpty,
               clause.hasPrefix("提前") || clause.hasPrefix("不要") || clause.hasPrefix("不需要") || clause.hasPrefix("到期") {
                merged[merged.count - 1] += " " + clause
            } else { merged.append(clause) }
        }
        var previousDate: Date?
        return merged.map { clause in
            let hasClock = clause.range(of: "[0-9一二两三四五六七八九十](?:点|时|[:：])", options: .regularExpression) != nil
            let parsed = parseOne(clause, now: now, calendar: calendar, inheritedDay: hasClock ? previousDate : nil)
            previousDate = parsed.draft.dueDate
            return parsed
        }
    }

    private func parseOne(_ original: String, now: Date, calendar: Calendar, inheritedDay: Date?) -> ParsedTask {
        var text = original
        var warnings: [String] = []
        var offsets = ReminderPlan.defaultOffsets
        if text.contains("不要提醒") || text.contains("不需要提醒") || text.contains("不提醒") {
            offsets = []
            text = text.replacingOccurrences(of: "(?:不要|不需要|不)提醒", with: "", options: .regularExpression)
        } else {
            let reminders = matches("提前([0-9零〇一二两三四五六七八九十百半]+)(分钟|小时|天)提醒", in: text)
            if !reminders.isEmpty {
                offsets = [0]
                for match in reminders {
                    let number = match[1] == "半" ? 0.5 : Double(Self.number(match[1]) ?? 0)
                    let unit: Double = match[2] == "天" ? 86400 : match[2] == "小时" ? 3600 : 60
                    if number > 0 { offsets.append(number * unit) }
                    text = text.replacingOccurrences(of: match[0], with: "")
                }
                offsets = Array(Set(offsets)).sorted(by: >)
            }
            text = text.replacingOccurrences(of: "到期提醒", with: "")
        }
        var due: Date?
        var day = calendar.startOfDay(for: inheritedDay ?? now)
        var hasDay = inheritedDay != nil
        var invalidDate = false
        // Relative durations are deadlines; relative reminder durations were removed above.
        if let m = matches("([0-9零〇一二两三四五六七八九十百半]+)(分钟|小时|天)后", in: text).first,
           let n = m[1] == "半" ? 0.5 : Self.number(m[1]).map(Double.init), n > 0 {
            if m[2] == "天", n.rounded() == n { due = calendar.date(byAdding: .day, value: Int(n), to: now) }
            else { due = now.addingTimeInterval(n * (m[2] == "小时" ? 3600 : m[2] == "天" ? 86400 : 60)) }
            text = text.replacingOccurrences(of: m[0], with: "")
        } else {
            if let m = matches("(?:(20[0-9]{2})[-/年])?([0-9]{1,2})[-/月]([0-9]{1,2})(?:日|号)?", in: text).first,
               let month = Int(m[2]), let date = Int(m[3]) {
                let year = Int(m[1]) ?? calendar.component(.year, from: now)
                var parts = DateComponents(year: year, month: month, day: date)
                if let candidate = calendar.date(from: parts), calendar.component(.month, from: candidate) == month,
                   calendar.component(.day, from: candidate) == date {
                    day = candidate
                    if m[1].isEmpty && day < calendar.startOfDay(for: now) {
                        parts.year = year + 1
                        day = calendar.date(from: parts) ?? candidate
                        if calendar.component(.month, from: day) != month { invalidDate = true }
                    }
                    hasDay = true
                } else { invalidDate = true }
                text = text.replacingOccurrences(of: m[0], with: "")
            } else if let m = matches("(下下周|下周|本周|这周|周|星期)([一二三四五六日天])", in: text).first {
                let target = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6][m[2]]!
                let week = HabitCalendar.week(containing: now, calendar: calendar)
                let shift = m[1] == "下下周" ? 14 : m[1] == "下周" ? 7 : 0
                day = calendar.date(byAdding: .day, value: shift, to: week[target])!
                if shift == 0 && (m[1] == "周" || m[1] == "星期") && day < calendar.startOfDay(for: now) {
                    day = calendar.date(byAdding: .day, value: 7, to: day)!
                }
                hasDay = true
                text = text.replacingOccurrences(of: m[0], with: "")
            } else {
                for (word, offset) in [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0), ("今晚", 0)] where text.contains(word) {
                    day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
                    hasDay = true
                    text = text.replacingOccurrences(of: word, with: word == "今晚" ? "晚上" : "")
                    break
                }
            }
            var hour: Int?
            var minute = 0
            var period = ""
            if let m = matches("(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)?\\s*([0-9]{1,2})[:：]([0-9]{2})", in: text).first {
                period = m[1]; hour = Int(m[2]); minute = Int(m[3]) ?? 0
                text = text.replacingOccurrences(of: m[0], with: "")
            } else if let m = matches("(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)?\\s*([0-9零〇一二两三四五六七八九十]+)(?:点|时)(半|一刻|三刻|[0-9零〇一二两三四五六七八九十]+分?)?", in: text).first {
                period = m[1]; hour = Self.number(m[2])
                let suffix = m[3].replacingOccurrences(of: "分", with: "")
                minute = suffix == "半" ? 30 : suffix == "一刻" ? 15 : suffix == "三刻" ? 45 : Self.number(suffix) ?? 0
                text = text.replacingOccurrences(of: m[0], with: "")
            }
            if var h = hour {
                if ["下午", "傍晚", "晚上", "夜里"].contains(period) && h < 12 { h += 12 }
                if period == "中午" && h < 11 { h += 12 }
                if period == "凌晨" && h == 12 { h = 0 }
                if h < 24 && h >= 0 && minute < 60 && minute >= 0 && !invalidDate {
                    due = calendar.date(bySettingHour: h, minute: minute, second: 0, of: day)
                    if !hasDay, let value = due, value < now {
                        due = calendar.date(byAdding: .day, value: 1, to: value)
                        warnings.append("未指定日期，已取下一次这个时间，请核对。")
                    }
                    if period.isEmpty && h > 0 && h < 12 { warnings.append("未说明上午或下午，请核对时间。") }
                } else { invalidDate = true }
            } else if hasDay && !invalidDate {
                due = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)
                warnings.append("只识别到日期，暂设 18:00，请确认具体时间。")
            }
        }
        if invalidDate { due = nil; warnings.append("日期或时间无效，请手动设置截止时间。") }
        if let due, due < now { warnings.append("截止时间已经过去，请确认。") }
        for prefix in ["请帮我", "帮我", "提醒我", "请"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count); break }
        if text.contains("提醒") { warnings.append("提醒要求未完全识别，请检查提醒选项。") }
        if due == nil && original.range(of: "明天|后天|下周|周末|月底|下个月|上午|下午|晚上|截止|[0-9一二两三四五六七八九十](?:点|时)|[:：][0-9]|(?:分钟|小时|天)后", options: .regularExpression) != nil {
            warnings.append("部分时间表达未识别，请手动设置截止时间。")
        }
        var priority: TaskPriority = .normal
        if text.contains("高优先级") || text.contains("紧急") {
            priority = .high
            text = text.replacingOccurrences(of: "高优先级", with: "").replacingOccurrences(of: "紧急", with: "")
        }
        text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。；;，")))
        for prefix in ["请帮我", "帮我", "提醒我", "请"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count); break }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = original; warnings.append("未提取到任务名称，请修改。") }
        return ParsedTask(draft: TaskDraft(title: text, dueDate: due, priority: priority, reminderOffsets: offsets), warnings: warnings)
    }
    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }
    static func number(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        guard !text.isEmpty else { return nil }
        if let index = text.firstIndex(of: "百") {
            let before = String(text[..<index]); let after = String(text[text.index(after:index)...]).trimmingCharacters(in: CharacterSet(charactersIn: "零〇"))
            guard before.count == 1, let hundreds = digits[before.first!], hundreds > 0 else { return nil }
            guard let rest = after.isEmpty ? 0 : number(after) else { return nil }
            return hundreds * 100 + rest
        }
        if let index = text.firstIndex(of: "十") {
            let before = String(text[..<index]); let after = String(text[text.index(after:index)...])
            guard (before.isEmpty || before.count == 1), (after.isEmpty || after.count == 1) else { return nil }
            let tens = before.isEmpty ? 1 : digits[before.first!] ?? -100
            let ones = after.isEmpty ? 0 : digits[after.first!] ?? -100
            return tens >= 0 && ones >= 0 ? tens * 10 + ones : nil
        }
        return text.count == 1 ? digits[text.first!] : nil
    }
}
