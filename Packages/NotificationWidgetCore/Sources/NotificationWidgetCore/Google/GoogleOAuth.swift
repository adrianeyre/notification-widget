import CryptoKit
import Foundation

/// A Google OAuth client of type **Desktop app**, entered in Settings (SRC-1).
/// Google treats a desktop client's secret as not confidential; it's kept in the
/// Keychain all the same.
public struct GoogleOAuthClient: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What's wrong with the values' shape, or `nil` if they look right.
    public var formatProblem: String? {
        if clientID.isEmpty { return "Enter the client ID." }
        if !clientID.hasSuffix(".apps.googleusercontent.com") { return "The client ID should end in .apps.googleusercontent.com." }
        if clientSecret.isEmpty { return "Enter the client secret." }
        return nil
    }
}

/// The Account's tokens, kept in the Keychain (APP-3).
public struct GoogleTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var email: String?
    public var grantedScopes: [String]

    public init(accessToken: String, refreshToken: String, expiresAt: Date, email: String?, grantedScopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.email = email
        self.grantedScopes = grantedScopes
    }
}

public enum GoogleOAuthError: Error, Equatable, Sendable {
    case denied(String)
    case stateMismatch
    case missingCode
    /// The token endpoint refused, for example `invalid_client` or `invalid_grant`.
    case tokenRequestFailed(String)
    case timedOut

    public var message: String {
        switch self {
        case .denied(let reason): reason == "access_denied" ? "Google sign-in was cancelled." : "Google refused the sign-in (\(reason))."
        case .stateMismatch: "The Google sign-in response didn't match this request. Try again."
        case .missingCode: "Google didn't return a sign-in code. Try again."
        case .tokenRequestFailed(let reason):
            switch reason {
            case "invalid_client": "Google didn't recognise the client ID or secret. Check them in Setup."
            case "invalid_grant": "Google sign-in has expired. Sign in again."
            default: "Google sign-in failed (\(reason))."
            }
        case .timedOut: "Google sign-in timed out. Try again."
        }
    }
}

/// Google's OAuth flow for installed apps: the browser, a loopback redirect and PKCE
/// (RFC 8252, RFC 7636). No SDK, so the client can be entered in Settings at run time.
public enum GoogleOAuth {
    public static let authorizeEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    public static let callbackPath = "/google/oauth/callback"
    /// The read-only scopes, plus who signed in.
    public static let scopes = ["openid", "email"] + GoogleScope.all

    // MARK: PKCE

    /// A random code verifier: 64 URL-safe characters.
    public static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return base64URL(Data(bytes))
    }

    public static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Requests

    public static func authorizeURL(
        client: GoogleOAuthClient,
        redirectURI: String,
        state: String,
        codeChallenge: String,
        loginHint: String? = nil
    ) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // A refresh token, so the app stays signed in.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let loginHint { query.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components.queryItems = query
        return components.url!
    }

    public static func code(fromCallback target: String, expectedState: String) throws -> String {
        guard let components = URLComponents(string: target) else { throw GoogleOAuthError.missingCode }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        if let error = query["error"] { throw GoogleOAuthError.denied(error) }
        guard query["state"] == expectedState else { throw GoogleOAuthError.stateMismatch }
        guard let code = query["code"], !code.isEmpty else { throw GoogleOAuthError.missingCode }
        return code
    }

    public static func exchangeRequest(client: GoogleOAuthClient, code: String, verifier: String, redirectURI: String) -> URLRequest {
        formRequest(tokenEndpoint, [
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
    }

    public static func refreshRequest(client: GoogleOAuthClient, refreshToken: String) -> URLRequest {
        formRequest(tokenEndpoint, [
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    public static func revokeRequest(token: String) -> URLRequest {
        formRequest(revokeEndpoint, ["token": token])
    }

    static func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // `+` is a space in form bodies, so encode it as well.
        let encoded = (body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = Data(encoded.utf8)
        return request
    }

    // MARK: Responses

    struct TokenResponse: Decodable {
        var access_token: String?
        var refresh_token: String?
        var expires_in: Double?
        var scope: String?
        var id_token: String?
        var error: String?
    }

    /// Reads a token endpoint response. A refresh response has no refresh token, so the
    /// previous one is kept.
    public static func tokens(fromResponse data: Data, status: Int, now: Date, previous: GoogleTokens? = nil) throws -> GoogleTokens {
        let response = try? JSONDecoder().decode(TokenResponse.self, from: data)
        guard (200..<300).contains(status), let response, let access = response.access_token else {
            throw GoogleOAuthError.tokenRequestFailed(response?.error ?? "http_\(status)")
        }
        guard let refresh = response.refresh_token ?? previous?.refreshToken else {
            throw GoogleOAuthError.tokenRequestFailed("no_refresh_token")
        }
        return GoogleTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(response.expires_in ?? 3600),
            email: response.id_token.flatMap(email(fromIDToken:)) ?? previous?.email,
            grantedScopes: response.scope.map { $0.split(separator: " ").map(String.init) } ?? previous?.grantedScopes ?? []
        )
    }

    /// The `email` claim from an ID token. It came straight from Google's token endpoint
    /// over TLS, so it's read, not verified.
    public static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return claims["email"] as? String
    }

    // MARK: The flow

    /// Listens on a free loopback port, opens the browser, waits for the redirect, and
    /// exchanges the code for tokens.
    public static func signIn(
        client: GoogleOAuthClient,
        loginHint: String? = nil,
        transport: HTTPTransport = URLSession.shared,
        now: @Sendable () -> Date = { Date() },
        openBrowser: @escaping @Sendable (URL) async -> Void
    ) async throws -> GoogleTokens {
        let receiver = try LoopbackRedirectReceiver(port: 0, path: callbackPath)
        defer { receiver.stop() }
        let port = try await receiver.start()
        let redirectURI = "http://127.0.0.1:\(port)\(callbackPath)"

        let state = UUID().uuidString
        let verifier = makeCodeVerifier()
        await openBrowser(authorizeURL(client: client, redirectURI: redirectURI, state: state,
                                       codeChallenge: codeChallenge(for: verifier), loginHint: loginHint))

        let target: String
        do {
            target = try await receiver.waitForRedirect(timeout: .seconds(300))
        } catch SlackOAuthError.timedOut {
            throw GoogleOAuthError.timedOut
        }
        do {
            let code = try code(fromCallback: target, expectedState: state)
            let (data, response) = try await transport.send(exchangeRequest(client: client, code: code, verifier: verifier, redirectURI: redirectURI))
            let tokens = try tokens(fromResponse: data, status: response.statusCode, now: now())
            receiver.respond(OAuthCallbackPage.response(.google, .signedIn))
            return tokens
        } catch {
            receiver.respond(OAuthCallbackPage.response(.google, callbackOutcome(for: error)))
            throw error
        }
    }

    /// What the browser's callback page says when sign-in fails.
    static func callbackOutcome(for error: Error) -> OAuthCallbackPage.Outcome {
        switch error {
        case GoogleOAuthError.denied("access_denied"): .cancelled
        case let error as GoogleOAuthError: .failed(error.message)
        default: .failed("Couldn’t reach Google to finish signing in. Check your connection and try again.")
        }
    }
}
