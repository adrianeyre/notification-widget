import Foundation
@testable import NotificationWidgetCore

extension Fixture {
    static func text(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

let me = SlackIdentity(userID: "U_ME", userName: "me", teamID: "T0123", teamName: "Acme")

/// A fake Slack workspace.
final class FakeSlackAPI: SlackWebAPI, @unchecked Sendable {
    private let lock = NSLock()
    var names: [String: String] = ["U_PRIYA": "Priya Shah", "U_ALEX": "Alex Chen", "U_SAM": "Sam Lee", "U_ME": "me"]
    var conversationList: [String: [SlackConversation]] = [:]
    var infos: [String: SlackConversation] = [:]
    var histories: [String: [SlackMessage]] = [:]
    var avatars: [String: URL] = [:]
    var memberLists: [String: [String]] = [:]
    var socketURLs = 0
    var authError: SlackAPIError?
    private(set) var calls: [String] = []

    private func record(_ call: String) { lock.withLock { calls.append(call) } }

    func authTest() async throws -> SlackIdentity {
        if let authError { throw authError }
        return me
    }

    func openSocketModeURL() async throws -> URL {
        record("apps.connections.open")
        if let authError { throw authError }
        lock.withLock { socketURLs += 1 }
        return URL(string: "wss://wss-primary.slack.com/link/?ticket=\(socketURLs)")!
    }

    func user(id: String) async throws -> SlackUser { SlackUser(name: names[id] ?? id, avatarURL: avatars[id]) }

    func conversations(types: String) async throws -> [SlackConversation] {
        record("users.conversations:\(types)")
        return conversationList[types] ?? []
    }

    func conversationInfo(id: String) async throws -> SlackConversation {
        record("conversations.info:\(id)")
        return infos[id] ?? SlackConversation(id: id)
    }

    func members(of channel: String) async throws -> [String] { memberLists[channel] ?? [] }

    func history(channel: String, oldest: String?, limit: Int) async throws -> [SlackMessage] {
        record("conversations.history:\(channel):\(oldest ?? "-")")
        let all = histories[channel] ?? []
        guard let oldest else { return all }
        return all.filter { !SlackTimestamp.isAtOrBefore($0.ts, oldest) }
    }
}

/// A WebSocket that replays recorded frames, then closes.
final class FakeWebSocket: WebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [String]
    private(set) var sent: [String] = []
    private(set) var closed = false

    init(frames: [String]) { self.frames = frames }

    func send(_ text: String) async throws { lock.withLock { sent.append(text) } }

    func receive() async throws -> String {
        try lock.withLock {
            guard !frames.isEmpty else { throw URLError(.networkConnectionLost) }
            return frames.removeFirst()
        }
    }

    func close() { lock.withLock { closed = true } }
}

final class FakeConnector: WebSocketConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [FakeWebSocket]
    private(set) var opened: [FakeWebSocket] = []

    init(sockets: [FakeWebSocket]) { self.sockets = sockets }

    func connect(to url: URL) -> WebSocketConnection {
        lock.withLock {
            let socket = sockets.isEmpty ? FakeWebSocket(frames: []) : sockets.removeFirst()
            opened.append(socket)
            return socket
        }
    }
}

/// Collects values from `@Sendable` callbacks.
actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []
    func append(_ value: Value) { values.append(value) }
}

/// A clock tests can move.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = referenceNow) { current = start }

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

func slackMessage(
    _ ts: String,
    user: String? = "U_PRIYA",
    text: String = "hello",
    channel: String = "D0456",
    channelType: String = "im",
    subtype: String? = nil,
    botID: String? = nil,
    threadTS: String? = nil
) -> SlackMessage {
    SlackMessage(subtype: subtype, channel: channel, channelType: channelType, user: user, botID: botID, text: text, ts: ts, threadTS: threadTS)
}

/// A Slack timestamp `seconds` after `referenceNow`.
func ts(_ seconds: TimeInterval) -> String {
    SlackTimestamp.string(referenceNow.addingTimeInterval(seconds))
}
