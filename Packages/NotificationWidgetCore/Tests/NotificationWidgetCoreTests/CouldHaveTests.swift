import Foundation
import Testing
@testable import NotificationWidgetCore

@Suite("Ignore Focus (ALR-9)")
struct IgnoreFocusTests {
    @Test("Off by default")
    func offByDefault() {
        #expect(AlertCategory.allCases.allSatisfy { !AlertPreference.defaults(for: $0).ignoresFocus })
    }

    @Test("A category that ignores Focus Alerts normally while Focus is on")
    func ignores() {
        var preference = AlertPreference.defaults(for: .dm)
        preference.ignoresFocus = true
        #expect(AlertPresentationPolicy.presentation(for: preference, focus: .on)
            == AlertPresentation(sound: .system("Pop"), shake: true, raisePanel: true))
    }

    @Test("Other categories stay silent during Focus")
    func othersSilent() {
        #expect(AlertPresentationPolicy.presentation(for: .defaults(for: .email), focus: .on) == .silent)
    }

    @Test("Preferences saved before Ignore Focus existed still load")
    func oldSettingsDecode() throws {
        let json = #"{"soundEnabled":false,"soundName":"Ping","shakeEnabled":true}"#
        let preference = try JSONDecoder().decode(AlertPreference.self, from: Data(json.utf8))
        #expect(preference == AlertPreference(soundEnabled: false, soundName: "Ping", shakeEnabled: true, ignoresFocus: false))
    }
}

@Suite("DM and Mention Alert settings (ALR-10)")
struct DMMentionSettingsTests {
    func item(_ kind: ItemKind) -> Item {
        Item(id: .init(source: kind.source, value: UUID().uuidString), kind: kind, title: "x", date: referenceNow)
    }

    @Test("Each Item kind maps to its own category, DMs before Mentions")
    func categories() {
        #expect(AlertCategory.categories(of: [item(.mention), item(.dm), item(.mention)]) == [.dm, .mention])
        #expect(AlertCategory(kind: .email) == .email)
        #expect(AlertCategory(kind: .event) == .event)
    }

    @Test("A mixed Slack Alert plays the DM sound and shakes if either does")
    func mixed() {
        let preferences: [AlertCategory: AlertPreference] = [
            .dm: AlertPreference(soundEnabled: true, soundName: "Pop", shakeEnabled: false),
            .mention: AlertPreference(soundEnabled: true, soundName: "Tink", shakeEnabled: true),
        ]
        let presentation = AlertPresentationPolicy.presentation(for: [.dm, .mention], preferences: { preferences[$0]! }, focus: .off)
        #expect(presentation == AlertPresentation(sound: .system("Pop"), shake: true, raisePanel: true))
    }

    @Test("With DM sound off, a mixed Alert uses the Mention sound")
    func dmSoundOff() {
        let preferences: [AlertCategory: AlertPreference] = [
            .dm: AlertPreference(soundEnabled: false, soundName: "Pop", shakeEnabled: false),
            .mention: AlertPreference(soundEnabled: true, soundName: "Tink", shakeEnabled: false),
        ]
        let presentation = AlertPresentationPolicy.presentation(for: [.dm, .mention], preferences: { preferences[$0]! }, focus: .off)
        #expect(presentation.sound == .system("Tink"))
        #expect(presentation.shake == false)
    }

    @Test("During Focus, only the category that ignores Focus counts")
    func focusMixed() {
        var mention = AlertPreference.defaults(for: .mention)
        mention.ignoresFocus = true
        let preferences: [AlertCategory: AlertPreference] = [.dm: .defaults(for: .dm), .mention: mention]
        let presentation = AlertPresentationPolicy.presentation(for: [.dm, .mention], preferences: { preferences[$0]! }, focus: .on)
        #expect(presentation.sound == .system("Tink"))
    }

    @Test("Old single Slack settings migrate to both DMs and Mentions")
    func migration() throws {
        let old: [String: AlertPreference] = [
            "slack": AlertPreference(soundEnabled: false, soundName: "Frog", shakeEnabled: false),
            "gmail": AlertPreference(soundName: "Ping"),
        ]
        let loaded = AppSettings.loadAlertPreferences(try JSONEncoder().encode(old))
        #expect(loaded[.dm] == old["slack"])
        #expect(loaded[.mention] == old["slack"])
        #expect(loaded[.email]?.soundName == "Ping")
        #expect(loaded[.event] == .defaults(for: .event))
    }

