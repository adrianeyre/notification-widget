import Foundation
import Observation

/// The Panel's reaction to new Items from one Source. How it's shown (sound, shake,
/// raising the Panel) is decided separately by ``AlertPresentationPolicy``.
public struct Alert: Equatable, Sendable {
    public var source: Source
    public var items: [Item]
    public var firedAt: Date

    public init(source: Source, items: [Item], firedAt: Date) {
        self.source = source
        self.items = items
        self.firedAt = firedAt
    }
}

/// Decides **when** an Alert fires (ALR-4, ALR-5, ALR-8, ITM-5).
///
/// - An Item the engine has never seen, arriving outside a Backfill, Alerts for its Source.
/// - Items loaded during a Backfill are recorded as seen and never Alert.
/// - Each Item Alerts at most once.
/// - Alerts for the same Source within ``coalescingWindow`` of the last one are combined
///   into it: the extra Items are highlighted, but no second Alert fires.
/// - Every Item that Alerts stays highlighted until it's clicked or Dismissed.
///
/// Events don't Alert when they arrive; they Alert at their Reminder Time through
/// ``reminderDue(_:)`` (ALR-6).
@MainActor
@Observable
public final class AlertEngine {
    public static let coalescingWindow: TimeInterval = 10

    public private(set) var highlightedIDs: Set<Item.ID> = []
    /// Items the user has clicked or Dismissed. Stops repeat Event Alerts (ALR-12).
    public private(set) var acknowledgedIDs: Set<Item.ID> = []

    @ObservationIgnored private var seenIDs: Set<Item.ID> = []
    @ObservationIgnored private var alertedIDs: Set<Item.ID> = []
    @ObservationIgnored private var lastAlertAt: [Source: Date] = [:]
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var continuations: [UUID: AsyncStream<Alert>.Continuation] = [:]

    /// Called for every Alert, after it's added to ``alerts()``.
    @ObservationIgnored public var onAlert: ((Alert) -> Void)?

    public init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    /// A stream of every Alert from now on, for sound, shake and other presentation.
    public func alerts() -> AsyncStream<Alert> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// Records a Source's current Items. Returns the Alert that fired, if any.
    @discardableResult
    public func itemsArrived(_ items: [Item], from source: Source, isBackfill: Bool) -> Alert? {
        let new = items.filter { !seenIDs.contains($0.id) }
        seenIDs.formUnion(new.map(\.id))
        guard !isBackfill, source != .googleCalendar else { return nil }
        return raise(new, source: source)
    }

    /// Fires an Alert for Events whose Reminder Time has come (ALR-6). Not affected by Backfill.
    @discardableResult
    public func reminderDue(_ events: [Item]) -> Alert? {
        seenIDs.formUnion(events.map(\.id))
        return raise(events, source: .googleCalendar)
    }

    public func isHighlighted(_ id: Item.ID) -> Bool {
        highlightedIDs.contains(id)
    }

    /// Clears the highlight when the Item is clicked or Dismissed, and records it as acknowledged.
    public func clearHighlight(_ id: Item.ID) {
        highlightedIDs.remove(id)
        acknowledgedIDs.insert(id)
    }

    /// Repeats the Alert for Events that have started and aren't acknowledged yet (ALR-12).
    /// The one deliberate exception to Alerts firing once; the caller decides the timing.
    @discardableResult
    public func nudge(_ events: [Item]) -> Alert? {
        let pending = events.filter { !acknowledgedIDs.contains($0.id) }
        guard !pending.isEmpty else { return nil }
        seenIDs.formUnion(pending.map(\.id))
        alertedIDs.formUnion(pending.map(\.id))
        highlightedIDs.formUnion(pending.map(\.id))
        return emit(Alert(source: .googleCalendar, items: pending, firedAt: clock()))
    }

    private func raise(_ items: [Item], source: Source) -> Alert? {
        let fresh = items.filter { alertedIDs.insert($0.id).inserted }
        guard !fresh.isEmpty else { return nil }
        highlightedIDs.formUnion(fresh.map(\.id))

        let now = clock()
        if let last = lastAlertAt[source], now.timeIntervalSince(last) < Self.coalescingWindow {
            return nil
        }
        lastAlertAt[source] = now

        return emit(Alert(source: source, items: fresh, firedAt: now))
    }

    private func emit(_ alert: Alert) -> Alert {
        for continuation in continuations.values {
            continuation.yield(alert)
        }
        onAlert?(alert)
        return alert
    }
}
