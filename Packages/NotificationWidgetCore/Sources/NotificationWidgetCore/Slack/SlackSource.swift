import Foundation

/// The Slack Source: turns Socket Mode message events into DM and Mention Items, runs the
/// Web API Backfill on launch and reconnect, and removes Items once they're read or
/// 24 hours old (SRC-2, SRC-3, SRC-7, LIF-2).
@MainActor
public final class SlackSource {
    /// How often the read state is checked (LIF-2), kept low to stay within rate limits.
    public static let readCheckInterval: Duration = .seconds(120)
    /// A DM or Mention leaves the Panel this long after it arrived, read or not (LIF-2).
    public static let itemLifetime: TimeInterval = 24 * 60 * 60
    /// Backfill limits, to stay within Slack's per-method rate limits.
    static let backfillDirectLimit = 20
    static let backfillChannelLimit = 15

    private let api: SlackWebAPI
    private let store: ItemStore
    private let identity: SlackIdentity
    private let clock: @Sendable () -> Date
    private var classifier: SlackMessageClassifier

    public private(set) var threads = ThreadTracker()
    private var items: [Item.ID: Item] = [:]
    private var users: [String: SlackUser] = [:]
    private var labels: [String: String] = [:]

    public init(
        api: SlackWebAPI,
        store: ItemStore,
        identity: SlackIdentity,
        keywords: [String] = [],
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.store = store
        self.identity = identity
        self.clock = clock
        self.classifier = SlackMessageClassifier(selfUserID: identity.userID, keywords: keywords)
    }

    /// Keyword highlights (SRC-7). Applies to messages from now on.
    public func setKeywords(_ keywords: [String]) {
        classifier = SlackMessageClassifier(selfUserID: identity.userID, keywords: keywords)
    }

    public var currentItems: [Item] { Array(items.values) }

    // MARK: - Live events

    /// Handles one message event from Socket Mode.
    public func handle(_ message: SlackMessage) async {
        guard let channel = message.channel else { return }

        if message.subtype == "message_deleted", let deleted = message.deletedTS {
            items[Self.itemID(channel: channel, ts: deleted)] = nil
            publish(isBackfill: false)
            return
        }

        if classifier.isOwn(message) {
            threads.recordOwnMessage(message, channel: channel)
            // Replying in a conversation means the user has seen what came before it.
            markRead(channel: channel, upTo: message.ts)
            publish(isBackfill: false)
            return
        }

        let channelType = message.channelType ?? "channel"
        guard let reason = classifier.classify(message, channel: channel, channelType: channelType, threads: threads) else { return }
        let item = await makeItem(message, channel: channel, channelType: channelType, reason: reason)
        items[item.id] = item
        publish(isBackfill: false)
    }

    // MARK: - Backfill

    /// Loads unread DMs and recent Mentions from the Web API. Items found here never Alert (ALR-8).
    public func backfill() async throws {
        let since = clock().addingTimeInterval(-Self.itemLifetime)
        let sinceTS = SlackTimestamp.string(since)

        let direct = try await recentConversations(types: "im,mpim", since: since, limit: Self.backfillDirectLimit)
        for conversation in direct {
            try await bestEffort {
                let info = try await self.api.conversationInfo(id: conversation.id)
                let oldest = Self.later(info.lastRead, sinceTS)
                let channelType = (info.isMPIM ?? conversation.isMPIM) == true ? "mpim" : "im"
                for message in try await self.api.history(channel: conversation.id, oldest: oldest, limit: 50).reversed() {
                    await self.add(message, channel: conversation.id, channelType: channelType)
                }
            }
        }

        let channels = try await recentConversations(types: "public_channel,private_channel", since: since, limit: Self.backfillChannelLimit)
        for conversation in channels {
            try await bestEffort {
                let info = try await self.api.conversationInfo(id: conversation.id)
                let history = try await self.api.history(channel: conversation.id, oldest: sinceTS, limit: 100)
                self.threads.seed(from: history, channel: conversation.id, selfUserID: self.identity.userID)
                for message in history.reversed() {
                    if self.classifier.isOwn(message) {
                        self.threads.recordOwnMessage(message, channel: conversation.id)
                        continue
                    }
                    if let lastRead = info.lastRead, SlackTimestamp.isAtOrBefore(message.ts, lastRead) { continue }
                    await self.add(message, channel: conversation.id, channelType: "channel")
                }
            }
        }

        publish(isBackfill: true)
    }

    // MARK: - Read state

    /// Removes DMs and Mentions in conversations whose `last_read` is at or after them (LIF-2, best effort).
    public func checkReadState() async throws {
        let channels = Set(items.values.compactMap { $0.slack }.filter { !$0.isThreadReply }.map(\.channelID))
        var lastRead: [String: String] = [:]
        for channel in channels {
            try await bestEffort {
                if let read = try await self.api.conversationInfo(id: channel).lastRead {
                    lastRead[channel] = read
                }
            }
        }
        let remaining = SlackReadState.unread(Array(items.values), lastRead: lastRead)
        items = Dictionary(uniqueKeysWithValues: remaining.map { ($0.id, $0) })
        publish(isBackfill: false)
    }

