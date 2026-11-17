import Foundation

/// The Google OAuth scopes the app asks for (SRC-1).
public enum GoogleScope {
    public static let calendarReadOnly = "https://www.googleapis.com/auth/calendar.readonly"
    public static let gmailReadOnly = "https://www.googleapis.com/auth/gmail.readonly"
    public static let all = [calendarReadOnly, gmailReadOnly]
}

/// Supplies a fresh Google access token, refreshing it first if it's about to expire.
///
/// The app implements this with the GoogleSignIn SDK. Throwing
/// ``GoogleAPIError/needsSignIn`` means the refresh failed and the user must sign in again.
public protocol GoogleAccessTokenProvider: Sendable {
    func freshAccessToken() async throws -> String
}

/// Sends HTTP requests. `URLSession` conforms; tests use a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public enum GoogleAPIError: Error, Equatable, Sendable {
    /// No Google Account is connected.
    case notSignedIn
    /// The token couldn't be refreshed or was rejected: the user must sign in again.
    case needsSignIn
    /// The request failed with an unexpected HTTP status.
    case http(status: Int, body: String)
}

/// Makes authorised Google API calls, refreshing the access token before each one
/// (the helper the Calendar and Gmail Sources use).
public struct GoogleAuthorizedClient: Sendable {
    private let tokenProvider: GoogleAccessTokenProvider
    private let transport: HTTPTransport
    /// Called when a call shows the user needs to sign in again, so the Account
    /// state can switch to "needs sign-in" for the health indicator.
    private let onNeedsSignIn: @Sendable () async -> Void

    public init(
        tokenProvider: GoogleAccessTokenProvider,
        transport: HTTPTransport = URLSession.shared,
        onNeedsSignIn: @escaping @Sendable () async -> Void = {}
    ) {
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.onNeedsSignIn = onNeedsSignIn
    }

    /// Sends an authorised GET to `url` and decodes the JSON response as `T`.
    public func get<T: Decodable>(_ url: URL, as type: T.Type = T.self) async throws -> T {
        let data = try await get(url)
        return try GoogleJSON.decoder.decode(T.self, from: data)
    }

    /// Sends an authorised GET to `url` and returns the body.
    public func get(_ url: URL) async throws -> Data {
        let token: String
        do {
            token = try await tokenProvider.freshAccessToken()
        } catch GoogleAPIError.needsSignIn {
            await onNeedsSignIn()
            throw GoogleAPIError.needsSignIn
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            await onNeedsSignIn()
            throw GoogleAPIError.needsSignIn
        default:
            throw GoogleAPIError.http(
                status: response.statusCode,
                body: String(decoding: data.prefix(2_000), as: UTF8.self)
            )
        }
    }
}

enum GoogleJSON {
    static let decoder = JSONDecoder()
}
