import Combine
import Foundation

@MainActor public final class DeletionUndo: ObservableObject {
    public struct Entry: Identifiable {
        public let id = UUID()
        public let title: String
        public let expires: Date
        public let restore: () throws -> Void
    }
    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var now = Date()
    private var timer: AnyCancellable?
    public var latest: Entry? { entries.last }
    private let clock: () -> Date
    public init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock; now = clock()
    }
    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }; self.now = self.clock(); self.entries.removeAll { $0.expires <= self.now }
            if self.entries.isEmpty { self.timer = nil }
        }
    }
    public func offer(_ title: String, restore: @escaping () throws -> Void) {
        now = clock(); entries.removeAll { $0.expires <= now }
        entries.append(Entry(title: title, expires: now.addingTimeInterval(10), restore: restore))
        startTimer()
    }
    public func undo() throws {
        now = clock(); entries.removeAll { $0.expires <= now }
        guard let entry = entries.last else { timer = nil; return }
        try entry.restore()
        entries.removeAll { $0.id == entry.id }
        if entries.isEmpty { timer = nil }
    }
}
