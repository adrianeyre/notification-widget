import Foundation
import Testing
@testable import NotificationWidgetCore

struct FakeCalendarAPI: CalendarEventsFetching {
    var list: CalendarEventList
    func fetchEvents(from start: Date, to end: Date) async throws -> CalendarEventList { list }
}

@Suite("Calendar Events")
struct CalendarTests {
    let mapper = CalendarEventMapper(calendar: utcCalendar)

    func fixtureItems() throws -> [Item] {
        let list = try JSONDecoder().decode(CalendarEventList.self, from: Fixture.data("calendar-events"))
        return mapper.items(from: list)
    }

    @Test("Declined, cancelled and working-location Events are left out")
    func declinedFiltering() throws {
        let ids = try fixtureItems().map(\.id.value)
        #expect(ids == ["standup_20261117", "offsite", "review"])
    }

    @Test("Another attendee declining doesn't hide the Event")
    func otherAttendeeDeclined() throws {
        #expect(try fixtureItems().contains { $0.id.value == "standup_20261117" })
    }

    @Test("All-day Events are split into the header")
    func allDaySplit() throws {
        let items = try fixtureItems()
        let offsite = try #require(items.first { $0.id.value == "offsite" })
        #expect(offsite.event?.isAllDay == true)
        #expect(offsite.event?.start == utcCalendar.date(from: DateComponents(year: 2026, month: 11, day: 17)))
        #expect(offsite.event?.end == utcCalendar.date(from: DateComponents(year: 2026, month: 11, day: 18)))

        let sections = PanelSections(visibleItems: items)
        #expect(sections.events.allDay.map(\.id.value) == ["offsite"])
        #expect(sections.events.timed.items.map(\.id.value) == ["standup_20261117", "review"])
    }

    @Test("Timed Events keep start, end, title and open link")
    func timedFields() throws {
        let standup = try #require(try fixtureItems().first { $0.id.value == "standup_20261117" })
        #expect(standup.title == "Team stand-up")
        #expect(standup.date == ISO8601DateFormatter().date(from: "2026-11-17T09:30:00Z"))
        #expect(standup.expiresAt == ISO8601DateFormatter().date(from: "2026-11-17T09:45:00Z"))
        #expect(standup.openURL?.absoluteString == "https://www.google.com/calendar/event?eid=c3RhbmR1cA")
    }

    @Test("Reminders: overrides when set, calendar defaults otherwise, popup only")
    func reminders() throws {
        let items = try fixtureItems()
        #expect(items.first { $0.id.value == "standup_20261117" }?.event?.reminderMinutes == [10])
        #expect(items.first { $0.id.value == "review" }?.event?.reminderMinutes == [1, 5])
        #expect(items.first { $0.id.value == "offsite" }?.event?.reminderMinutes == [])
    }

    @MainActor
    @Test("Ended Events are removed by the store's clock")
    func endedRemoved() async throws {
        let list = try JSONDecoder().decode(CalendarEventList.self, from: Fixture.data("calendar-events"))
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        let source = CalendarSource(api: FakeCalendarAPI(list: list), store: store, calendar: utcCalendar)

        try await source.refresh(now: referenceNow)
        #expect(store.sections.events.timed.items.map(\.id.value) == ["standup_20261117", "review"])

        // Stand-up ends at 09:45 UTC.
        store.tick(now: ISO8601DateFormatter().date(from: "2026-11-17T09:45:00Z")!)
        #expect(store.sections.events.timed.items.map(\.id.value) == ["review"])
        #expect(store.sections.events.allDay.map(\.id.value) == ["offsite"])
    }

    @MainActor
    @Test("A Dismissed Event stays hidden after the next poll")
    func dismissedEvent() async throws {
        let list = try JSONDecoder().decode(CalendarEventList.self, from: Fixture.data("calendar-events"))
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        let source = CalendarSource(api: FakeCalendarAPI(list: list), store: store, calendar: utcCalendar)
        try await source.refresh(now: referenceNow)

        store.dismiss(.init(source: .googleCalendar, value: "review"))
        try await source.refresh(now: referenceNow)

        #expect(!store.visibleItems.contains { $0.id.value == "review" })
    }

    @Test("Countdown shows only within 15 minutes of the start", arguments: [
        (16 * 60.0, false),
        (15 * 60.0, true),
        (60.0, true),
        (0.0, false),
        (-60.0, false),
    ])
    func countdownThreshold(secondsUntilStart: Double, shows: Bool) {
        let start = referenceNow.addingTimeInterval(secondsUntilStart)
        #expect((EventCountdown.remaining(until: start, now: referenceNow) != nil) == shows)
    }

    @Test("Countdown text is minutes and seconds")
    func countdownText() {
        #expect(EventCountdown.text(remaining: 14 * 60 + 5) == "in 14:05")
        #expect(EventCountdown.text(remaining: 0.4) == "in 0:01")
    }

    @Test("The request expands recurring Events and asks for today only")
    func requestURL() throws {
        let api = GoogleCalendarAPI(client: GoogleAuthorizedClient(tokenProvider: FakeTokenProvider(), transport: FakeTransport()))
        let start = utcCalendar.startOfDay(for: referenceNow)
        let url = api.url(from: start, to: start.addingTimeInterval(86_400), pageToken: nil)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/calendar/v3/calendars/primary/events")
        #expect(query.contains(URLQueryItem(name: "singleEvents", value: "true")))
        #expect(query.contains(URLQueryItem(name: "timeMin", value: "2026-11-17T00:00:00Z")))
        #expect(query.contains(URLQueryItem(name: "timeMax", value: "2026-11-18T00:00:00Z")))
    }
}
