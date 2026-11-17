import Foundation

/// Schedules Event Alerts at their Reminder Time (ALR-6).
///
/// The Reminder Time is the Event's popup reminder (its own override or the calendar's
/// default), or 10 minutes before the start if it has none. With several reminders, the
/// earliest one still in the future is used. Each Event Alerts once.
///
/// The app calls ``schedule(_:now:)`` after every Calendar poll and ``due(now:)``
/// regularly and on wake, so the time is always re-evaluated against the real clock.
public struct ReminderScheduler: Sendable {
    public static let defaultLeadMinutes = 10

    /// Event ID → when its Alert fires.
    public private(set) var scheduled: [Item.ID: Date] = [:]
    private var events: [Item.ID: Item] = [:]
    private var fired: Set<Item.ID> = []

    public init() {}

    /// The Reminder Time for `event` that's still ahead of `now`, if any.
    public static func reminderTime(for event: Item, now: Date) -> Date? {
        guard let details = event.event, !details.isAllDay else { return nil }
        let minutes = details.reminderMinutes.isEmpty ? [defaultLeadMinutes] : details.reminderMinutes
        return minutes
            .map { details.start.addingTimeInterval(-Double($0) * 60) }
            .filter { $0 > now }
            .min()
    }

    /// Replaces the schedule with the latest Events. Events that changed are rescheduled;
    /// ones whose Reminder Time has already passed (for example loaded at launch) are skipped.
    public mutating func schedule(_ items: [Item], now: Date) {
        let current = items.filter { $0.kind == .event && $0.event?.isAllDay == false }
        let previous = events
        events = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        var updated: [Item.ID: Date] = [:]
        for event in current where !fired.contains(event.id) {
            let unchanged = previous[event.id]?.event?.start == event.event?.start
                && previous[event.id]?.event?.reminderMinutes == event.event?.reminderMinutes
            if unchanged, let existing = scheduled[event.id] {
                // Keep it, even if it's just become due, so a poll can't skip a reminder.
                updated[event.id] = existing
            } else if let time = Self.reminderTime(for: event, now: now) {
                updated[event.id] = time
            }
        }
        scheduled = updated
        // Forget fired Events that have gone, so the set doesn't grow.
        fired.formIntersection(Set(events.keys))
    }

    /// The Events whose Reminder Time has come. Each is returned once.
    ///
    /// A reminder that fell while the Mac was asleep still fires on wake if the Event
    /// hasn't started; otherwise it's dropped.
    public mutating func due(now: Date) -> [Item] {
        var result: [Item] = []
        for (id, time) in scheduled where time <= now {
            scheduled[id] = nil
            fired.insert(id)
            if let event = events[id], let start = event.event?.start, now < start {
                result.append(event)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// The next time ``due(now:)`` needs calling.
    public var nextFireDate: Date? { scheduled.values.min() }
}
