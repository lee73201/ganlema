import Foundation

/// Recognition providers may emit an empty final result after useful partial results.
/// An empty callback is not an instruction to erase a user's captured words.
public struct SpeechTranscriptBuffer {
    public enum Ending: Equatable { case complete, partial, empty }
    public private(set) var text = ""
    public init() {}

    @discardableResult public mutating func accept(_ candidate: String?) -> Bool {
        guard let next = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !next.isEmpty else { return false }
        text = next
        return true
    }
    public func ending(isFinal: Bool, hasError: Bool) -> Ending {
        if text.isEmpty { return .empty }
        return isFinal && !hasError ? .complete : .partial
    }
}
