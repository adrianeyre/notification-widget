import Foundation

public enum SlackAPIError: Error, Equatable, Sendable {
    /// The token is wrong, revoked or missing a scope. Shown in Settings.
    case invalidAuth(String)
    /// Slack returned `ok: false` with another error code.
    case api(String)
    case http(Int)

    public var message: String {
        switch self {
        case .invalidAuth(let code):
            switch code {
            case "invalid_auth", "not_authed": return "Slack didn't accept the token. Check you copied all of it."
            case "token_revoked", "account_inactive": return "The token has been revoked. Reinstall the Slack app and paste the new token."
            case "missing_scope": return "The token is missing a scope. See docs/setup/slack-app.md."
            default: return "Slack rejected the token (\(code))."
            }
        case .api(let code): return "Slack returned an error: \(code)."
        case .http(let status): return "Slack returned HTTP \(status)."
        }
    }

    static let authErrors: Set<String> = [
        "invalid_auth", "not_authed", "token_revoked", "account_inactive",
        "missing_scope", "not_allowed_token_type", "token_expired",
    ]
}

/// The Slack Web API calls the Slack Source needs.
public protocol SlackWebAPI: Sendable {
    /// `auth.test` with the user token.
    func authTest() async throws -> SlackIdentity
    /// `apps.connections.open` with the app-level token: a WebSocket URL for Socket Mode.
    func openSocketModeURL() async throws -> URL
    /// `users.info`: the user's display name.
    func userName(id: String) async throws -> String
    /// `users.conversations`: the conversations the user is in, of the given types.
    func conversations(types: String) async throws -> [SlackConversation]
    /// `conversations.info`: includes `last_read` for the user.
    func conversationInfo(id: String) async throws -> SlackConversation
    /// `conversations.members`: user IDs in a conversation (used for group DM names).
    func members(of channel: String) async throws -> [String]
    /// `conversations.history`: messages after `oldest`, newest first.
    func history(channel: String, oldest: String?, limit: Int) async throws -> [SlackMessage]
}

/// The live Slack Web API.
public struct LiveSlackWebAPI: SlackWebAPI {
    private let credentials: SlackCredentials
    private let transport: HTTPTransport
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        credentials: SlackCredentials,
        transport: HTTPTransport = URLSession.shared,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.credentials = credentials
        self.transport = transport
        self.sleep = sleep
    }

    public func authTest() async throws -> SlackIdentity {
        struct Response: Decodable { var user_id: String; var user: String; var team_id: String; var team: String }
        let r: Response = try await call("auth.test")
        return SlackIdentity(userID: r.user_id, userName: r.user, teamID: r.team_id, teamName: r.team)
    }

    public func openSocketModeURL() async throws -> URL {
        struct Response: Decodable { var url: URL }
        let r: Response = try await call("apps.connections.open", token: credentials.appToken)
        return r.url
    }

    public func userName(id: String) async throws -> String {
        struct Response: Decodable {
            struct User: Decodable {
                struct Profile: Decodable { var display_name: String?; var real_name: String? }
                var name: String?
                var real_name: String?
                var profile: Profile?
            }
            var user: User
        }
        let r: Response = try await call("users.info", ["user": id])
        let candidates = [r.user.profile?.display_name, r.user.profile?.real_name, r.user.real_name, r.user.name]
        return candidates.compactMap { $0?.nilIfBlank }.first ?? id
    }

    public func conversations(types: String) async throws -> [SlackConversation] {
        struct Response: Decodable {
            struct Metadata: Decodable { var next_cursor: String? }
            var channels: [SlackConversation]
            var response_metadata: Metadata?
        }
        var all: [SlackConversation] = []
        var cursor: String?
        repeat {
            var parameters = ["types": types, "exclude_archived": "true", "limit": "200"]
            if let cursor { parameters["cursor"] = cursor }
            let r: Response = try await call("users.conversations", parameters)
            all += r.channels
            cursor = r.response_metadata?.next_cursor?.nilIfBlank
        } while cursor != nil && all.count < 1_000
        return all
    }

    public func conversationInfo(id: String) async throws -> SlackConversation {
        struct Response: Decodable { var channel: SlackConversation }
        let r: Response = try await call("conversations.info", ["channel": id])
        return r.channel
    }

    public func members(of channel: String) async throws -> [String] {
        struct Response: Decodable { var members: [String] }
        let r: Response = try await call("conversations.members", ["channel": channel, "limit": "50"])
        return r.members
    }

    public func history(channel: String, oldest: String?, limit: Int) async throws -> [SlackMessage] {
        struct Response: Decodable { var messages: [SlackMessage] }
        var parameters = ["channel": channel, "limit": String(limit)]
        if let oldest { parameters["oldest"] = oldest }
        let r: Response = try await call("conversations.history", parameters)
        return r.messages
    }

    // MARK: - Transport

    private struct Status: Decodable { var ok: Bool; var error: String? }

    func call<T: Decodable>(_ method: String, _ parameters: [String: String] = [:], token: String? = nil) async throws -> T {
        var components = URLComponents()
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token ?? credentials.userToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        // Respect rate limits: wait for Retry-After once, then give up until the next poll.
        for attempt in 0..<2 {
            let (data, response) = try await transport.send(request)
            if response.statusCode == 429, attempt == 0 {
                let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init) ?? 30
                try await sleep(.seconds(min(seconds, 120)))
                continue
            }
            guard (200..<300).contains(response.statusCode) else { throw SlackAPIError.http(response.statusCode) }
            let status = try JSONDecoder().decode(Status.self, from: data)
            guard status.ok else {
                let code = status.error ?? "unknown_error"
                throw SlackAPIError.authErrors.contains(code) ? SlackAPIError.invalidAuth(code) : SlackAPIError.api(code)
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw SlackAPIError.http(429)
    }
}
