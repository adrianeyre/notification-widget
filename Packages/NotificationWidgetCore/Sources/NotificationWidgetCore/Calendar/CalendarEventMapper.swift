import Foundation

/// Turns Google Calendar events into Event Items (SRC-5, SRC-6).
public struct CalendarEventMapper: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Maps every Event the user is attending. Leaves out cancelled Events, Events
    /// the user has declined, and working-location entries.
    public func items(from list: CalendarEventList) -> [Item] {
        list.items.compactMap { item(from: $0, defaultReminders: list.defaultReminders ?? []) }
    }

    func item(from event: CalendarEvent, defaultReminders: [CalendarReminder]) -> Item? {
        guard event.status != "cancelled",
              event.eventType != "workingLocation",
              !Self.isDeclined(event),
              let (start, end, isAllDay) = times(of: event)
        else { return nil }

        return Item(
            id: .init(source: .googleCalendar, value: event.id),
            kind: .event,
            title: event.summary?.nilIfBlank ?? "(No title)",
            date: start,
            // An Event leaves the Panel once it has ended (LIF-3).
            expiresAt: end,
            openURL: event.htmlLink.flatMap(URL.init(string:)),
            event: EventDetails(
                start: start,
                end: end,
                isAllDay: isAllDay,
                reminderMinutes: Self.reminderMinutes(for: event, defaults: defaultReminders),
                joinURL: MeetingLink.joinURL(for: event)
            )
        )
    }

    /// The user declined if their own attendee entry says so.
    static func isDeclined(_ event: CalendarEvent) -> Bool {
        event.attendees?.contains { $0.isSelf == true && $0.responseStatus == "declined" } ?? false
    }

    /// The Event's popup reminders: its own overrides, or the calendar defaults if it uses them.
    static func reminderMinutes(for event: CalendarEvent, defaults: [CalendarReminder]) -> [Int] {
        let reminders: [CalendarReminder]
        if let eventReminders = event.reminders, !eventReminders.useDefault {
            reminders = eventReminders.overrides ?? []
        } else {
            reminders = defaults
        }
        return reminders.filter { $0.method == "popup" }.map(\.minutes).sorted()
    }

    func times(of event: CalendarEvent) -> (Date, Date, Bool)? {
        if let startDateTime = event.start.dateTime, let endDateTime = event.end.dateTime {
            guard let start = Self.parseDateTime(startDateTime),
                  let end = Self.parseDateTime(endDateTime)
            else { return nil }
            return (start, end, false)
        }
        if let startDate = event.start.date, let endDate = event.end.date {
            // All-day dates are local days; the end date is exclusive.
            guard let start = parseDay(startDate), let end = parseDay(endDate) else { return nil }
            return (start, end, true)
        }
        return nil
    }

    static func parseDateTime(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// The live countdown shown when an Event is about to start (ITM-3).
public enum EventCountdown {
    /// Show the countdown when the Event starts within this many seconds.
    public static let threshold: TimeInterval = 15 * 60

    /// Seconds until `start`, if the Event starts within the threshold and hasn't started yet.
    public static func remaining(until start: Date, now: Date) -> TimeInterval? {
        let remaining = start.timeIntervalSince(now)
        guard remaining > 0, remaining <= threshold else { return nil }
        return remaining
    }

    /// For example "in 14:05", rounded up to the next whole second.
    public static func text(remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "in %d:%02d", seconds / 60, seconds % 60)
    }
}

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
