import Foundation

/// Repeats the Alert for an Event that has started until it's acknowledged (ALR-12).
///
/// From the start time it fires every `interval`, for up to ``window`` (10 minutes),
/// until the Event is clicked or Dismissed. If the Mac slept through several slots,
/// it fires once for the latest one.
public struct EventNudgeScheduler: Sendable {
    public static let window: TimeInterval = 10 * 60

    /// Event ID → the slot it last fired for.
    private var lastNudge: [Item.ID: Date] = [:]

    public init() {}

    /// The Events to nudge now.
    ///
    /// - Parameters:
    ///   - events: today's Events.
    ///   - acknowledged: Events the user has clicked or Dismissed.
    ///   - interval: minutes between nudges. 0 turns repeating off.
    public mutating func due(_ events: [Item], acknowledged: Set<Item.ID>, intervalMinutes: Int, now: Date) -> [Item] {
        guard intervalMinutes > 0 else {
            lastNudge = [:]
            return []
        }
        let interval = TimeInterval(intervalMinutes * 60)
        var result: [Item] = []
        var current: Set<Item.ID> = []

        for event in events {
            guard let details = event.event, !details.isAllDay else { continue }
            current.insert(event.id)
            let elapsed = now.timeIntervalSince(details.start)
            guard elapsed >= 0, elapsed <= Self.window, now < details.end, !acknowledged.contains(event.id) else { continue }

            // The latest slot at or before now: start, start + interval, …
            let slot = details.start.addingTimeInterval((elapsed / interval).rounded(.down) * interval)
            if lastNudge[event.id].map({ $0 < slot }) ?? true {
                lastNudge[event.id] = slot
                result.append(event)
            }
        }
        lastNudge = lastNudge.filter { current.contains($0.key) }
        return result.sorted { $0.date < $1.date }
    }
}
