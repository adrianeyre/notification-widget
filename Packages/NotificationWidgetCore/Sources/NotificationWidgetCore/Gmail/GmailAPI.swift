import Foundation

/// A Gmail message's metadata. Only headers are fetched (`format=metadata`), never the body.
public struct GmailMessageMetadata: Equatable, Sendable {
    public var id: String
    public var threadID: String?
    public var from: String?
    public var subject: String?
    public var receivedAt: Date

    public init(id: String, threadID: String? = nil, from: String?, subject: String?, receivedAt: Date) {
        self.id = id
        self.threadID = threadID
        self.from = from
        self.subject = subject
        self.receivedAt = receivedAt
    }
}

/// What changed in the mailbox since a history ID.
public struct GmailChanges: Equatable, Sendable {
    /// Messages that were added, deleted, or had labels added or removed.
    public var changedMessageIDs: Set<String>
    /// The mailbox's latest history ID, to poll from next time.
    public var latestHistoryID: String

    public init(changedMessageIDs: Set<String>, latestHistoryID: String) {
        self.changedMessageIDs = changedMessageIDs
        self.latestHistoryID = latestHistoryID
    }
}

public enum GmailAPIError: Error, Equatable, Sendable {
    /// The start history ID is too old for `history.list` (HTTP 404). Run a full query instead.
    case historyExpired
}

/// The Gmail API calls the Gmail Source needs.
public protocol GmailAPI: Sendable {
    /// The mailbox's current history ID (`users.getProfile`).
    func currentHistoryID() async throws -> String
    /// IDs of messages matching `query` (`messages.list`), newest first.
    func listMessageIDs(query: String) async throws -> [String]
    /// Changes since `historyID` (`history.list`). Throws ``GmailAPIError/historyExpired``
    /// when the history ID is too old.
    func changes(since historyID: String) async throws -> GmailChanges
    /// One message's headers (`messages.get` with `format=metadata`).
    func messageMetadata(id: String) async throws -> GmailMessageMetadata
}

/// The live Gmail API.
public struct GoogleGmailAPI: GmailAPI {
    /// The most Emails fetched by a full query. The Panel shows 5 plus "+N more".
    public static let maxMessages = 100

    private let client: GoogleAuthorizedClient
    private let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!

    public init(client: GoogleAuthorizedClient) {
        self.client = client
    }

    public func currentHistoryID() async throws -> String {
        struct Profile: Decodable { var historyId: String }
        let profile: Profile = try await client.get(url("profile"))
        return profile.historyId
    }

    public func listMessageIDs(query: String) async throws -> [String] {
        let response: GmailMessageListResponse = try await client.get(url("messages", [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(Self.maxMessages)),
        ]))
        return response.messages?.map(\.id) ?? []
    }

    public func changes(since historyID: String) async throws -> GmailChanges {
        var changed = Set<String>()
        var latest = historyID
        var pageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "startHistoryId", value: historyID),
                URLQueryItem(name: "maxResults", value: "500"),
            ]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: GmailHistoryResponse
            do {
                page = try await client.get(url("history", query))
            } catch GoogleAPIError.http(status: 404, body: _) {
                throw GmailAPIError.historyExpired
            }
            changed.formUnion(page.changedMessageIDs)
            latest = page.historyId ?? latest
            pageToken = page.nextPageToken
        } while pageToken != nil
        return GmailChanges(changedMessageIDs: changed, latestHistoryID: latest)
    }

    public func messageMetadata(id: String) async throws -> GmailMessageMetadata {
        let message: GmailMessageResponse = try await client.get(url("messages/\(id)", [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "fields", value: "id,threadId,internalDate,payload/headers"),
        ]))
        return message.metadata
    }

    func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }
}

// MARK: - Response types

struct GmailMessageListResponse: Decodable {
    struct MessageRef: Decodable { var id: String }
    var messages: [MessageRef]?
}

struct GmailHistoryResponse: Decodable {
    struct MessageRef: Decodable { var id: String }
    struct MessageChange: Decodable { var message: MessageRef }
    struct Record: Decodable {
        var messagesAdded: [MessageChange]?
        var messagesDeleted: [MessageChange]?
        var labelsAdded: [MessageChange]?
        var labelsRemoved: [MessageChange]?
    }

    var history: [Record]?
    var historyId: String?
    var nextPageToken: String?

    var changedMessageIDs: Set<String> {
        var ids = Set<String>()
        for record in history ?? [] {
            for change in [record.messagesAdded, record.messagesDeleted, record.labelsAdded, record.labelsRemoved] {
                ids.formUnion(change?.map(\.message.id) ?? [])
            }
        }
        return ids
    }
}

struct GmailMessageResponse: Decodable {
    struct Header: Decodable { var name: String; var value: String }
    struct Payload: Decodable { var headers: [Header]? }

    var id: String
    var threadId: String?
    var internalDate: String?
    var payload: Payload?

    func header(_ name: String) -> String? {
        payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var metadata: GmailMessageMetadata {
        let milliseconds = internalDate.flatMap(Double.init) ?? 0
        return GmailMessageMetadata(
            id: id,
            threadID: threadId,
            from: header("From"),
            subject: header("Subject"),
            receivedAt: Date(timeIntervalSince1970: milliseconds / 1000)
        )
    }
}
