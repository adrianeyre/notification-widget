import Foundation

/// The signed-in Google Account's tokens: kept in the Keychain, refreshed before they
/// expire, and handed to the Calendar and Gmail Sources (SRC-1, APP-3).
public actor GoogleSession: GoogleAccessTokenProvider {
    static let tokensKey = "googleTokens"
    /// Refresh this long before the access token expires.
    static let refreshMargin: TimeInterval = 120

    private let store: CredentialStore
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    private let client: @Sendable () async -> GoogleOAuthClient?
    private var tokens: GoogleTokens?
    private var refreshing: Task<GoogleTokens, Error>?

    public init(
        store: CredentialStore,
        transport: HTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() },
        client: @escaping @Sendable () async -> GoogleOAuthClient?
    ) {
        self.store = store
        self.transport = transport
        self.now = now
        self.client = client
        self.tokens = store.loadValue(GoogleTokens.self, for: Self.tokensKey)
    }

    /// The saved tokens, if an Account is signed in. Restoring needs no network.
    public var current: GoogleTokens? { tokens }

    public func save(_ tokens: GoogleTokens) throws {
        try store.saveValue(tokens, for: Self.tokensKey)
        self.tokens = tokens
    }

    /// Forgets the Account and, best effort, revokes the app's access at Google.
    public func signOut() async {
        let token = tokens?.refreshToken
        tokens = nil
        refreshing = nil
        store.delete(Self.tokensKey)
        if let token {
            _ = try? await transport.send(GoogleOAuth.revokeRequest(token: token))
        }
    }

    /// A valid access token, refreshed first if it's about to expire. Throws
    /// ``GoogleAPIError/needsSignIn`` when Google refuses the refresh token.
    public func freshAccessToken() async throws -> String {
        guard let tokens else { throw GoogleAPIError.notSignedIn }
        if tokens.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return tokens.accessToken
        }
        // One refresh at a time, shared by every caller.
        let task = refreshing ?? Task { try await self.refresh(tokens) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value.accessToken
    }

    private func refresh(_ old: GoogleTokens) async throws -> GoogleTokens {
        guard let client = await client() else { throw GoogleAPIError.needsSignIn }
        let (data, response) = try await transport.send(GoogleOAuth.refreshRequest(client: client, refreshToken: old.refreshToken))
        do {
            let fresh = try GoogleOAuth.tokens(fromResponse: data, status: response.statusCode, now: now(), previous: old)
            try save(fresh)
            return fresh
        } catch GoogleOAuthError.tokenRequestFailed(let reason) where reason == "invalid_grant" || reason == "invalid_client" || reason == "unauthorized_client" {
            // Revoked, expired (7 days in testing mode) or the client changed: sign in again.
            throw GoogleAPIError.needsSignIn
        }
    }
}