    @MainActor
    @Test("Separate DM and Mention settings survive a restart")
    func persistence() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.alertPreferences[.mention] = AlertPreference(soundEnabled: true, soundName: "Submarine", shakeEnabled: false)

        let second = AppSettings(defaults: defaults)
        #expect(second.alertPreference(for: .mention).soundName == "Submarine")
        #expect(second.alertPreference(for: .dm) == .defaults(for: .dm))
    }
}

@Suite("Custom sound files (ALR-11)")
struct CustomSoundTests {
    func makeLibrary() -> (CustomSoundLibrary, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "NWSoundTests-\(UUID().uuidString)")
        return (CustomSoundLibrary(folder: root.appending(path: "Sounds")), root)
    }

    @Test("Stored values round-trip for system and custom sounds")
    func references() {
        #expect(AlertSoundReference(storedValue: "Glass") == .system("Glass"))
        #expect(AlertSoundReference(storedValue: "file:ding.m4a") == .file("ding.m4a"))
        #expect(AlertSoundReference.file("ding.m4a").storedValue == "file:ding.m4a")
        #expect(AlertSoundReference.file("ding.m4a").displayName == "ding")
    }

    @Test("Importing copies the file into the sounds folder; same names get numbered")
    func importing() throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "ding.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("RIFF".utf8).write(to: source)

        let first = try library.importSound(from: source)
        let second = try library.importSound(from: source)

        #expect(first == .file("ding.wav"))
        #expect(second == .file("ding 2.wav"))
        #expect(library.url(for: first) != nil)
        #expect(library.importedSounds() == [.file("ding 2.wav"), .file("ding.wav")])
        #expect(library.url(for: .system("Glass")) == nil)
    }

    @Test("Only AIFF, WAV, MP3 and M4A are accepted")
    func types() throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let text = root.appending(path: "notes.txt")
        try Data("hi".utf8).write(to: text)

        #expect(throws: CustomSoundLibrary.ImportError.unsupportedType("txt")) {
            try library.importSound(from: text)
        }
    }
}

@Suite("Repeat Alerts for Events starting now (ALR-12)")
struct EventNudgeTests {
    let standup = timedEvent("standup", startsIn: 0)

    @Test("Fires at the start and every N minutes, up to 10 minutes")
    func schedule() {
        var scheduler = EventNudgeScheduler()
        var fired: [Int] = []
        for second in stride(from: -60, through: 12 * 60, by: 5) {
            let now = referenceNow.addingTimeInterval(TimeInterval(second))
            if !scheduler.due([standup], acknowledged: [], intervalMinutes: 2, now: now).isEmpty {
                fired.append(second / 60)
            }
        }
        #expect(fired == [0, 2, 4, 6, 8, 10])
    }

    @Test("Stops once the Event is clicked or Dismissed")
    func acknowledged() {
        var scheduler = EventNudgeScheduler()
        #expect(scheduler.due([standup], acknowledged: [], intervalMinutes: 2, now: referenceNow).count == 1)
        #expect(scheduler.due([standup], acknowledged: [standup.id], intervalMinutes: 2, now: referenceNow.addingTimeInterval(120)).isEmpty)
    }

    @Test("0 minutes turns repeating off")
    func off() {
        var scheduler = EventNudgeScheduler()
        #expect(scheduler.due([standup], acknowledged: [], intervalMinutes: 0, now: referenceNow).isEmpty)
    }

    @Test("After sleeping through several slots, it fires once")
    func sleptThrough() {
        var scheduler = EventNudgeScheduler()
        _ = scheduler.due([standup], acknowledged: [], intervalMinutes: 2, now: referenceNow)
        #expect(scheduler.due([standup], acknowledged: [], intervalMinutes: 2, now: referenceNow.addingTimeInterval(7 * 60)).count == 1)
        #expect(scheduler.due([standup], acknowledged: [], intervalMinutes: 2, now: referenceNow.addingTimeInterval(7 * 60 + 30)).isEmpty)
    }