    // MARK: - Private

    private func add(_ message: SlackMessage, channel: String, channelType: String) async {
        guard let reason = classifier.classify(message, channel: channel, channelType: channelType, threads: threads) else { return }
        let item = await makeItem(message, channel: channel, channelType: channelType, reason: reason)
        items[item.id] = item
    }

    private func markRead(channel: String, upTo ts: String) {
        items = items.filter { _, item in
            guard let slack = item.slack, slack.channelID == channel, !slack.isThreadReply else { return true }
            return !SlackTimestamp.isAtOrBefore(slack.ts, ts)
        }
    }

    private func publish(isBackfill: Bool) {
        let now = clock()
        items = items.filter { !$0.value.isExpired(at: now) }
        store.replaceItems(Array(items.values), from: .slack, isBackfill: isBackfill)
    }

    private func recentConversations(types: String, since: Date, limit: Int) async throws -> [SlackConversation] {
        try await api.conversations(types: types)
            .filter { ($0.updatedDate ?? .distantFuture) >= since }
            .sorted { ($0.updatedDate ?? .distantFuture) > ($1.updatedDate ?? .distantFuture) }
            .prefix(limit)
            .map { $0 }
    }

    /// Runs `work`, ignoring failures other than rejected tokens, so one conversation
    /// can't stop the rest of a Backfill.
    private func bestEffort(_ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch let error as SlackAPIError {
            if case .invalidAuth = error { throw error }
        } catch {}
    }

    private func makeItem(_ message: SlackMessage, channel: String, channelType: String, reason: SlackItemReason) async -> Item {
        let text = message.text ?? ""
        var names: [String: String] = [:]
        for id in Set(SlackText.mentionedUserIDs(in: text)).prefix(5) {
            names[id] = await userName(id)
        }
        let senderUser = await user(message.user ?? "")
        let sender = senderUser.name
        let where_ = await label(channel: channel, channelType: channelType)

        var detail = "\(sender) · \(where_)"
        switch reason {
        case .threadReply: detail += " · thread"
        case .keyword(let keyword): detail += " · “\(keyword)”"
        case .dm, .mention: break
        }

        let date = message.date
        return Item(
            id: Self.itemID(channel: channel, ts: message.ts),
            kind: reason.kind,
            title: SlackText.excerpt(SlackText.plain(text, userNames: names)).nilIfBlank ?? "(No text)",
            detail: detail,
            date: date,
            expiresAt: date.addingTimeInterval(Self.itemLifetime),
            openURL: Self.deepLink(team: identity.teamID, channel: channel, ts: message.ts, threadTS: message.threadTS),
            avatarURL: senderUser.avatarURL,
            slack: SlackMessageDetails(channelID: channel, ts: message.ts, threadTS: message.threadTS)
        )
    }

    private func userName(_ id: String) async -> String {
        await user(id).name
    }

    private func user(_ id: String) async -> SlackUser {
        guard !id.isEmpty else { return SlackUser(name: "Someone") }
        if let cached = users[id] { return cached }
        let user = (try? await api.user(id: id)) ?? SlackUser(name: id)
        users[id] = user
        return user
    }

    private func label(channel: String, channelType: String) async -> String {
        if channelType == "im" { return "DM" }
        if let cached = labels[channel] { return cached }
        var label: String
        if channelType == "mpim" {
            let members = (try? await api.members(of: channel)) ?? []
            var names: [String] = []
            for member in members where member != identity.userID {
                names.append(await userName(member))
            }
            label = names.isEmpty ? "Group DM" : names.sorted().joined(separator: ", ")
        } else {
            let name = (try? await api.conversationInfo(id: channel))?.name
            label = "#" + (name ?? "channel")
        }
        labels[channel] = label
        return label
    }

    static func itemID(channel: String, ts: String) -> Item.ID {
        Item.ID(source: .slack, value: "\(channel):\(ts)")
    }

    static func later(_ a: String?, _ b: String) -> String {
        guard let a else { return b }
        return SlackTimestamp.isAtOrBefore(a, b) ? b : a
    }

    /// Opens the message in the Slack desktop app (INT-1).
    static func deepLink(team: String, channel: String, ts: String, threadTS: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "slack"
        components.host = "channel"
        var query = [
            URLQueryItem(name: "team", value: team),
            URLQueryItem(name: "id", value: channel),
            URLQueryItem(name: "message", value: ts),
        ]
        if let threadTS, threadTS != ts { query.append(URLQueryItem(name: "thread_ts", value: threadTS)) }
        components.queryItems = query
        return components.url
    }
}

public enum SlackReadState {
    /// The Items that are still unread: anything newer than its conversation's `last_read`.
    /// Thread replies are kept, because a channel's `last_read` doesn't cover its threads.
    public static func unread(_ items: [Item], lastRead: [String: String]) -> [Item] {
        items.filter { item in
            guard let slack = item.slack, !slack.isThreadReply, let read = lastRead[slack.channelID] else { return true }
            return !SlackTimestamp.isAtOrBefore(slack.ts, read)
        }
    }
}
