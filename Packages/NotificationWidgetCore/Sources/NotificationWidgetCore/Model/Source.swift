import Foundation

/// One external service that Items come from (see GLOSSARY.md).
public enum Source: String, Codable, CaseIterable, Hashable, Sendable {
    case slack
    case gmail
    case googleCalendar

    public var displayName: String {
        switch self {
        case .slack: "Slack"
        case .gmail: "Gmail"
        case .googleCalendar: "Google Calendar"
        }
    }
}

/// The kinds of Item the Panel shows (see GLOSSARY.md, "Item kinds").
public enum ItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case dm
    case mention
    case email
    case event

    /// The Source each kind of Item comes from.
    public var source: Source {
        switch self {
        case .dm, .mention: .slack
        case .email: .gmail
        case .event: .googleCalendar
        }
    }
}

/// The user's identity on a Source: one Google account (covering Gmail and
/// Google Calendar) or one Slack workspace.
public struct Account: Codable, Hashable, Sendable {
    /// The Sources this Account gives access to.
    public var sources: Set<Source>
    /// A stable identifier: an email address for Google, a team and user ID for Slack.
    public var identifier: String
    /// What the user sees in Settings, for example the email address.
    public var displayName: String

    public init(sources: Set<Source>, identifier: String, displayName: String) {
        self.sources = sources
        self.identifier = identifier
        self.displayName = displayName
    }

    /// A Google Account covers both Gmail and Google Calendar.
    public static func google(email: String) -> Account {
        Account(sources: [.gmail, .googleCalendar], identifier: email, displayName: email)
    }
}
