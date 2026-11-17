import Foundation
import Testing
@testable import NotificationWidgetCore

@MainActor
@Suite("Slack DMs and Mentions")
struct SlackItemsTests {
    let clock = TestClock()

    func makeSource(api: FakeSlackAPI = FakeSlackAPI(), keywords: [String] = []) -> (SlackSource, ItemStore, AlertEngine) {
        let engine = AlertEngine(clock: { [clock] in clock.now })
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), alertEngine: engine, now: referenceNow)
        let source = SlackSource(api: api, store: store, identity: me, keywords: keywords, clock: { [clock] in clock.now })
        return (source, store, engine)
    }

    // MARK: DMs (#14)

    @Test("A DM from someone else becomes a DM Item with sender, DM and plain text")
    func dmMapping() async throws {
        let (source, store, _) = makeSource()
        let event = try #require(try { () throws -> SlackMessage? in
            if case .event(_, let message) = try SocketModeProtocol.decode(Fixture.text("socket-event-im")) { return message }
            return nil
        }())

        await source.handle(event)

        let item = try #require(store.visibleItems.first)
        #expect(item.kind == .dm)
        #expect(item.detail == "Priya Shah · DM")
        #expect(item.title == "Have you got five minutes to look at the release notes?")
        #expect(item.openURL?.absoluteString == "slack://channel?team=T0123&id=D0456&message=1794906000.000100")
        #expect(item.expiresAt == item.date.addingTimeInterval(24 * 60 * 60))
    }

    @Test("A group DM shows the other members' names")
    func groupDM() async throws {
        let api = FakeSlackAPI()
        api.memberLists["G0999"] = ["U_ME", "U_SAM", "U_ALEX"]
        let (source, store, _) = makeSource(api: api)

        await source.handle(slackMessage(ts(0), user: "U_SAM", channel: "G0999", channelType: "mpim"))

        #expect(store.visibleItems.first?.detail == "Sam Lee · Alex Chen, Sam Lee")
        #expect(store.visibleItems.first?.kind == .dm)
    }

    @Test("The user's own messages and bot or system messages are ignored", arguments: [
        slackMessage("1.0", user: "U_ME"),
        slackMessage("1.0", user: "U_BOT", botID: "B123"),
        slackMessage("1.0", subtype: "channel_join"),
        slackMessage("1.0", subtype: "bot_message"),
        slackMessage("1.0", user: nil),
    ])
    func ignored(message: SlackMessage) async {
        let (source, store, _) = makeSource()
        await source.handle(message)
        #expect(store.visibleItems.isEmpty)
    }

    @Test("Live DMs Alert; Backfilled DMs don't")
    func backfillSilence() async {
        let api = FakeSlackAPI()
        api.conversationList["im,mpim"] = [SlackConversation(id: "D0456", isIM: true, updated: referenceNow.timeIntervalSince1970 * 1000)]
        api.infos["D0456"] = SlackConversation(id: "D0456", isIM: true, lastRead: ts(-600))
        api.histories["D0456"] = [
            slackMessage(ts(-60), text: "unread"),
            slackMessage(ts(-900), text: "already read"),
        ]
        let (source, store, engine) = makeSource(api: api)
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }

        try? await source.backfill()
        #expect(store.visibleItems.map(\.title) == ["unread"])
        #expect(alerts.isEmpty)

        await source.handle(slackMessage(ts(5), text: "new one"))
        #expect(alerts.count == 1)
    }

    @Test("A deleted message is removed")
    func deleted() async {
        let (source, store, _) = makeSource()
        await source.handle(slackMessage(ts(0)))
        await source.handle(SlackMessage(subtype: "message_deleted", channel: "D0456", channelType: "im", user: nil, text: nil, ts: ts(10), deletedTS: ts(0)))
        #expect(store.visibleItems.isEmpty)
    }

    // MARK: Mentions (#15)

    @Test("A channel message that @mentions the user is a Mention with #channel")
    func mention() async throws {
        let api = FakeSlackAPI()
        api.infos["C0789"] = SlackConversation(id: "C0789", name: "platform")
        let (source, store, _) = makeSource(api: api)
        guard case .event(_, let message?) = try SocketModeProtocol.decode(Fixture.text("socket-event-channel-mention")) else {
            Issue.record("Expected a message")
            return
        }

        await source.handle(message)

        let item = try #require(store.visibleItems.first)
        #expect(item.kind == .mention)
        #expect(item.detail == "Alex Chen · #platform")
        #expect(item.title == "@me can you check the deploy pipeline? cc @Sam Lee")
    }

    @Test("A channel message without a mention is ignored")
    func noMention() async {
        let (source, store, _) = makeSource()
        await source.handle(slackMessage(ts(0), user: "U_ALEX", text: "<@U_SAM> hi", channel: "C0789", channelType: "channel"))
        #expect(store.visibleItems.isEmpty)
    }

    @Test("Replies in a thread the user posted in become Mentions; other threads don't")
    func threadTracking() async {
        let (source, store, _) = makeSource()
        let parent = ts(0)
        // The user replies in a thread.
        await source.handle(slackMessage(ts(10), user: "U_ME", text: "I'll look", channel: "C0789", channelType: "channel", threadTS: parent))
        #expect(source.threads.contains(channel: "C0789", threadTS: parent))
        #expect(store.visibleItems.isEmpty)

        await source.handle(slackMessage(ts(20), user: "U_ALEX", text: "thanks!", channel: "C0789", channelType: "channel", threadTS: parent))
        await source.handle(slackMessage(ts(30), user: "U_ALEX", text: "other thread", channel: "C0789", channelType: "channel", threadTS: ts(-100)))

        #expect(store.visibleItems.map(\.title) == ["thanks!"])
        #expect(store.visibleItems.first?.kind == .mention)
        #expect(store.visibleItems.first?.detail?.hasSuffix("· thread") == true)
    }

    @Test("Replies to the user's own top-level message count as their thread")
    func ownTopLevel() async {
        let (source, store, _) = makeSource()
        await source.handle(slackMessage(ts(0), user: "U_ME", text: "release is out", channel: "C0789", channelType: "channel"))
        await source.handle(slackMessage(ts(5), user: "U_SAM", text: "nice", channel: "C0789", channelType: "channel", threadTS: ts(0)))
        #expect(store.visibleItems.map(\.title) == ["nice"])
    }

    @Test("Backfill seeds threads from recent history and finds unread channel Mentions")
    func backfillSeeding() async {
        let api = FakeSlackAPI()
        api.conversationList["public_channel,private_channel"] = [SlackConversation(id: "C0789", name: "platform")]
        api.infos["C0789"] = SlackConversation(id: "C0789", name: "platform", lastRead: ts(-300))
        api.histories["C0789"] = [
            slackMessage(ts(-60), user: "U_ALEX", text: "<@U_ME> ping", channel: "C0789", channelType: "channel"),
            slackMessage(ts(-600), user: "U_ALEX", text: "<@U_ME> old ping", channel: "C0789", channelType: "channel"),
            SlackMessage(channel: "C0789", user: "U_SAM", text: "a thread", ts: ts(-3000), replyUsers: ["U_SAM", "U_ME"], latestReply: ts(-2000)),
        ]
        let (source, store, _) = makeSource(api: api)

        try? await source.backfill()

        #expect(store.visibleItems.map(\.title) == ["@me ping"])
        #expect(source.threads.contains(channel: "C0789", threadTS: ts(-3000)))
    }

    // MARK: Keywords (#25)

    @Test("Channel messages with a keyword become Items: whole word, case-insensitive")
    func keywords() async {
        let (source, store, _) = makeSource(keywords: ["deploy", "on-call"])
        await source.handle(slackMessage(ts(0), user: "U_ALEX", text: "The DEPLOY failed", channel: "C1", channelType: "channel"))
        await source.handle(slackMessage(ts(1), user: "U_ALEX", text: "redeployed fine", channel: "C1", channelType: "channel"))
        await source.handle(slackMessage(ts(2), user: "U_ALEX", text: "who's on-call?", channel: "C1", channelType: "channel"))

        #expect(Set(store.visibleItems.map(\.title)) == ["The DEPLOY failed", "who's on-call?"])
        #expect(store.visibleItems.allSatisfy { $0.kind == .mention })
        #expect(store.visibleItems.contains { $0.detail?.contains("“deploy”") == true })
    }

    @Test("Keyword matcher", arguments: [
        ("Deploy now", true), ("deploy.", true), ("(deploy)", true),
        ("deployment", false), ("redeploy", false), ("de ploy", false),
    ])
    func keywordMatcher(text: String, matches: Bool) {
        #expect((KeywordMatcher(keywords: ["deploy"]).firstMatch(in: text) != nil) == matches)
    }

    @Test("Blank keywords match nothing")
    func blankKeywords() {
        #expect(KeywordMatcher(keywords: ["", "  "]).firstMatch(in: "anything") == nil)
    }

    // MARK: Read state and expiry (#16)

    @Test("Read-state comparison: removed when last_read is at or after the message")
    func readState() {
        func item(_ ts: String, thread: String? = nil) -> Item {
            Item(id: .init(source: .slack, value: ts), kind: .dm, title: ts, date: referenceNow,
                 slack: SlackMessageDetails(channelID: "D1", ts: ts, threadTS: thread))
        }
        let items = [item("100.000001"), item("200.000001"), item("300.000001"), item("150.000001", thread: "50.000001")]

        let unread = SlackReadState.unread(items, lastRead: ["D1": "200.000001"])

        #expect(unread.map(\.title) == ["300.000001", "150.000001"])
    }

    @Test("checkReadState removes Items the user has read elsewhere")
    func checkReadState() async throws {
        let api = FakeSlackAPI()
        let (source, store, _) = makeSource(api: api)
        await source.handle(slackMessage(ts(0), text: "first"))
        await source.handle(slackMessage(ts(10), text: "second"))

        api.infos["D0456"] = SlackConversation(id: "D0456", lastRead: ts(0))
        try await source.checkReadState()

        #expect(store.visibleItems.map(\.title) == ["second"])
    }

    @Test("Replying in a conversation clears the Items before the reply")
    func ownReplyMarksRead() async {
        let (source, store, _) = makeSource()
        await source.handle(slackMessage(ts(0), text: "question"))
        await source.handle(slackMessage(ts(5), user: "U_ME", text: "answer"))
        #expect(store.visibleItems.isEmpty)
    }

    @Test("Items leave 24 hours after they arrived, read or not")
    func expiry() async {
        let (source, store, _) = makeSource()
        await source.handle(slackMessage(ts(0)))

        store.tick(now: referenceNow.addingTimeInterval(24 * 60 * 60 - 1))
        #expect(store.visibleItems.count == 1)

        store.tick(now: referenceNow.addingTimeInterval(24 * 60 * 60))
        #expect(store.visibleItems.isEmpty)

        // The Source also forgets it on its next publish.
        clock.advance(24 * 60 * 60 + 1)
        await source.handle(slackMessage(ts(24 * 60 * 60 + 1), text: "new"))
        #expect(source.currentItems.map(\.title) == ["new"])
    }

    @Test("A Dismissed DM stays hidden")
    func dismissed() async {
        let (source, store, _) = makeSource()
        await source.handle(slackMessage(ts(0), text: "hide me"))
        store.dismiss(store.visibleItems[0].id)
        await source.handle(slackMessage(ts(10), text: "keep"))
        #expect(store.visibleItems.map(\.title) == ["keep"])
    }
}
