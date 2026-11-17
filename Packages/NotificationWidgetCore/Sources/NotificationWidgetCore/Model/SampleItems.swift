import Foundation

/// Hard-coded Items for building and checking the Panel without real Sources.
///
/// The app uses these instead of real Sources when launched with
/// `-UseSampleItems YES`, and SwiftUI previews use them too.
public enum SampleItems {
    public static func items(now: Date = Date(), calendar: Calendar = .current) -> [Item] {
        events(now: now, calendar: calendar) + messages(now: now) + emails(now: now)
    }

    public static func events(now: Date, calendar: Calendar = .current) -> [Item] {
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        func event(_ id: String, _ title: String, startsIn minutes: Double, lasting duration: Double) -> Item {
            let start = now.addingTimeInterval(minutes * 60)
            let end = start.addingTimeInterval(duration * 60)
            return Item(
                id: .init(source: .googleCalendar, value: id),
                kind: .event,
                title: title,
                date: start,
                expiresAt: end,
                openURL: URL(string: "https://calendar.google.com/calendar/r"),
                event: EventDetails(start: start, end: end, isAllDay: false, reminderMinutes: [10])
            )
        }

        return [
            Item(
                id: .init(source: .googleCalendar, value: "sample-all-day"),
                kind: .event,
                title: "Company offsite",
                date: startOfDay,
                expiresAt: endOfDay,
                openURL: URL(string: "https://calendar.google.com/calendar/r"),
                event: EventDetails(start: startOfDay, end: endOfDay, isAllDay: true, reminderMinutes: [])
            ),
            event("sample-standup", "Team stand-up", startsIn: 12, lasting: 15),
            event("sample-design", "Design review", startsIn: 75, lasting: 60),
            event("sample-1-1", "1:1 with manager", startsIn: 180, lasting: 30),
        ]
    }

    public static func messages(now: Date) -> [Item] {
        let samples: [(ItemKind, String, String)] = [
            (.dm, "Priya Shah · DM", "Have you got five minutes to look at the release notes before I send them?"),
            (.mention, "Sam Lee · #platform", "@you can you check the deploy pipeline? It failed twice this morning"),
            (.dm, "Jordan Kim · DM", "Thanks for the review!"),
            (.mention, "Alex Chen · #design", "Replied in thread: I think the second option reads better"),
            (.dm, "Taylor, Morgan · DM", "Lunch at 1?"),
            (.mention, "Robin Diaz · #ops", "@you heads up, the on-call rota changed"),
            (.dm, "Casey Wu · DM", "Got the slides, thanks"),
        ]
        return samples.enumerated().map { index, sample in
            Item(
                id: .init(source: .slack, value: "sample-message-\(index)"),
                kind: sample.0,
                title: sample.2,
                detail: sample.1,
                date: now.addingTimeInterval(Double(-index) * 600),
                openURL: URL(string: "slack://open")
            )
        }
    }

    public static func emails(now: Date) -> [Item] {
        let samples: [(String, String)] = [
            ("Payroll", "Your November payslip is ready"),
            ("Jamie Fox", "Quarterly planning: agenda"),
            ("GitHub", "[notification-widget] CI passed on main"),
        ]
        return samples.enumerated().map { index, sample in
            Item(
                id: .init(source: .gmail, value: "sample-email-\(index)"),
                kind: .email,
                title: sample.1,
                detail: sample.0,
                date: now.addingTimeInterval(Double(-index) * 1800),
                openURL: URL(string: "https://mail.google.com/mail/u/0/#inbox")
            )
        }
    }
}