    @Test("All-day and ended Events are never repeated")
    func excluded() {
        var scheduler = EventNudgeScheduler()
        let allDay = timedEvent("offsite", startsIn: 0, allDay: true)
        let short = Item(id: .init(source: .googleCalendar, value: "short"), kind: .event, title: "short", date: referenceNow,
                         event: EventDetails(start: referenceNow, end: referenceNow.addingTimeInterval(60), isAllDay: false, reminderMinutes: []))
        #expect(scheduler.due([allDay, short], acknowledged: [], intervalMinutes: 2, now: referenceNow.addingTimeInterval(120)).isEmpty)
    }

    @MainActor
    @Test("The engine nudges until the Event is acknowledged, bypassing fire-once")
    func engine() {
        let clock = TestClock()
        let engine = AlertEngine(clock: { clock.now })
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }

        engine.reminderDue([standup])
        engine.nudge([standup])
        clock.advance(120)
        engine.nudge([standup])
        engine.clearHighlight(standup.id)
        engine.nudge([standup])

        #expect(alerts.count == 3)
        #expect(engine.acknowledgedIDs.contains(standup.id))
    }

    @MainActor
    @Test("Repeat interval defaults to 2 minutes and persists")
    func setting() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.eventRepeatMinutes == 2)
        first.eventRepeatMinutes = 5
        #expect(AppSettings(defaults: defaults).eventRepeatMinutes == 5)
    }
}

@Suite("Screen capture setting (PNL-7)")
struct ScreenCaptureSettingTests {
    @MainActor
    @Test("Off by default and persists")
    func setting() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.allowScreenCapture == false)
        first.allowScreenCapture = true
        #expect(AppSettings(defaults: defaults).allowScreenCapture)
    }
}

@Suite("Slack OAuth (SRC-8)")
struct SlackOAuthTests {
    let configuration = SlackOAuthConfiguration(clientID: "123.456", clientSecret: "shh")

    @Test("The authorize URL asks for user scopes and redirects to the loopback port")
    func authorizeURL() throws {
        let url = SlackOAuth.authorizeURL(configuration, state: "abc")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "slack.com")
        #expect(query.contains(URLQueryItem(name: "client_id", value: "123.456")))
        #expect(query.contains(URLQueryItem(name: "redirect_uri", value: "http://localhost:53682/slack/oauth/callback")))
        #expect(query.contains(URLQueryItem(name: "state", value: "abc")))
        let scopes = try #require(query.first { $0.name == "user_scope" }?.value)
        #expect(scopes.split(separator: ",").count == 9)
        #expect(!query.contains { $0.name == "scope" })
    }

    @Test("The callback gives the code only when the state matches")
    func callback() throws {
        #expect(try SlackOAuth.code(fromCallback: "/slack/oauth/callback?code=xyz&state=abc", expectedState: "abc") == "xyz")
        #expect(throws: SlackOAuthError.stateMismatch) {
            try SlackOAuth.code(fromCallback: "/slack/oauth/callback?code=xyz&state=evil", expectedState: "abc")
        }
        #expect(throws: SlackOAuthError.denied("access_denied")) {
            try SlackOAuth.code(fromCallback: "/slack/oauth/callback?error=access_denied&state=abc", expectedState: "abc")
        }
    }

    @Test("The exchange response gives the user token")
    func exchange() throws {
        let ok = #"{"ok":true,"app_id":"A1","authed_user":{"id":"U1","scope":"im:history","access_token":"xoxp-1-2-3","token_type":"user"},"team":{"id":"T1"}}"#
        #expect(try SlackOAuth.userToken(fromExchangeResponse: Data(ok.utf8)) == "xoxp-1-2-3")
        let bad = #"{"ok":false,"error":"invalid_code"}"#
        #expect(throws: SlackOAuthError.exchangeFailed("invalid_code")) {
            try SlackOAuth.userToken(fromExchangeResponse: Data(bad.utf8))
        }
    }

    @Test("The exchange request posts the code with the client credentials")
    func exchangeRequest() throws {
        let request = SlackOAuth.exchangeRequest(configuration, code: "xyz")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(request.url?.absoluteString == "https://slack.com/api/oauth.v2.access")
        #expect(body.contains("code=xyz"))
        #expect(body.contains("client_secret=shh"))
    }

    @Test("Request targets are read from the HTTP request line")
    func requestLine() {
        #expect(LoopbackRedirectReceiver.requestTarget(fromRequest: "GET /slack/oauth/callback?code=1 HTTP/1.1\r\nHost: localhost\r\n\r\n")
            == "/slack/oauth/callback?code=1")
        #expect(LoopbackRedirectReceiver.requestTarget(fromRequest: "POST / HTTP/1.1\r\n\r\n") == nil)
    }

    @Test("The full flow: the browser's redirect to the loopback port is exchanged for a token")
    func fullFlow() async throws {
        let configuration = SlackOAuthConfiguration(clientID: "1", clientSecret: "2", port: UInt16.random(in: 50_000...59_000))
        let transport = FakeTransport()
        transport.body = Data(#"{"ok":true,"authed_user":{"access_token":"xoxp-flow"}}"#.utf8)

        let browser = BrowserPage()
        let token = try await SlackOAuth.signIn(configuration, transport: transport) { authorizeURL in
            // Play the browser: follow Slack's redirect back to the app with the same state.
            let state = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
            browser.load(URL(string: "http://127.0.0.1:\(configuration.port)/slack/oauth/callback?code=abc&state=\(state)")!)
        }

        #expect(token == "xoxp-flow")
        // The browser is answered only once the token is in hand, so it can say so.
        let page = try await browser.page()
        #expect(page.contains("You’re connected to Slack"))
        #expect(page.contains("Connected"))
        let body = String(decoding: transport.requests.first?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("code=abc"))
    }
}

