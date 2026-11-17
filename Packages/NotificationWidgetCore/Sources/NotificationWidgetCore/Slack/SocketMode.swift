import Foundation

/// One message from the Socket Mode WebSocket.
public enum SocketModeMessage: Equatable, Sendable {
    /// The connection is ready.
    case hello
    /// An Events API envelope. `message` is set when it carries a message event.
    case event(envelopeID: String, message: SlackMessage?)
    /// Slack is about to close the connection; reconnect (for example `refresh_requested`).
    case disconnect(reason: String)
    /// Anything else. Envelopes with an ID still need acknowledging.
    case other(envelopeID: String?)
}

public enum SocketModeProtocol {
    struct Envelope: Decodable {
        struct Payload: Decodable {
            var event: SlackMessage?
        }

        var type: String
        var envelope_id: String?
        var payload: Payload?
        var reason: String?
    }

    /// Decodes a WebSocket text frame. Events that aren't messages decode with `message == nil`.
    public static func decode(_ text: String) throws -> SocketModeMessage {
        let data = Data(text.utf8)
        // Decode the outer envelope first, so an unexpected event shape is still acknowledged.
        struct Outer: Decodable { var type: String; var envelope_id: String?; var reason: String? }
        let outer = try JSONDecoder().decode(Outer.self, from: data)
        switch outer.type {
        case "hello":
            return .hello
        case "disconnect":
            return .disconnect(reason: outer.reason ?? "unknown")
        case "events_api":
            guard let id = outer.envelope_id else { return .other(envelopeID: nil) }
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
            let event = envelope?.payload?.event
            return .event(envelopeID: id, message: event?.type == "message" ? event : nil)
        default:
            return .other(envelopeID: outer.envelope_id)
        }
    }

    /// The acknowledgement Slack expects for every envelope, within 3 seconds.
    public static func acknowledgement(for envelopeID: String) -> String {
        let escaped = envelopeID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"envelope_id":"\#(escaped)"}"#
    }
}

/// A WebSocket connection. The live one wraps `URLSessionWebSocketTask`; tests use a fake.
public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    /// The next text frame. Throws when the connection closes.
    func receive() async throws -> String
    func close()
}

public protocol WebSocketConnecting: Sendable {
    func connect(to url: URL) -> WebSocketConnection
}

public enum SocketModeStatus: Equatable, Sendable {
    case connecting
    case connected
    /// The socket dropped; it reconnects after a backoff.
    case down
    /// The tokens were rejected; it stops until new tokens are saved.
    case invalidAuth(String)
}

/// Keeps a Socket Mode connection open: opens it with `apps.connections.open`,
/// acknowledges every envelope, publishes message events, and reconnects with backoff
/// when Slack asks it to (`disconnect`) or the connection drops.
public final class SocketModeClient: Sendable {
    private let api: SlackWebAPI
    private let connector: WebSocketConnecting
    private let sleep: @Sendable (Duration) async throws -> Void
    private let onStatus: @Sendable (SocketModeStatus) async -> Void
    private let onMessage: @Sendable (SlackMessage) async -> Void

    public init(
        api: SlackWebAPI,
        connector: WebSocketConnecting,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onStatus: @escaping @Sendable (SocketModeStatus) async -> Void,
        onMessage: @escaping @Sendable (SlackMessage) async -> Void
    ) {
        self.api = api
        self.connector = connector
        self.sleep = sleep
        self.onStatus = onStatus
        self.onMessage = onMessage
    }

    /// Runs until the task is cancelled or the tokens are rejected.
    public func run() async {
        var backoff = Backoff()
        while !Task.isCancelled {
            await onStatus(.connecting)
            do {
                let url = try await api.openSocketModeURL()
                let connection = connector.connect(to: url)
                let receivedAny = try await pump(connection)
                connection.close()
                if receivedAny { backoff.reset() }
            } catch let error as SlackAPIError {
                if case .invalidAuth(let code) = error {
                    await onStatus(.invalidAuth(code))
                    return
                }
            } catch {
                // Connection dropped or failed to open: fall through to backoff.
            }
            guard !Task.isCancelled else { return }
            await onStatus(.down)
            try? await sleep(.seconds(backoff.nextDelay()))
        }
    }

    /// Reads frames until the connection closes or Slack sends `disconnect`.
    /// Returns whether the connection got as far as `hello`.
    func pump(_ connection: WebSocketConnection) async throws -> Bool {
        var helloReceived = false
        while !Task.isCancelled {
            let text = try await connection.receive()
            guard let message = try? SocketModeProtocol.decode(text) else { continue }
            switch message {
            case .hello:
                helloReceived = true
                await onStatus(.connected)
            case .event(let id, let event):
                try await connection.send(SocketModeProtocol.acknowledgement(for: id))
                if let event { await onMessage(event) }
            case .other(let id):
                if let id { try await connection.send(SocketModeProtocol.acknowledgement(for: id)) }
            case .disconnect:
                return helloReceived
            }
        }
        return helloReceived
    }
}

// MARK: - Live WebSocket

public struct URLSessionWebSocketConnector: WebSocketConnecting {
    public init() {}

    public func connect(to url: URL) -> WebSocketConnection {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    // URLSessionWebSocketTask is thread-safe; it just isn't marked Sendable.
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        while true {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
