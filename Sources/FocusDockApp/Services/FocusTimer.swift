import AppKit
import Combine
import FocusDockCore

@MainActor final class FocusTimer: ObservableObject {
    @Published private(set) var session: FocusSession?
    @Published private(set) var now = Date()
    @Published private(set) var finished = false
    private let defaults: UserDefaults
    private var tick: AnyCancellable?
    private let key = "focusSession.v1"
    init(defaults: UserDefaults) {
        self.defaults = defaults
        session = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FocusSession.self, from: $0) }
        finished = session?.isFinished(at: now) ?? false
        tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }
            self.now = date
            if self.session?.isFinished(at: date) == true && !self.finished { self.finished = true; NSSound(named: "Glass")?.play() }
        }
    }
    func start(_ item: TodoItem, minutes: Int) { session = FocusSession(taskID: item.id, taskTitle: item.title, minutes: minutes); now = .now; finished = false; persist() }
    func togglePause() {
        guard var value = session, !finished else { return }
        if value.pausedRemaining == nil { value.pause(at: .now) } else { value.resume(at: .now) }
        session = value; now = .now; persist()
    }
    func restore(_ value: FocusSession) { session = value; now = .now; finished = value.isFinished(at: now); persist() }
    func stop() { session = nil; finished = false; persist() }
    private func persist() {
        if let session, let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}
