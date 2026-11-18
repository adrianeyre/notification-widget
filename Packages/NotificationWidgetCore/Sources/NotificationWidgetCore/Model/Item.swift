import Foundation

/// A single thing shown in the Panel that needs the user's attention, from one Source.
///
/// Items are never persisted as the source of truth (APP-2): every Source rebuilds
/// its Items from the service, and only Dismissals are saved locally.
public struct Item: Identifiable, Hashable, Sendable {
    /// A stable identifier, unique across Sources.
    public struct ID: Hashable, Codable, Sendable, CustomStringConvertible {
        public var source: Source
        /// The identifier the Source uses, for example a Gmail message ID.
        public var value: String

        public init(source: Source, value: String) {
            self.source = source
            self.value = value
        }

        public var description: String { "\(source.rawValue):\(value)" }
    }

    public var id: ID
    public var kind: ItemKind
    /// The main line: an Email subject, an Event title, or a Slack message excerpt.
    public var title: String
    /// The secondary line: an Email sender, or a Slack sender and channel.
    public var detail: String?
    /// When the Item happened: an Email or Slack message's arrival, or an Event's start.
    public var date: Date
    /// When the Item stops being relevant and leaves the Panel, for example an Event's end (LIF-3).
    public var expiresAt: Date?
    /// Where clicking the Item takes the user (INT-1, INT-2).
    public var openURL: URL?
    /// A picture of the person behind a DM, Mention or Email: the Slack profile photo, or
    /// the sender's Gravatar. `nil` when there isn't one; the Panel then shows initials.
    public var avatarURL: URL?
    /// Event-only details. `nil` for every other kind.
    public var event: EventDetails?
    /// Slack-only details for DMs and Mentions. `nil` for every other kind.
    public var slack: SlackMessageDetails?

    public var source: Source { id.source }

    public init(
        id: ID,
        kind: ItemKind,
        title: String,
        detail: String? = nil,
        date: Date,
        expiresAt: Date? = nil,
        openURL: URL? = nil,
        avatarURL: URL? = nil,
        event: EventDetails? = nil,
        slack: SlackMessageDetails? = nil
    ) {
        precondition(kind.source == id.source, "An Item's kind must belong to its Source")
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
        self.expiresAt = expiresAt
        self.openURL = openURL
        self.avatarURL = avatarURL
        self.event = event
        self.slack = slack
    }

    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

/// The Event-specific part of an Item.
public struct EventDetails: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Minutes before the start at which the Event's reminders fire: the Event's own
    /// popup reminder overrides, or the calendar's defaults. Kept for Reminder Time Alerts.
    public var reminderMinutes: [Int]
    /// A Google Meet or Zoom link, shown as a Join button (ITM-4).
    public var joinURL: URL?

    public init(start: Date, end: Date, isAllDay: Bool, reminderMinutes: [Int], joinURL: URL? = nil) {
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.reminderMinutes = reminderMinutes
        self.joinURL = joinURL
    }
}

/// The Slack-specific part of a DM or Mention Item.
public struct SlackMessageDetails: Hashable, Sendable {
    public var channelID: String
    /// The message timestamp, which is also its ID within the conversation.
    public var ts: String
    /// The parent message's timestamp when this is a reply in a thread.
    public var threadTS: String?

    public init(channelID: String, ts: String, threadTS: String? = nil) {
        self.channelID = channelID
        self.ts = ts
        self.threadTS = threadTS
    }

    public var isThreadReply: Bool { threadTS != nil && threadTS != ts }
}
