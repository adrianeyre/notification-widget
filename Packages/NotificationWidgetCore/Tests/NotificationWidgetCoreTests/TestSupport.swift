import Foundation
import Testing
@testable import NotificationWidgetCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

/// A fixed point in time for tests: 2026-11-17 09:00 UTC.
let referenceNow = Date(timeIntervalSince1970: 1_794_906_000)

var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

func freshDefaults() -> UserDefaults {
    let name = "NotificationWidgetCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func email(_ id: String, at date: Date = referenceNow) -> Item {
    Item(id: .init(source: .gmail, value: id), kind: .email, title: "Subject \(id)", detail: "Sender", date: date)
}

func dm(_ id: String, at date: Date = referenceNow) -> Item {
    Item(id: .init(source: .slack, value: id), kind: .dm, title: "Message \(id)", detail: "Someone · DM", date: date)
}

func event(_ id: String, start: Date, end: Date, allDay: Bool = false) -> Item {
    Item(
        id: .init(source: .googleCalendar, value: id),
        kind: .event,
        title: "Event \(id)",
        date: start,
        expiresAt: end,
        event: EventDetails(start: start, end: end, isAllDay: allDay, reminderMinutes: [])
    )
}
