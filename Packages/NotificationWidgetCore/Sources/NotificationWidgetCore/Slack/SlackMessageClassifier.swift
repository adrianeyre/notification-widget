import Foundation

/// Why a Slack message becomes an Item.
public enum SlackItemReason: Equatable, Sendable {
    /// A direct message or group direct message (SRC-2).
    case dm
    /// A channel message that @mentions the user (SRC-3).
    case mention
    /// A reply in a thread the user has posted in (SRC-3).
    case threadReply
    /// A channel message containing one of the user's keywords (SRC-7).
    case keyword(String)

    public var kind: ItemKind { self == .dm ? .dm : .mention }
}

/// The threads the user has posted in, so replies in them become Mentions.
public struct ThreadTracker: Equatable, Sendable {
    public private(set) var threads: Set<String> = []

    public init() {}

    static func key(channel: String, threadTS: String) -> String { "\(channel):\(threadTS)" }

    public func contains(channel: String, threadTS: String) -> Bool {
        threads.contains(Self.key(channel: channel, threadTS: threadTS))
    }

    public mutating func insert(channel: String, threadTS: String) {
        threads.insert(Self.key(channel: channel, threadTS: threadTS))
    }

    /// Records the thread a message by the user belongs to. A top-level message by the
    /// user counts too: replies to it are replies in a thread they've posted in.
    public mutating func recordOwnMessage(_ message: SlackMessage, channel: String) {
        insert(channel: channel, threadTS: message.threadTS ?? message.ts)
    }

    /// Seeds the set from a history page during Backfill (best effort, PRD §8): thread
    /// parents the user wrote or replied to.
    public mutating func seed(from history: [SlackMessage], channel: String, selfUserID: String) {
        for message in history where message.replyUsers != nil || message.latestReply != nil {
            if message.user == selfUserID || message.replyUsers?.contains(selfUserID) == true {
                insert(channel: channel, threadTS: message.threadTS ?? message.ts)
            }
        }
    }
}

/// Matches the user's keywords as whole words, ignoring case (SRC-7).
public struct KeywordMatcher: Sendable {
    private let patterns: [(keyword: String, regex: NSRegularExpression)]

    public init(keywords: [String]) {
        patterns = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { keyword in
                let pattern = "(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: keyword))(?![\\p{L}\\p{N}_])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                return (keyword, regex)
            }
    }

    /// The first keyword found in `text`.
    public func firstMatch(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.first { $0.regex.firstMatch(in: text, range: range) != nil }?.keyword
    }
}

/// Decides whether a Slack message becomes a DM or Mention Item.
public struct SlackMessageClassifier: Sendable {
    public var selfUserID: String
    public var keywords: KeywordMatcher

    /// Subtypes that are still real messages from a person.
    static let personSubtypes: Set<String> = ["thread_broadcast", "file_share", "me_message"]

    public init(selfUserID: String, keywords: [String] = []) {
        self.selfUserID = selfUserID
        self.keywords = KeywordMatcher(keywords: keywords)
    }

    /// Whether `message` was sent by the user.
    public func isOwn(_ message: SlackMessage) -> Bool {
        message.user == selfUserID
    }

    /// Whether `message` is from another person (not the user, a bot or the system).
    public func isFromAnotherPerson(_ message: SlackMessage) -> Bool {
        if let subtype = message.subtype, !Self.personSubtypes.contains(subtype) { return false }
        guard message.botID == nil, let user = message.user, user != selfUserID else { return false }
        return true
    }

    /// `channelType` is `im`, `mpim`, `channel` or `group`.
    public func classify(_ message: SlackMessage, channel: String, channelType: String, threads: ThreadTracker) -> SlackItemReason? {
        guard isFromAnotherPerson(message) else { return nil }

        if channelType == "im" || channelType == "mpim" {
            return .dm
        }

        let text = message.text ?? ""
        if SlackText.mentionedUserIDs(in: text).contains(selfUserID) {
            return .mention
        }
        if let threadTS = message.threadTS, threadTS != message.ts, threads.contains(channel: channel, threadTS: threadTS) {
            return .threadReply
        }
        if let keyword = keywords.firstMatch(in: SlackText.plain(text)) {
            return .keyword(keyword)
        }
        return nil
    }
}
