import Foundation

/// The Gmail Source: keeps the Emails matching the user's query in the Item store.
///
/// The first refresh (and any refresh after the query changes) is a Backfill:
/// a full `messages.list` with the query. After that, the app calls ``refresh(query:)``
/// about every 30 seconds and the Source asks `history.list` what changed since the last
/// history ID. When something changed, it re-runs the query (IDs only) to find which
/// Emails now match. That adds new Emails and removes ones that no longer match, for
/// example because they were read elsewhere (LIF-1). An expired history ID falls back to
/// a full query.
@MainActor
public final class GmailSource {
    public static let pollInterval: Duration = .seconds(30)

    private let api: GmailAPI
    private let store: ItemStore
    private let accountEmail: String?

    /// The history ID to poll from. `nil` until the first Backfill.
    public private(set) var historyID: String?
    private var syncedQuery: String?
    private var emails: [String: Item] = [:]

    public init(api: GmailAPI, store: ItemStore, accountEmail: String?) {
        self.api = api
        self.store = store
        self.accountEmail = accountEmail
    }

    public func refresh(query: String) async throws {
        guard let historyID, syncedQuery == query else {
            try await fullSync(query: query)
            return
        }

        let changes: GmailChanges
        do {
            changes = try await api.changes(since: historyID)
        } catch GmailAPIError.historyExpired {
            try await fullSync(query: query)
            return
        }

        if !changes.changedMessageIDs.isEmpty {
            try await apply(matchingIDs: api.listMessageIDs(query: query), isBackfill: false)
        }
        self.historyID = changes.latestHistoryID
    }

    /// Forgets everything, so the next refresh is a full Backfill.
    public func reset() {
        historyID = nil
        syncedQuery = nil
        emails = [:]
    }

    private func fullSync(query: String) async throws {
        // Read the history ID first, so nothing that happens during the query is missed.
        let latestHistoryID = try await api.currentHistoryID()
        if syncedQuery != query { emails = [:] }
        // A full query is a Backfill: its Emails appear silently (ALR-8).
        try await apply(matchingIDs: api.listMessageIDs(query: query), isBackfill: true)
        historyID = latestHistoryID
        syncedQuery = query
    }

    /// Makes the Source's Emails exactly the messages in `matchingIDs`, fetching
    /// metadata only for ones it doesn't have yet.
    private func apply(matchingIDs: [String], isBackfill: Bool) async throws {
        let missing = matchingIDs.filter { emails[$0] == nil }
        let api = self.api
        let fetched = try await withThrowingTaskGroup(of: GmailMessageMetadata.self) { group in
            for id in missing {
                group.addTask { try await api.messageMetadata(id: id) }
            }
            var results: [GmailMessageMetadata] = []
            for try await metadata in group {
                results.append(metadata)
            }
            return results
        }

        var updated: [String: Item] = [:]
        for id in matchingIDs {
            updated[id] = emails[id]
        }
        for metadata in fetched {
            updated[metadata.id] = Self.item(from: metadata, accountEmail: accountEmail)
        }
        emails = updated
        store.replaceItems(Array(emails.values), from: .gmail, isBackfill: isBackfill)
    }

    static func item(from metadata: GmailMessageMetadata, accountEmail: String?) -> Item {
        Item(
            id: .init(source: .gmail, value: metadata.id),
            kind: .email,
            title: metadata.subject?.nilIfBlank ?? "(No subject)",
            detail: metadata.from.map(EmailAddress.displayName(from:)) ?? "(Unknown sender)",
            date: metadata.receivedAt,
            openURL: openURL(messageID: metadata.id, accountEmail: accountEmail)
        )
    }

    /// Opens the message in Gmail in the browser, in the right account (INT-2).
    static func openURL(messageID: String, accountEmail: String?) -> URL? {
        var components = URLComponents(string: "https://mail.google.com/mail/u/")!
        if let accountEmail {
            components.queryItems = [URLQueryItem(name: "authuser", value: accountEmail)]
        }
        components.fragment = "all/\(messageID)"
        return components.url
    }
}

enum EmailAddress {
    /// The sender's name from a `From` header, or the address if there's no name.
    ///
    /// `"Jamie Fox" <jamie@example.com>` → `Jamie Fox`; `jamie@example.com` → `jamie@example.com`.
    static func displayName(from header: String) -> String {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close else {
            return trimmed
        }
        let name = trimmed[..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return String(trimmed[trimmed.index(after: open)..<close])
    }
}
