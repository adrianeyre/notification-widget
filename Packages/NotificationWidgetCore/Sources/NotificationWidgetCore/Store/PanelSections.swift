import Foundation

/// What one section of the Panel shows: at most `limit` Items plus a "+N more" count (PNL-5).
public struct SectionContent: Equatable, Sendable {
    public static let limit = 5

    public var items: [Item]
    public var moreCount: Int

    public init(items: [Item], moreCount: Int) {
        self.items = items
        self.moreCount = moreCount
    }

    public init(all: [Item], limit: Int = SectionContent.limit) {
        items = Array(all.prefix(limit))
        moreCount = max(0, all.count - limit)
    }

    public var isEmpty: Bool { items.isEmpty }

    public static let empty = SectionContent(items: [], moreCount: 0)
}

/// The Events section: all-day Events in a compact header (SRC-6), then timed Events
/// in start order with the next one shown prominently.
public struct EventsSection: Equatable, Sendable {
    public var allDay: [Item]
    public var timed: SectionContent

    public init(allDay: [Item], timed: SectionContent) {
        self.allDay = allDay
        self.timed = timed
    }

    /// The Event to show prominently: the first timed Event that hasn't ended.
    public var next: Item? { timed.items.first }

    public var isEmpty: Bool { allDay.isEmpty && timed.isEmpty }
}

/// Everything the Panel shows, in Panel order: Events, then DMs and Mentions, then Emails (PNL-5).
public struct PanelSections: Equatable, Sendable {
    public var events: EventsSection
    public var messages: SectionContent
    public var emails: SectionContent

    public init(events: EventsSection, messages: SectionContent, emails: SectionContent) {
        self.events = events
        self.messages = messages
        self.emails = emails
    }

    /// Groups visible Items into sections and orders each one.
    public init(visibleItems: [Item]) {
        let events = visibleItems.filter { $0.kind == .event }
        let allDay = events
            .filter { $0.event?.isAllDay == true }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let timed = events
            .filter { $0.event?.isAllDay != true }
            .sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        let messages = visibleItems
            .filter { $0.kind == .dm || $0.kind == .mention }
            .sorted { $0.date > $1.date }
        let emails = visibleItems
            .filter { $0.kind == .email }
            .sorted { $0.date > $1.date }

        self.init(
            events: EventsSection(allDay: allDay, timed: SectionContent(all: timed)),
            messages: SectionContent(all: messages),
            emails: SectionContent(all: emails)
        )
    }
}
