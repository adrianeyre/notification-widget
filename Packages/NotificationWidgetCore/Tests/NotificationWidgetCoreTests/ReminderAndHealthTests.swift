import Foundation
import Testing
@testable import NotificationWidgetCore

func timedEvent(_ id: String, startsIn minutes: Double, reminders: [Int] = [], allDay: Bool = false) -> Item {
    let start = referenceNow.addingTimeInterval(minutes * 60)
    let end = start.addingTimeInterval(1800)
    return Item(
        id: .init(source: .googleCalendar, value: id), kind: .event, title: id, date: start, expiresAt: end,
        event: EventDetails(start: start, end: end, isAllDay: allDay, reminderMinutes: reminders)
    )
}

@Suite("Reminder Time")
struct ReminderTimeTests {
    @Test("Uses the Event's reminder, or 10 minutes before when there is none")
    func choice() {
        #expect(ReminderScheduler.reminderTime(for: timedEvent("a", startsIn: 60, reminders: [5]), now: referenceNow)
            == referenceNow.addingTimeInterval(55 * 60))
        #expect(ReminderScheduler.reminderTime(for: timedEvent("b", startsIn: 60), now: referenceNow)
            == referenceNow.addingTimeInterval(50 * 60))
    }

    @Test("With several reminders, the earliest still in the future is used")
    func earliestFuture() {
        let event = timedEvent("a", startsIn: 20, reminders: [1, 10, 30])
        // 30 minutes before has passed; 10 minutes before is next.
        #expect(ReminderScheduler.reminderTime(for: event, now: referenceNow) == referenceNow.addingTimeInterval(10 * 60))
    }

    @Test("All-day Events never get a Reminder Time")
    func allDay() {
        #expect(ReminderScheduler.reminderTime(for: timedEvent("a", startsIn: 60, allDay: true), now: referenceNow) == nil)
    }

    @Test("Past reminders are skipped: an Event loaded after its Reminder Time doesn't Alert")
    func pastSkipped() {
        var scheduler = ReminderScheduler()
        scheduler.schedule([timedEvent("soon", startsIn: 5)], now: referenceNow)
        #expect(scheduler.scheduled.isEmpty)
        #expect(scheduler.due(now: referenceNow.addingTimeInterval(60)).isEmpty)
    }

    @Test("A Reminder Time that falls while running fires once, even for Backfilled Events")
    func firesOnce() {
        var scheduler = ReminderScheduler()
        scheduler.schedule([timedEvent("standup", startsIn: 30)], now: referenceNow)

        #expect(scheduler.due(now: referenceNow.addingTimeInterval(19 * 60)).isEmpty)
        #expect(scheduler.due(now: referenceNow.addingTimeInterval(20 * 60)).map(\.title) == ["standup"])
        #expect(scheduler.due(now: referenceNow.addingTimeInterval(21 * 60)).isEmpty)

        // The next poll returns the same Event; it must not be scheduled again.
        scheduler.schedule([timedEvent("standup", startsIn: 30)], now: referenceNow.addingTimeInterval(22 * 60))
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test("Rescheduling: a moved Event gets a new Reminder Time; a removed one is dropped")
    func rescheduling() {
        var scheduler = ReminderScheduler()
        scheduler.schedule([timedEvent("a", startsIn: 30), timedEvent("b", startsIn: 60)], now: referenceNow)
        #expect(scheduler.scheduled[.init(source: .googleCalendar, value: "a")] == referenceNow.addingTimeInterval(20 * 60))

        scheduler.schedule([timedEvent("a", startsIn: 90)], now: referenceNow.addingTimeInterval(60))

        #expect(scheduler.scheduled[.init(source: .googleCalendar, value: "a")] == referenceNow.addingTimeInterval(80 * 60))
        #expect(scheduler.scheduled[.init(source: .googleCalendar, value: "b")] == nil)
    }

    @Test("A reminder that's just come due isn't lost by a poll that lands first")
    func pollAtDueTime() {
        var scheduler = ReminderScheduler()
        scheduler.schedule([timedEvent("a", startsIn: 30)], now: referenceNow)
        scheduler.schedule([timedEvent("a", startsIn: 30)], now: referenceNow.addingTimeInterval(20 * 60 + 1))
        #expect(scheduler.due(now: referenceNow.addingTimeInterval(20 * 60 + 2)).map(\.title) == ["a"])
    }

    @Test("Wake re-evaluation: a reminder missed during sleep fires on wake if the Event hasn't started")
    func wake() {
        var scheduler = ReminderScheduler()
        scheduler.schedule([timedEvent("a", startsIn: 30), timedEvent("b", startsIn: 40)], now: referenceNow)

        // Asleep from minute 15 to minute 35: "a" (due 20, starts 30) has started; "b" (due 30, starts 40) hasn't.
        let woke = scheduler.due(now: referenceNow.addingTimeInterval(35 * 60))

        #expect(woke.map(\.title) == ["b"])
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test("The next fire date is the earliest scheduled reminder")
    func nextFire() {
        var scheduler = ReminderScheduler()
        scheduler.schedule([timedEvent("a", startsIn: 60), timedEvent("b", startsIn: 30)], now: referenceNow)
        #expect(scheduler.nextFireDate == referenceNow.addingTimeInterval(20 * 60))
    }
}

@Suite("Join links")
struct MeetingLinkTests {
    func events() throws -> [String: CalendarEvent] {
        let list = try JSONDecoder().decode(CalendarEventList.self, from: Fixture.data("calendar-meetings"))
        return Dictionary(uniqueKeysWithValues: list.items.map { ($0.id, $0) })
    }

    @Test("Extracts Meet and Zoom links from sample Events")
    func extraction() throws {
        let events = try events()
        #expect(MeetingLink.joinURL(for: events["meet"]!)?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(MeetingLink.joinURL(for: events["conference-only"]!)?.absoluteString == "https://meet.google.com/xyz-abcd-efg")
        #expect(MeetingLink.joinURL(for: events["zoom-location"]!)?.absoluteString == "https://acme.zoom.us/j/98765432100?pwd=AbCdEf123")
        #expect(MeetingLink.joinURL(for: events["zoom-description"]!)?.absoluteString == "https://zoom.us/j/1234567890?pwd=xyz&from=addon")
        #expect(MeetingLink.joinURL(for: events["no-link"]!) == nil)
    }

    @Test("The Event Item carries the Join link")
    func onItem() throws {
        let list = try JSONDecoder().decode(CalendarEventList.self, from: Fixture.data("calendar-meetings"))
        let items = CalendarEventMapper(calendar: utcCalendar).items(from: list)
        #expect(items.first { $0.id.value == "meet" }?.event?.joinURL != nil)
        #expect(items.first { $0.id.value == "no-link" }?.event?.joinURL == nil)
    }

    @Test("Zoom links convert to the Zoom app's URL")
    func zoomApp() {
        let url = URL(string: "https://acme.zoom.us/j/98765432100?pwd=AbCdEf123")!
        #expect(MeetingLink.zoomAppURL(for: url)?.absoluteString
            == "zoommtg://acme.zoom.us/join?action=join&confno=98765432100&pwd=AbCdEf123")
        #expect(MeetingLink.zoomAppURL(for: URL(string: "https://meet.google.com/abc")!) == nil)
    }
}

