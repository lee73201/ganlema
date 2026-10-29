import AppKit
import Combine
import UserNotifications
import FocusDockCore

@MainActor
final class NativeReminderService: NSObject, ObservableObject, ReminderService, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "提醒尚未启用"
    @Published private(set) var isAuthorized = false
    @Published private(set) var isDenied = false
    @Published private(set) var settingsOpenFailed = false
    @Published private(set) var pendingCount = 0
    private let center: UNUserNotificationCenter
    private var desired: [PlannedReminder] = []
    private var activeTaskIDs: Set<String> = []
    private var revision = 0
    private var worker: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    var onOpen: ((UUID?) -> Void)?
    override init() {
        center = .current()
        super.init()
        center.delegate = self
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.revision += 1; self?.startSync() }
        }
    }
    deinit { if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) } }
    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isDenied = settings.authorizationStatus == .denied
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        status = isAuthorized ? "系统提醒已启用" : settings.authorizationStatus == .denied ? "系统提醒被关闭，可在系统设置中开启" : "提醒尚未启用，点击启用"
    }
    func refreshAndSync() async { await refreshAuthorization(); revision += 1; startSync() }
    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        settingsOpenFailed = !NSWorkspace.shared.open(url)
    }
    func enableOrOpenSettings() async {
        await refreshAuthorization()
        if isDenied { openSettings() } else { await enable() }
    }
    func enable() async {
        await refreshAuthorization()
        if isDenied { return }
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
            if allowed { revision += 1; startSync() }
        } catch { status = "无法启用提醒：\(error.localizedDescription)" }
    }
    func update(items: [TodoItem]) {
        let now = Date()
        activeTaskIDs = Set(items.filter { !$0.isCompleted }.map { $0.id.uuidString })
        desired = items.filter { !$0.isCompleted }.flatMap { item -> [PlannedReminder] in
            guard let due = item.dueDate else { return [] }
            return ReminderPlan.make(taskID: item.id, title: item.title, dueDate: due, offsets: item.reminderOffsets, now: now)
        }.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        revision += 1
        startSync()
    }
    private func startSync() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            var processed = -1
            while processed != self.revision {
                processed = self.revision
                await self.reconcile(self.desired, activeIDs: self.activeTaskIDs)
            }
            self.worker = nil
        }
    }
    private func reconcile(_ all: [PlannedReminder], activeIDs: Set<String>) async {
        await refreshAuthorization()
        // Bound the queue, keeping the next reminders; replenish periodically and on wake.
        let plan = isAuthorized ? Array(all.filter { $0.fireDate > .now }.prefix(60)) : []
        let existing = await center.pendingNotificationRequests()
        let change = ReminderQueueChange(desired: plan, pending: existing.map {
            PendingReminderSnapshot(id: $0.identifier, title: $0.content.title, body: $0.content.body, fireDate: ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        }, body: Self.body)
        center.removePendingNotificationRequests(withIdentifiers: change.removeIDs)
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            $0.request.identifier.hasPrefix("ganlema.") && !activeIDs.contains($0.request.content.userInfo["taskID"] as? String ?? "")
        }.map { $0.request.identifier })
        guard isAuthorized else { pendingCount = 0; return }
        var errors = 0
        for reminder in change.upsert {
            let body = Self.body(reminder)
            let content = UNMutableNotificationContent()
            content.title = reminder.title; content.body = body; content.sound = .default
            content.userInfo = ["taskID": reminder.taskID.uuidString]
            // Absolute dates survive a timezone change without moving the deadline.
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            components.calendar = calendar; components.timeZone = calendar.timeZone
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do { try await center.add(request) } catch { errors += 1 }
        }
        pendingCount = (await center.pendingNotificationRequests()).filter { $0.identifier.hasPrefix("ganlema.") }.count
        status = errors > 0 ? "有 \(errors) 条提醒未能安排，请重试" : all.count > 60 ? "已安排最近 \(pendingCount) 条提醒，运行中自动补充" : "已安排 \(pendingCount) 条系统提醒"
    }
    private static func body(_ reminder: PlannedReminder) -> String {
        "\(ReminderPlan.label(reminder.offset)) · 截止 \(reminder.dueDate.formatted(.dateTime.month().day().hour().minute()))"
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["taskID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in self?.onOpen?(id) }
        completionHandler()
    }
}
