import Foundation
import Testing
@testable import NotificationWidgetCore

struct FakeTokenProvider: GoogleAccessTokenProvider {
    var result: Result<String, GoogleAPIError> = .success("token-123")
    func freshAccessToken() async throws -> String { try result.get() }
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var status = 200
    var body = Data("{}".utf8)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}

@Suite("Google authorised client")
struct GoogleClientTests {
    @Test("Adds a fresh bearer token to each request")
    func bearerToken() async throws {
        let transport = FakeTransport()
        let client = GoogleAuthorizedClient(tokenProvider: FakeTokenProvider(), transport: transport)

        _ = try await client.get(URL(string: "https://example.com/x")!)

        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
    }

    @Test("A failed refresh reports needs sign-in")
    func refreshFailure() async {
        let flag = Flag()
        let client = GoogleAuthorizedClient(
            tokenProvider: FakeTokenProvider(result: .failure(.needsSignIn)),
            transport: FakeTransport(),
            onNeedsSignIn: { await flag.set() }
        )

        await #expect(throws: GoogleAPIError.needsSignIn) {
            _ = try await client.get(URL(string: "https://example.com/x")!)
        }
        #expect(await flag.isSet)
    }

    @Test("HTTP 401 reports needs sign-in")
    func unauthorized() async {
        let flag = Flag()
        let transport = FakeTransport()
        transport.status = 401
        let client = GoogleAuthorizedClient(tokenProvider: FakeTokenProvider(), transport: transport, onNeedsSignIn: { await flag.set() })

        await #expect(throws: GoogleAPIError.needsSignIn) {
            _ = try await client.get(URL(string: "https://example.com/x")!)
        }
        #expect(await flag.isSet)
    }

    @Test("Account state after sign-in needs both scopes")
    func accountState() {
        #expect(GoogleAccountState.afterSignIn(email: "me@example.com", grantedScopes: GoogleScope.all)
            == .connected(.google(email: "me@example.com")))
        #expect(GoogleAccountState.afterSignIn(email: "me@example.com", grantedScopes: [GoogleScope.gmailReadOnly])
            == .needsSignIn(.google(email: "me@example.com")))
    }
}
