import Foundation
import Testing
@testable import NotificationWidgetCore

/// An unsigned ID token carrying an email claim.
func idToken(email: String) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["email": email, "sub": "123"])
    return "eyJhbGciOiJub25lIn0." + GoogleOAuth.base64URL(payload) + ".sig"
}

let googleClient = GoogleOAuthClient(clientID: "123-abc.apps.googleusercontent.com", clientSecret: "GOCSPX-secret+/=")

@Suite("Google OAuth without the SDK")
struct GoogleOAuthTests {
    @Test("PKCE: S256 challenge of the verifier, URL-safe and unpadded")
    func pkce() {
        #expect(GoogleOAuth.codeChallenge(for: "dBjftJeZ4CVP-mJ92K9mxHc89jdyLYyNd8I8VQ7bFKI") == "T5QpWjs8T1TuT5J8AEljfoZC-gr74WHojAtfW1hJNbs")
        let verifier = GoogleOAuth.makeCodeVerifier()
        #expect(verifier.count == 64)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test("The authorize URL asks for read-only scopes, offline access and PKCE")
    func authorizeURL() throws {
        let url = GoogleOAuth.authorizeURL(client: googleClient, redirectURI: "http://127.0.0.1:5000/google/oauth/callback",
                                           state: "s", codeChallenge: "c", loginHint: "me@example.com")
        let query = Dictionary(uniqueKeysWithValues: try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map { ($0.name, $0.value ?? "") })
        #expect(query["client_id"] == googleClient.clientID)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["access_type"] == "offline")
        #expect(query["login_hint"] == "me@example.com")
        #expect(query["scope"]?.contains("https://www.googleapis.com/auth/gmail.readonly") == true)
        #expect(query["scope"]?.contains("https://www.googleapis.com/auth/calendar.readonly") == true)
    }

    @Test("The callback gives the code only when the state matches")
    func callback() throws {
        #expect(try GoogleOAuth.code(fromCallback: "/google/oauth/callback?state=s&code=4/abc", expectedState: "s") == "4/abc")
        #expect(throws: GoogleOAuthError.stateMismatch) { try GoogleOAuth.code(fromCallback: "/cb?state=x&code=1", expectedState: "s") }
        #expect(throws: GoogleOAuthError.denied("access_denied")) { try GoogleOAuth.code(fromCallback: "/cb?error=access_denied", expectedState: "s") }
    }

    @Test("Token responses: sign-in, refresh keeping the refresh token, and errors")
    func tokenResponses() throws {
        let signIn = #"{"access_token":"ya29.a","expires_in":3599,"refresh_token":"1//r","scope":"openid email https://www.googleapis.com/auth/gmail.readonly","id_token":"\#(idToken(email: "me@example.com"))"}"#
        let tokens = try GoogleOAuth.tokens(fromResponse: Data(signIn.utf8), status: 200, now: referenceNow)
        #expect(tokens.refreshToken == "1//r")
        #expect(tokens.email == "me@example.com")
        #expect(tokens.expiresAt == referenceNow.addingTimeInterval(3599))
        #expect(tokens.grantedScopes.contains(GoogleScope.gmailReadOnly))

        let refresh = #"{"access_token":"ya29.b","expires_in":3600}"#
        let refreshed = try GoogleOAuth.tokens(fromResponse: Data(refresh.utf8), status: 200, now: referenceNow, previous: tokens)
        #expect(refreshed.accessToken == "ya29.b")
        #expect(refreshed.refreshToken == "1//r")
        #expect(refreshed.email == "me@example.com")

        #expect(throws: GoogleOAuthError.tokenRequestFailed("invalid_grant")) {
            try GoogleOAuth.tokens(fromResponse: Data(#"{"error":"invalid_grant"}"#.utf8), status: 400, now: referenceNow)
        }
    }

    @Test("Form bodies encode + and / in secrets")
    func formEncoding() throws {
        let request = GoogleOAuth.refreshRequest(client: googleClient, refreshToken: "1//r")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("client_secret=GOCSPX-secret%2B/%3D") || body.contains("client_secret=GOCSPX-secret%2B%2F%3D"))
        #expect(body.contains("grant_type=refresh_token"))
    }

    @Test("Client values are checked before saving")
    func clientFormat() {
        #expect(googleClient.formatProblem == nil)
        #expect(GoogleOAuthClient(clientID: "nope", clientSecret: "x").formatProblem != nil)
        #expect(GoogleOAuthClient(clientID: "1.apps.googleusercontent.com", clientSecret: " ").formatProblem != nil)
    }

    @Test("The full flow: a loopback redirect on a free port is exchanged for tokens")
    func fullFlow() async throws {
        let transport = FakeTransport()
        transport.body = Data(#"{"access_token":"ya29.flow","expires_in":3600,"refresh_token":"1//flow","id_token":"\#(idToken(email: "me@example.com"))"}"#.utf8)

        let browser = BrowserPage()
        let tokens = try await GoogleOAuth.signIn(client: googleClient, transport: transport) { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = items.first { $0.name == "state" }?.value ?? ""
            let redirect = items.first { $0.name == "redirect_uri" }?.value ?? ""
            browser.load(URL(string: "\(redirect)?code=4/xyz&state=\(state)")!)
        }
        #expect(try await browser.page().contains("You’re connected to Google"))

        #expect(tokens.accessToken == "ya29.flow")
        #expect(tokens.email == "me@example.com")
        let body = String(decoding: transport.requests.first?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("code=4/xyz") || body.contains("code=4%2Fxyz"))
        #expect(body.contains("code_verifier="))
    }

    @Test("A sign-in Google rejects shows the browser why")
    func rejectedFlow() async throws {
        let transport = FakeTransport()
        transport.status = 400
        transport.body = Data(#"{"error":"invalid_client"}"#.utf8)

        let browser = BrowserPage()
        await #expect(throws: GoogleOAuthError.tokenRequestFailed("invalid_client")) {
            try await GoogleOAuth.signIn(client: googleClient, transport: transport) { url in
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let state = items.first { $0.name == "state" }?.value ?? ""
                let redirect = items.first { $0.name == "redirect_uri" }?.value ?? ""
                browser.load(URL(string: "\(redirect)?code=4/xyz&state=\(state)")!)
            }
        }
        let page = try await browser.page()
        #expect(page.contains("Couldn’t connect to Google"))
        #expect(page.contains("client ID or secret"))
    }
}

@Suite("Google session")
struct GoogleSessionTests {
    func signedIn(expiresIn seconds: TimeInterval) -> GoogleTokens {
        GoogleTokens(accessToken: "old", refreshToken: "1//r", expiresAt: referenceNow.addingTimeInterval(seconds),
                     email: "me@example.com", grantedScopes: GoogleScope.all)
    }

    @Test("A token that isn't about to expire is used as is")
    func noRefresh() async throws {
        let store = InMemoryCredentialStore()
        let transport = FakeTransport()
        let session = GoogleSession(store: store, transport: transport, now: { referenceNow }, client: { googleClient })
        try await session.save(signedIn(expiresIn: 3000))

        #expect(try await session.freshAccessToken() == "old")
        #expect(transport.requests.isEmpty)
    }

    @Test("An expiring token is refreshed and saved")
    func refresh() async throws {
        let store = InMemoryCredentialStore()
        let transport = FakeTransport()
        transport.body = Data(#"{"access_token":"new","expires_in":3600}"#.utf8)
        let session = GoogleSession(store: store, transport: transport, now: { referenceNow }, client: { googleClient })
        try await session.save(signedIn(expiresIn: 30))

        #expect(try await session.freshAccessToken() == "new")
        #expect(store.loadValue(GoogleTokens.self, for: "googleTokens")?.accessToken == "new")
        #expect(store.loadValue(GoogleTokens.self, for: "googleTokens")?.refreshToken == "1//r")
    }

    @Test("A refused refresh token means sign in again")
    func invalidGrant() async throws {
        let transport = FakeTransport()
        transport.status = 400
        transport.body = Data(#"{"error":"invalid_grant"}"#.utf8)
        let session = GoogleSession(store: InMemoryCredentialStore(), transport: transport, now: { referenceNow }, client: { googleClient })
        try await session.save(signedIn(expiresIn: 0))

        await #expect(throws: GoogleAPIError.needsSignIn) { _ = try await session.freshAccessToken() }
    }

    @Test("Sign-in survives a restart without the network; sign-out forgets it")
    func persistence() async throws {
        let store = InMemoryCredentialStore()
        let first = GoogleSession(store: store, transport: FakeTransport(), now: { referenceNow }, client: { googleClient })
        try await first.save(signedIn(expiresIn: 3000))

        let transport = FakeTransport()
        let second = GoogleSession(store: store, transport: transport, now: { referenceNow }, client: { googleClient })
        #expect(await second.current?.email == "me@example.com")

        await second.signOut()
        #expect(await second.current == nil)
        #expect(store.load("googleTokens") == nil)
        #expect(transport.requests.first?.url == GoogleOAuth.revokeEndpoint)
    }
}

@MainActor
@Suite("Service configuration in Settings")
struct ServiceConfigurationTests {
    @Test("Google client: ID in preferences, secret in the credential store, both survive a restart")
    func google() throws {
        let defaults = freshDefaults()
        let secrets = InMemoryCredentialStore()
        let first = ServiceConfiguration(defaults: defaults, secrets: secrets)
        #expect(first.googleClient == nil)

        try first.saveGoogle(clientID: " 123-abc.apps.googleusercontent.com ", clientSecret: "GOCSPX-1")

        let second = ServiceConfiguration(defaults: defaults, secrets: secrets)
        #expect(second.googleClient == GoogleOAuthClient(clientID: "123-abc.apps.googleusercontent.com", clientSecret: "GOCSPX-1"))
        #expect(defaults.string(forKey: "googleClientSecret") == nil)
    }

    @Test("A blank secret keeps the saved one, so the ID can be edited alone")
    func keepSecret() throws {
        let config = ServiceConfiguration(defaults: freshDefaults(), secrets: InMemoryCredentialStore())
        try config.saveGoogle(clientID: "1.apps.googleusercontent.com", clientSecret: "GOCSPX-1")
        try config.saveGoogle(clientID: "2.apps.googleusercontent.com", clientSecret: "")
        #expect(config.googleClient?.clientSecret == "GOCSPX-1")
        #expect(config.googleClient?.clientID == "2.apps.googleusercontent.com")
    }

    @Test("Bad values are refused with a message")
    func validation() {
        let config = ServiceConfiguration(defaults: freshDefaults(), secrets: InMemoryCredentialStore())
        #expect(throws: ConfigurationError.self) { try config.saveGoogle(clientID: "nope", clientSecret: "x") }
        #expect(throws: ConfigurationError.self) { try config.saveSlack(clientID: "", clientSecret: "x") }
        #expect(config.googleClient == nil)
    }

    @Test("Slack client and clearing")
    func slack() throws {
        let config = ServiceConfiguration(defaults: freshDefaults(), secrets: InMemoryCredentialStore())
        try config.saveSlack(clientID: "111.222", clientSecret: "abc")
        #expect(config.slackClient == SlackOAuthConfiguration(clientID: "111.222", clientSecret: "abc"))
        config.clearSlack()
        #expect(config.slackClient == nil)
        config.clearGoogle()
        #expect(!config.isGoogleConfigured)
    }
}
