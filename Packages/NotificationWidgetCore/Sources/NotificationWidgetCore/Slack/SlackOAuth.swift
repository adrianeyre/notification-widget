import Foundation
import Network

/// The Slack app's OAuth client, set in Config/Secrets.xcconfig (SRC-8).
public struct SlackOAuthConfiguration: Equatable, Sendable {
    /// The loopback port the browser redirects to. It must match the redirect URL in the
    /// Slack app manifest exactly.
    public static let defaultPort: UInt16 = 53682
    public static let callbackPath = "/slack/oauth/callback"

    public var clientID: String
    public var clientSecret: String
    public var port: UInt16

    public init(clientID: String, clientSecret: String, port: UInt16 = defaultPort) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.port = port
    }

    public var redirectURI: String { "http://localhost:\(port)\(Self.callbackPath)" }
}

public enum SlackOAuthError: Error, Equatable, Sendable {
    /// The user cancelled, or Slack refused (for example `access_denied`).
    case denied(String)
    /// The `state` didn't match: the callback wasn't for this sign-in.
    case stateMismatch
    case missingCode
    /// `oauth.v2.access` failed.
    case exchangeFailed(String)
    case timedOut

    public var message: String {
        switch self {
        case .denied(let reason): reason == "access_denied" ? "Slack sign-in was cancelled." : "Slack refused the sign-in (\(reason))."
        case .stateMismatch: "The Slack sign-in response didn't match this request. Try again."
        case .missingCode: "Slack didn't return a sign-in code. Try again."
        case .exchangeFailed(let reason): "Couldn't get a token from Slack (\(reason))."
        case .timedOut: "Slack sign-in timed out. Try again."
        }
    }
}

/// The browser OAuth flow for the Slack user token (SRC-8). The app-level token
/// (`xapp-…`) isn't issued through OAuth, so it's still pasted.
public enum SlackOAuth {
    /// The same user scopes as the Slack app manifest.
    public static let userScopes = [
        "im:history", "mpim:history", "channels:history", "groups:history",
        "im:read", "mpim:read", "channels:read", "groups:read", "users:read",
    ]

    public static func authorizeURL(_ configuration: SlackOAuthConfiguration, state: String) -> URL {
        var components = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "user_scope", value: userScopes.joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Reads the code from the redirect's request target, for example
    /// `/slack/oauth/callback?code=…&state=…`.
    public static func code(fromCallback target: String, expectedState: String) throws -> String {
        guard let components = URLComponents(string: target) else { throw SlackOAuthError.missingCode }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        if let error = query["error"] { throw SlackOAuthError.denied(error) }
        guard query["state"] == expectedState else { throw SlackOAuthError.stateMismatch }
        guard let code = query["code"], !code.isEmpty else { throw SlackOAuthError.missingCode }
        return code
    }

    public static func exchangeRequest(_ configuration: SlackOAuthConfiguration, code: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://slack.com/api/oauth.v2.access")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "client_secret", value: configuration.clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
        ]
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        return request
    }

    /// The user token (`xoxp-…`) from an `oauth.v2.access` response.
    public static func userToken(fromExchangeResponse data: Data) throws -> String {
        struct Response: Decodable {
            struct AuthedUser: Decodable { var access_token: String? }
            var ok: Bool
            var error: String?
            var authed_user: AuthedUser?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.ok else { throw SlackOAuthError.exchangeFailed(response.error ?? "unknown_error") }
        guard let token = response.authed_user?.access_token, token.hasPrefix("xoxp-") else {
            throw SlackOAuthError.exchangeFailed("no_user_token")
        }
        return token
    }

    /// Runs the whole flow: listens on the loopback port, opens the browser, waits for the
    /// redirect, and exchanges the code for the user token.
    public static func signIn(
        _ configuration: SlackOAuthConfiguration,
        transport: HTTPTransport = URLSession.shared,
        openBrowser: @escaping @Sendable (URL) async -> Void
    ) async throws -> String {
        let state = UUID().uuidString
        let receiver = try LoopbackRedirectReceiver(port: configuration.port, path: SlackOAuthConfiguration.callbackPath)
        defer { receiver.stop() }
        try await receiver.start()
        await openBrowser(authorizeURL(configuration, state: state))

        let target = try await receiver.waitForRedirect(timeout: .seconds(300))
        let code = try code(fromCallback: target, expectedState: state)
        let (data, _) = try await transport.send(exchangeRequest(configuration, code: code))
        return try userToken(fromExchangeResponse: data)
    }
}

/// A one-shot HTTP listener on the loopback interface that catches an OAuth redirect.
public final class LoopbackRedirectReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let path: String
    private let queue = DispatchQueue(label: "NotificationWidget.oauth")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?

    /// `port` 0 lets the system pick a free port; ``start()`` returns the one it got.
    public init(port: UInt16, path: String) throws {
        self.path = path
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        listener = port == 0
            ? try NWListener(using: parameters)
            : try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
    }

    /// Starts listening and returns the port.
    @discardableResult
    func start() async throws -> UInt16 {
        try await startListening()
        return listener.port?.rawValue ?? 0
    }

    private func startListening() async throws {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(ready)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error): once.resume(.failure(error))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    /// The request target of the first request to `path`.
    func waitForRedirect(timeout: Duration) async throws -> String {
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.complete(.failure(SlackOAuthError.timedOut))
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let result {
                    continuation.resume(with: result)
                } else {
                    self.continuation = continuation
                }
            }
        }
    }

    private func complete(_ outcome: Result<String, Error>) {
        lock.withLock {
            guard result == nil else { return }
            result = outcome
            continuation?.resume(with: outcome)
            continuation = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let target = Self.requestTarget(fromRequest: request)
            let isCallback = target.map { $0.hasPrefix(self.path) } ?? false

            let body = isCallback
                ? "<h2>Notification Widget</h2><p>You can close this tab and go back to the app.</p>"
                : "<p>Not found</p>"
            let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if isCallback, let target { self.complete(.success(target)) }
        }
    }

    /// `/path?query` from an HTTP request's first line, `GET /path?query HTTP/1.1`.
    public static func requestTarget(fromRequest request: String) -> String? {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }
}

/// Resumes a continuation at most once, from any thread.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Void, Error>) {
        lock.withLock {
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
