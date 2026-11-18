import Foundation
import Testing
@testable import NotificationWidgetCore

/// A fake mailbox that records which Gmail calls were made.
final class FakeGmailAPI: GmailAPI, @unchecked Sendable {
    private let lock = NSLock()
    var historyID = "100"
    var matching: [String] = []
    var pendingChanges: Set<String> = []
    var historyExpired = false
    private(set) var calls: [String] = []

    private func record(_ call: String) { lock.withLock { calls.append(call) } }

    func currentHistoryID() async throws -> String {
        record("profile")
        return historyID
    }

    func listMessageIDs(query: String) async throws -> [String] {
        record("list:\(query)")
        return matching
    }

    func changes(since historyID: String) async throws -> GmailChanges {
        record("history:\(historyID)")
        if historyExpired { throw GmailAPIError.historyExpired }
        defer { pendingChanges = [] }
        return GmailChanges(changedMessageIDs: pendingChanges, latestHistoryID: self.historyID)
    }

    func messageMetadata(id: String) async throws -> GmailMessageMetadata {
        record("get:\(id)")
        return GmailMessageMetadata(id: id, from: "Sender \(id) <\(id)@example.com>", subject: "Subject \(id)", receivedAt: referenceNow)
    }

    func resetCalls() { lock.withLock { calls = [] } }
}

@MainActor
@Suite("Gmail Emails")
struct GmailTests {
    let query = AppSettings.defaultGmailQuery

    func makeSource() -> (GmailSource, FakeGmailAPI, ItemStore) {
        let api = FakeGmailAPI()
        let store = ItemStore(persistence: InMemoryDismissalPersistence(), now: referenceNow)
        return (GmailSource(api: api, store: store, accountEmail: "me@example.com"), api, store)
    }

    func emailIDs(_ store: ItemStore) -> Set<String> {
        Set(store.visibleItems.map(\.id.value))
    }

    @Test("Backfill runs the full query and fetches metadata for each Email")
    func backfill() async throws {
        let (source, api, store) = makeSource()
        api.matching = ["a", "b"]

        try await source.refresh(query: query)

        #expect(api.calls.first == "profile")
        #expect(api.calls.contains("list:\(query)"))
        #expect(Set(api.calls.filter { $0.hasPrefix("get:") }) == ["get:a", "get:b"])
        #expect(emailIDs(store) == ["a", "b"])
        #expect(source.historyID == "100")
    }

    @Test("History-based add: a new message is added, and only it is fetched")
    func historyAdd() async throws {
        let (source, api, store) = makeSource()
        api.matching = ["a"]
        try await source.refresh(query: query)
        api.resetCalls()

        api.matching = ["new", "a"]
        api.pendingChanges = ["new"]
        api.historyID = "120"
        try await source.refresh(query: query)

        #expect(api.calls == ["history:100", "list:\(query)", "get:new"])
        #expect(emailIDs(store) == ["a", "new"])
        #expect(source.historyID == "120")
    }

    @Test("History-based remove: an Email read elsewhere no longer matches and is removed")
    func historyRemove() async throws {
        let (source, api, store) = makeSource()
        api.matching = ["a", "b"]
        try await source.refresh(query: query)
        api.resetCalls()

        api.matching = ["b"]
        api.pendingChanges = ["a"]
        try await source.refresh(query: query)

        #expect(api.calls == ["history:100", "list:\(query)"])
        #expect(emailIDs(store) == ["b"])
    }

    @Test("No history changes means no query and no metadata fetches")
    func noChanges() async throws {
        let (source, api, _) = makeSource()
        api.matching = ["a"]
        try await source.refresh(query: query)
        api.resetCalls()

        try await source.refresh(query: query)

        #expect(api.calls == ["history:100"])
    }

    @Test("An expired history ID falls back to a full query")
    func expiredHistory() async throws {
        let (source, api, store) = makeSource()
        api.matching = ["a"]
        try await source.refresh(query: query)
        api.resetCalls()

        api.historyExpired = true
        api.historyID = "500"
        api.matching = ["a", "c"]
        try await source.refresh(query: query)

        #expect(api.calls == ["history:100", "profile", "list:\(query)", "get:c"])
        #expect(emailIDs(store) == ["a", "c"])
        #expect(source.historyID == "500")
    }

    @Test("Changing the query runs a new full query")
    func queryChange() async throws {
        let (source, api, _) = makeSource()
        api.matching = ["a"]
        try await source.refresh(query: query)
        api.resetCalls()

        try await source.refresh(query: "is:unread")

        #expect(api.calls == ["profile", "list:is:unread", "get:a"])
    }

