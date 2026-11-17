import Foundation
import Testing
@testable import NotificationWidgetCore

@Suite("Socket Mode")
struct SocketModeTests {
    @Test("Decodes hello, message events, other events and disconnect from recorded payloads")
    func decoding() throws {
        #expect(try SocketModeProtocol.decode(Fixture.text("socket-hello")) == .hello)

        guard case .event(let id, let message?) = try SocketModeProtocol.decode(Fixture.text("socket-event-im")) else {
            Issue.record("Expected a message event")
            return
        }
        #expect(id == "57d6a792-4d35-4d0b-b6aa-3361493e1caf")
        #expect(message.channel == "D0456")
        #expect(message.channelType == "im")
        #expect(message.user == "U_PRIYA")
        #expect(message.ts == "1794906000.000100")

        #expect(try SocketModeProtocol.decode(Fixture.text("socket-event-reaction"))
            == .event(envelopeID: "a1b2c3d4-0000-4000-8000-000000000003", message: nil))
        #expect(try SocketModeProtocol.decode(Fixture.text("socket-disconnect")) == .disconnect(reason: "refresh_requested"))
    }

    @Test("The acknowledgement echoes the envelope ID")
    func acknowledgement() throws {
        let ack = SocketModeProtocol.acknowledgement(for: "57d6a792-4d35")
        let decoded = try JSONDecoder().decode([String: String].self, from: Data(ack.utf8))
        #expect(decoded == ["envelope_id": "57d6a792-4d35"])
    }

    @Test("Every envelope is acknowledged, message events are published, and disconnect reconnects")
    func clientLoop() async throws {
        let first = FakeWebSocket(frames: [
            try Fixture.text("socket-hello"),
            try Fixture.text("socket-event-im"),
            try Fixture.text("socket-event-reaction"),
            try Fixture.text("socket-disconnect"),
        ])
        let second = FakeWebSocket(frames: [try Fixture.text("socket-hello"), try Fixture.text("socket-event-channel-mention")])
        let api = FakeSlackAPI()
        let connector = FakeConnector(sockets: [first, second])
        let statuses = Recorder<SocketModeStatus>()
        let messages = Recorder<SlackMessage>()

        let client = SocketModeClient(
            api: api,
            connector: connector,
            sleep: { _ in
                // Stop after the second connection closes.
                if api.socketURLs >= 2 { throw CancellationError() }
            },
            onStatus: { await statuses.append($0) },
            onMessage: { await messages.append($0) }
        )
        let task = Task { await client.run() }
        // The second socket closes after its frames; the sleep then throws, and the loop
        // retries. Cancel once both connections have been used.
        while api.socketURLs < 2 || connector.opened.count < 2 || second.sent.isEmpty {
            await Task.yield()
        }
        task.cancel()
        await task.value

        #expect(first.sent == [
            SocketModeProtocol.acknowledgement(for: "57d6a792-4d35-4d0b-b6aa-3361493e1caf"),
            SocketModeProtocol.acknowledgement(for: "a1b2c3d4-0000-4000-8000-000000000003"),
        ])
        #expect(second.sent == [SocketModeProtocol.acknowledgement(for: "a1b2c3d4-0000-4000-8000-000000000002")])
        #expect(first.closed)
        #expect(await messages.values.map(\.ts) == ["1794906000.000100", "1794906100.000200"])
        let seen = await statuses.values
        #expect(seen.prefix(3) == [.connecting, .connected, .down])
        #expect(seen.contains(.connected))
    }

    @Test("Rejected tokens stop the client and report invalid auth")
    func invalidAuth() async {
        let api = FakeSlackAPI()
        api.authError = .invalidAuth("invalid_auth")
        let statuses = Recorder<SocketModeStatus>()
        let client = SocketModeClient(api: api, connector: FakeConnector(sockets: []), sleep: { _ in },
                                      onStatus: { await statuses.append($0) }, onMessage: { _ in })

        await client.run()

        #expect(await statuses.values == [.connecting, .invalidAuth("invalid_auth")])
    }

    @Test("Credentials are checked for the right token prefixes")
    func credentialFormat() {
        #expect(SlackCredentials(userToken: " xoxp-1 ", appToken: "xapp-1").formatProblem == nil)
        #expect(SlackCredentials(userToken: "xoxb-1", appToken: "xapp-1").formatProblem != nil)
        #expect(SlackCredentials(userToken: "xoxp-1", appToken: "xoxp-1").formatProblem != nil)
    }

    @Test("Auth errors have a clear message for Settings")
    func authMessages() {
        #expect(SlackAPIError.invalidAuth("invalid_auth").message.contains("didn't accept"))
        #expect(SlackAPIError.invalidAuth("token_revoked").message.contains("revoked"))
    }

    @Test("Credentials round-trip through a credential store")
    func credentialStore() throws {
        let store = InMemoryCredentialStore()
        let credentials = SlackCredentials(userToken: "xoxp-1", appToken: "xapp-1")
        try store.saveValue(credentials, for: "slack")
        #expect(store.loadValue(SlackCredentials.self, for: "slack") == credentials)
        store.delete("slack")
        #expect(store.loadValue(SlackCredentials.self, for: "slack") == nil)
    }
}

@Suite("Backoff")
struct BackoffTests {
    @Test("Doubles up to the maximum and resets after success")
    func doubling() {
        var backoff = Backoff(base: 2, maximum: 30)
        #expect((0..<6).map { _ in backoff.nextDelay() } == [2, 4, 8, 16, 30, 30])
        backoff.reset()
        #expect(backoff.nextDelay() == 2)
    }
}

@Suite("Slack text")
struct SlackTextTests {
    @Test("Markup becomes plain text", arguments: [
        ("Have you got *five minutes*?", "Have you got five minutes?"),
        ("<@U_SAM> can you _check_ this", "@Sam Lee can you check this"),
        ("<@U_NOBODY|bob> hi", "@bob hi"),
        ("see <#C123|platform> and <https://example.com|the notes>", "see #platform and the notes"),
        ("<https://example.com>", "https://example.com"),
        ("<mailto:a@b.com|a@b.com>", "a@b.com"),
        ("<!here> deploy ~now~", "@here deploy now"),
        ("use `make test`\n\n```code```", "use make test code"),
        ("a &lt; b &amp;&amp; c &gt; d", "a < b && c > d"),
    ])
    func plain(input: String, expected: String) {
        #expect(SlackText.plain(input, userNames: ["U_SAM": "Sam Lee"]) == expected)
    }

    @Test("Long text is cut to about 100 characters with an ellipsis")
    func truncation() {
        let long = String(repeating: "word ", count: 40)
        let excerpt = SlackText.excerpt(long.trimmingCharacters(in: .whitespaces))
        #expect(excerpt.hasSuffix("…"))
        #expect(excerpt.count <= 101)
        #expect(!excerpt.contains("wor…"))
        #expect(SlackText.excerpt("short") == "short")
    }
}
