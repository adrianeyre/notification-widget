import Foundation

/// The two tokens pasted into Settings (SRC-1a): the user token reads messages, the
/// app-level token opens the Socket Mode connection (ADR 0002).
public struct SlackCredentials: Codable, Equatable, Sendable {
    public var userToken: String
    public var appToken: String

    public init(userToken: String, appToken: String) {
        self.userToken = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A message explaining what's wrong with the tokens' shape, or `nil` if they look right.
    public var formatProblem: String? {
        if !userToken.hasPrefix("xoxp-") { return "The user token should start with xoxp-." }
        if !appToken.hasPrefix("xapp-") { return "The app-level token should start with xapp-." }
        return nil
    }
}

/// Who the user token belongs to, from `auth.test`.
public struct SlackIdentity: Codable, Equatable, Sendable {
    public var userID: String
    public var userName: String
    public var teamID: String
    public var teamName: String

    public init(userID: String, userName: String, teamID: String, teamName: String) {
        self.userID = userID
        self.userName = userName
        self.teamID = teamID
        self.teamName = teamName
    }

    public var account: Account {
        Account(sources: [.slack], identifier: "\(teamID):\(userID)", displayName: "\(userName) · \(teamName)")
    }
}

/// A Slack message, from a Socket Mode event or from `conversations.history`.
public struct SlackMessage: Decodable, Equatable, Sendable {
    public var type: String?
    public var subtype: String?
    public var channel: String?
    /// `im`, `mpim`, `channel` or `group`. Only set on events.
    public var channelType: String?
    public var user: String?
    public var botID: String?
    public var text: String?
    public var ts: String
    public var threadTS: String?
    /// Thread parents in history list who has replied.
    public var replyUsers: [String]?
    public var latestReply: String?
    /// Set on `message_deleted`.
    public var deletedTS: String?

    public init(
        type: String? = "message",
        subtype: String? = nil,
        channel: String? = nil,
        channelType: String? = nil,
        user: String?,
        botID: String? = nil,
        text: String?,
        ts: String,
        threadTS: String? = nil,
        replyUsers: [String]? = nil,
        latestReply: String? = nil,
        deletedTS: String? = nil
    ) {
        self.type = type
        self.subtype = subtype
        self.channel = channel
        self.channelType = channelType
        self.user = user
        self.botID = botID
        self.text = text
        self.ts = ts
        self.threadTS = threadTS
        self.replyUsers = replyUsers
        self.latestReply = latestReply
        self.deletedTS = deletedTS
    }

    enum CodingKeys: String, CodingKey {
        case type, subtype, channel, user, text, ts
        case channelType = "channel_type"
        case botID = "bot_id"
        case threadTS = "thread_ts"
        case replyUsers = "reply_users"
        case latestReply = "latest_reply"
        case deletedTS = "deleted_ts"
    }

    /// When the message was sent.
    public var date: Date { SlackTimestamp.date(ts) }
}

/// A conversation: a DM, a group DM, or a channel.
public struct SlackConversation: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var isIM: Bool?
    public var isMPIM: Bool?
    /// For a DM, the other person.
    public var user: String?
    /// The last message the user has read.
    public var lastRead: String?
    /// When the conversation last changed, in milliseconds or seconds since 1970.
    public var updated: Double?

    public init(id: String, name: String? = nil, isIM: Bool? = nil, isMPIM: Bool? = nil, user: String? = nil, lastRead: String? = nil, updated: Double? = nil) {
        self.id = id
        self.name = name
        self.isIM = isIM
        self.isMPIM = isMPIM
        self.user = user
        self.lastRead = lastRead
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey {
        case id, name, user, updated
        case isIM = "is_im"
        case isMPIM = "is_mpim"
        case lastRead = "last_read"
    }

    public var isDirect: Bool { isIM == true || isMPIM == true }

    public var updatedDate: Date? {
        guard let updated else { return nil }
        // Slack sends milliseconds for `updated`; tolerate seconds too.
        return Date(timeIntervalSince1970: updated > 10_000_000_000 ? updated / 1000 : updated)
    }
}

public enum SlackTimestamp {
    public static func date(_ ts: String) -> Date {
        Date(timeIntervalSince1970: Double(ts) ?? 0)
    }

    public static func string(_ date: Date) -> String {
        String(format: "%.6f", date.timeIntervalSince1970)
    }

    /// `a` is at or before `b`. Slack timestamps compare as numbers.
    public static func isAtOrBefore(_ a: String, _ b: String) -> Bool {
        (Double(a) ?? 0) <= (Double(b) ?? 0)
    }
}
