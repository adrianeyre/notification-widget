import Foundation
import Observation

/// How a Source is doing, shown in its Panel section header (PNL-8).
public enum SourceHealth: Equatable, Sendable {
    case connected
    /// No successful update for more than 3 poll intervals, or the socket is down.
    case outOfDate
    /// No Account is connected.
    case disconnected
    /// The Account's sign-in has expired or its token was rejected.
    case needsSignIn
}

/// Works out one Source's health from what has happened to it.
public struct HealthTracker: Equatable, Sendable {
    public enum Connection: Equatable, Sendable {
        case disconnected
        case needsSignIn
        /// Connected and polling every `pollInterval`, or holding a socket.
        case active
    }

    /// The expected time between successful updates.
    public var pollInterval: TimeInterval
    /// `true` for Sources that hold a socket (Slack), where a dropped socket means out of date.
    public var usesSocket: Bool
    public private(set) var connection: Connection = .disconnected
    public private(set) var lastSuccess: Date?
    public private(set) var activeSince: Date?
    public private(set) var isSocketUp = false

    public init(pollInterval: TimeInterval, usesSocket: Bool = false) {
        self.pollInterval = pollInterval
        self.usesSocket = usesSocket
    }

    public mutating func markActive(at now: Date) {
        if connection != .active { activeSince = now }
        connection = .active
    }

    public mutating func markDisconnected() {
        connection = .disconnected
        lastSuccess = nil
        activeSince = nil
        isSocketUp = false
    }

    public mutating func markNeedsSignIn() {
        connection = .needsSignIn
        isSocketUp = false
    }

    public mutating func recordSuccess(at now: Date) {
        markActive(at: now)
        lastSuccess = now
    }

    public mutating func setSocket(up: Bool, at now: Date) {
        isSocketUp = up
        if up { recordSuccess(at: now) }
    }

    public func health(now: Date) -> SourceHealth {
        switch connection {
        case .disconnected: return .disconnected
        case .needsSignIn: return .needsSignIn
        case .active: break
        }
        if usesSocket, !isSocketUp { return .outOfDate }
        let limit = pollInterval * 3
        // Before the first success, allow the same grace period from when it connected.
        guard let reference = lastSuccess ?? activeSince else { return .outOfDate }
        return now.timeIntervalSince(reference) > limit ? .outOfDate : .connected
    }
}

/// The health of every Source, observed by the Panel.
@MainActor
@Observable
public final class HealthMonitor {
    public private(set) var trackers: [Source: HealthTracker]
    public private(set) var now: Date

    public init(now: Date = Date()) {
        self.now = now
        trackers = [
            .googleCalendar: HealthTracker(pollInterval: 5 * 60),
            .gmail: HealthTracker(pollInterval: 30),
            // Slack updates arrive over the socket; the poll interval is the read-state check.
            .slack: HealthTracker(pollInterval: 120, usesSocket: true),
        ]
    }

    public func health(for source: Source) -> SourceHealth {
        trackers[source]?.health(now: now) ?? .disconnected
    }

    public func update(_ source: Source, _ change: (inout HealthTracker) -> Void) {
        guard var tracker = trackers[source] else { return }
        change(&tracker)
        trackers[source] = tracker
    }

    public func tick(now: Date) {
        self.now = now
    }
}