@Suite("Sign-in callback page")
struct OAuthCallbackPageTests {
    @Test("Signed in: names the service and what it loads, with the badge turning Connected")
    func signedIn() {
        let page = OAuthCallbackPage.response(.google, .signedIn)
        #expect(page.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(page.contains("<title>Connected to Google · Notification Widget</title>"))
        #expect(page.contains("You’re connected to Google"))
        #expect(page.contains("Calendar and Gmail"))
        #expect(page.contains(#"<span class="badge" data-animate>"#))
    }

    @Test("Cancelled: says nothing was shared and how to try again")
    func cancelled() {
        let page = OAuthCallbackPage.response(.slack, .cancelled)
        #expect(page.contains("Sign-in was cancelled"))
        #expect(page.contains("Sign in with Slack…"))
        #expect(!page.contains(#"<span class="badge" data-animate>"#))
    }

    @Test("Failed: shows the message, escaped")
    func failed() {
        let page = OAuthCallbackPage.response(.google, .failed("Bad <script>alert(1)</script> & co"))
        #expect(page.contains("Couldn’t connect to Google"))
        #expect(page.contains("Bad &lt;script&gt;alert(1)&lt;/script&gt; &amp; co"))
        #expect(!page.contains("<script>alert"))
    }

    @Test("Locked down: a nonce'd script only, no referrer, not cached, a correct length")
    func headers() throws {
        let page = OAuthCallbackPage.response(.slack, .signedIn)
        let parts = page.components(separatedBy: "\r\n\r\n")
        let head = try #require(parts.first)
        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        #expect(head.contains("Content-Length: \(body.utf8.count)"))
        #expect(head.contains("Referrer-Policy: no-referrer"))
        #expect(head.contains("Cache-Control: no-store"))
        let nonce = try #require(head.firstMatch(of: /script-src 'nonce-([0-9A-F]+)'/)?.1)
        #expect(body.contains("<script nonce=\"\(nonce)\">"))
        #expect(!body.contains("http://") && !body.contains("https://"))
    }

    @Test("Denied sign-ins read as cancelled; other failures carry their message")
    func outcomes() {
        #expect(GoogleOAuth.callbackOutcome(for: GoogleOAuthError.denied("access_denied")) == .cancelled)
        #expect(GoogleOAuth.callbackOutcome(for: GoogleOAuthError.stateMismatch) == .failed(GoogleOAuthError.stateMismatch.message))
        #expect(SlackOAuth.callbackOutcome(for: SlackOAuthError.denied("access_denied")) == .cancelled)
        #expect(SlackOAuth.callbackOutcome(for: SlackOAuthError.exchangeFailed("bad")) == .failed(SlackOAuthError.exchangeFailed("bad").message))
    }
}

/// Plays the browser in a sign-in flow: loads the callback URL and keeps the page it gets.
final class BrowserPage: @unchecked Sendable {
    private var task: Task<String, Error>?

    func load(_ url: URL) {
        task = Task { String(decoding: try await URLSession.shared.data(from: url).0, as: UTF8.self) }
    }

    func page() async throws -> String {
        try await #require(task).value
    }
}