@Suite("Source health")
struct HealthTests {
    @Test("Poll Source: connected, then out of date after 3 missed intervals, then connected again")
    func pollTransitions() {
        var tracker = HealthTracker(pollInterval: 30)
        #expect(tracker.health(now: referenceNow) == .disconnected)

        tracker.markActive(at: referenceNow)
        #expect(tracker.health(now: referenceNow.addingTimeInterval(60)) == .connected)
        #expect(tracker.health(now: referenceNow.addingTimeInterval(91)) == .outOfDate)

        tracker.recordSuccess(at: referenceNow.addingTimeInterval(100))
        #expect(tracker.health(now: referenceNow.addingTimeInterval(150)) == .connected)
        #expect(tracker.health(now: referenceNow.addingTimeInterval(191)) == .outOfDate)
    }

    @Test("Socket Source: out of date while the socket is down")
    func socketTransitions() {
        var tracker = HealthTracker(pollInterval: 120, usesSocket: true)
        tracker.markActive(at: referenceNow)
        #expect(tracker.health(now: referenceNow) == .outOfDate)
        tracker.setSocket(up: true, at: referenceNow)
        #expect(tracker.health(now: referenceNow.addingTimeInterval(10)) == .connected)
        tracker.setSocket(up: false, at: referenceNow.addingTimeInterval(20))
        #expect(tracker.health(now: referenceNow.addingTimeInterval(21)) == .outOfDate)
    }

    @Test("Socket Source: stays connected while the socket is up, however quiet it is")
    func socketStaysConnectedWhileUp() {
        // Regression: Slack showed "Out of date" 6 minutes (3 × the read-check interval)
        // after every connect, because only the socket's hello counted as an update.
        var tracker = HealthTracker(pollInterval: 120, usesSocket: true)
        tracker.markActive(at: referenceNow)
        tracker.setSocket(up: true, at: referenceNow)
        #expect(tracker.health(now: referenceNow.addingTimeInterval(361)) == .connected)
        #expect(tracker.health(now: referenceNow.addingTimeInterval(6 * 60 * 60)) == .connected)
        tracker.setSocket(up: false, at: referenceNow.addingTimeInterval(6 * 60 * 60))
        #expect(tracker.health(now: referenceNow.addingTimeInterval(6 * 60 * 60 + 1)) == .outOfDate)
    }

    @Test("Needs sign-in and disconnected override everything")
    func signInAndDisconnect() {
        var tracker = HealthTracker(pollInterval: 30)
        tracker.recordSuccess(at: referenceNow)
        tracker.markNeedsSignIn()
        #expect(tracker.health(now: referenceNow) == .needsSignIn)
        tracker.recordSuccess(at: referenceNow.addingTimeInterval(5))
        #expect(tracker.health(now: referenceNow.addingTimeInterval(6)) == .connected)
        tracker.markDisconnected()
        #expect(tracker.health(now: referenceNow.addingTimeInterval(7)) == .disconnected)
    }

    @MainActor
    @Test("The monitor reports each Source with its own clock")
    func monitor() {
        let monitor = HealthMonitor(now: referenceNow)
        monitor.update(.gmail) { $0.recordSuccess(at: referenceNow) }
        #expect(monitor.health(for: .gmail) == .connected)
        #expect(monitor.health(for: .slack) == .disconnected)
        monitor.tick(now: referenceNow.addingTimeInterval(91))
        #expect(monitor.health(for: .gmail) == .outOfDate)
    }
}
