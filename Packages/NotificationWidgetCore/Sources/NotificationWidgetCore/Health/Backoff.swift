import Foundation

/// Exponential backoff for reconnecting: 2 s, 4 s, 8 s … up to a maximum (APP-4).
public struct Backoff: Sendable, Equatable {
    public var base: TimeInterval
    public var maximum: TimeInterval
    public private(set) var attempt = 0

    public init(base: TimeInterval = 2, maximum: TimeInterval = 300) {
        self.base = base
        self.maximum = maximum
    }

    /// The delay before the next attempt. Each call doubles it, up to `maximum`.
    public mutating func nextDelay() -> TimeInterval {
        let delay = min(maximum, base * pow(2, Double(attempt)))
        attempt += 1
        return delay
    }

    /// Call after a success, so the next failure starts from `base` again.
    public mutating func reset() {
        attempt = 0
    }
}