    @Test("A Dismissed Email stays hidden across polls")
    func dismissed() async throws {
        let (source, api, store) = makeSource()
        api.matching = ["a", "b"]
        try await source.refresh(query: query)

        store.dismiss(.init(source: .gmail, value: "a"))
        api.pendingChanges = ["b"]
        try await source.refresh(query: query)

        #expect(emailIDs(store) == ["b"])
    }

    @Test("Email Items show sender name and subject, and open in Gmail")
    func itemFields() async throws {
        let (source, api, store) = makeSource()
        api.matching = ["abc"]
        try await source.refresh(query: query)

        let item = try #require(store.visibleItems.first)
        #expect(item.kind == .email)
        #expect(item.detail == "Sender abc")
        #expect(item.title == "Subject abc")
        #expect(item.openURL?.absoluteString == "https://mail.google.com/mail/u/?authuser=me@example.com#all/abc")
    }

    @Test("Sender display names", arguments: [
        ("\"Jamie Fox\" <jamie@example.com>", "Jamie Fox"),
        ("Jamie Fox <jamie@example.com>", "Jamie Fox"),
        ("<jamie@example.com>", "jamie@example.com"),
        ("jamie@example.com", "jamie@example.com"),
        ("\"Fox, Jamie\" <jamie@example.com>", "Fox, Jamie"),
    ])
    func senderNames(header: String, expected: String) {
        #expect(EmailAddress.displayName(from: header) == expected)
    }

    @Test("Sender addresses", arguments: [
        ("\"Jamie Fox\" <Jamie@Example.com>", "Jamie@Example.com"),
        ("<jamie@example.com>", "jamie@example.com"),
        (" jamie@example.com ", "jamie@example.com"),
        ("Jamie Fox", nil),
        ("", nil),
    ] as [(String, String?)])
    func senderAddresses(header: String, expected: String?) {
        #expect(EmailAddress.address(from: header) == expected)
    }

    @Test("Gravatar URLs hash the trimmed, lower-cased address and 404 when there's no photo")
    func gravatar() throws {
        // SHA-256 of "myemailaddress@example.com", from Gravatar's documentation.
        let hash = "84059b07d4be67b806386c0aad8070a23f18836bbaae342275dc0a83414c32ee"
        let url = try #require(Gravatar.url(for: " MyEmailAddress@example.com "))
        #expect(url.absoluteString == "https://gravatar.com/avatar/\(hash)?s=64&d=404")
        #expect(Gravatar.url(for: "  ") == nil)
    }

    @Test("An Email carries its sender's Gravatar")
    func emailAvatar() {
        let metadata = GmailMessageMetadata(id: "m1", from: "Jamie Fox <jamie@example.com>", subject: "Hi", receivedAt: referenceNow)
        let item = GmailSource.item(from: metadata, accountEmail: nil)
        #expect(item.avatarURL == Gravatar.url(for: "jamie@example.com"))

        let noAddress = GmailMessageMetadata(id: "m2", from: nil, subject: "Hi", receivedAt: referenceNow)
        #expect(GmailSource.item(from: noAddress, accountEmail: nil).avatarURL == nil)
    }

    @Test("Decodes history and metadata responses")
    func decoding() throws {
        let history = try JSONDecoder().decode(GmailHistoryResponse.self, from: Fixture.data("gmail-history"))
        #expect(history.changedMessageIDs == ["m-new", "m-read"])
        #expect(history.historyId == "1005")

        let message = try JSONDecoder().decode(GmailMessageResponse.self, from: Fixture.data("gmail-message-metadata"))
        #expect(message.metadata.from == "\"Jamie Fox\" <jamie@example.com>")
        #expect(message.metadata.subject == "Quarterly planning: agenda")
        #expect(message.metadata.receivedAt == Date(timeIntervalSince1970: 1_795_420_800))
    }

    @Test("Metadata requests ask for headers only, never the body")
    func metadataOnly() async throws {
        let transport = FakeTransport()
        transport.body = try Fixture.data("gmail-message-metadata")
        let api = GoogleGmailAPI(client: GoogleAuthorizedClient(tokenProvider: FakeTokenProvider(), transport: transport))

        _ = try await api.messageMetadata(id: "18c2f0a1b2c3d4e5")

        let url = try #require(transport.requests.first?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "format", value: "metadata")))
    }

    @Test("history.list returning 404 is reported as an expired history ID")
    func history404() async throws {
        let transport = FakeTransport()
        transport.status = 404
        let api = GoogleGmailAPI(client: GoogleAuthorizedClient(tokenProvider: FakeTokenProvider(), transport: transport))

        await #expect(throws: GmailAPIError.historyExpired) {
            _ = try await api.changes(since: "1")
        }
    }
}
