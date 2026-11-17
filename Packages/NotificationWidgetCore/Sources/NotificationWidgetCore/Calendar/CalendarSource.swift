import Foundation

/// The Google Calendar Source: fetches today's Events and hands them to the Item store.
///
/// The app calls ``refresh(now:)`` about every 5 minutes. Ended Events leave the
/// Panel through the store's clock (``ItemStore/tick(now:)``), which ticks more often.
@MainActor
public final class CalendarSource {
    public static let pollInterval: Duration = .seconds(5 * 60)

    private let api: CalendarEventsFetching
    private let store: ItemStore
    private let mapper: CalendarEventMapper

    public init(api: CalendarEventsFetching, store: ItemStore, calendar: Calendar = .current) {
        self.api = api
        self.store = store
        self.mapper = CalendarEventMapper(calendar: calendar)
    }

    /// Fetches today's Events and replaces the Source's Items with them.
    public func refresh(now: Date = Date()) async throws {
        let startOfDay = mapper.calendar.startOfDay(for: now)
        let endOfDay = mapper.calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let list = try await api.fetchEvents(from: startOfDay, to: endOfDay)
        store.replaceItems(mapper.items(from: list), from: .googleCalendar)
    }
}
