import AppKit
import Foundation
import NotificationWidgetCore
import Observation

/// Connects the Slack workspace with pasted tokens (SRC-1a), kept in the Keychain (APP-3).
@MainActor
@Observable
final class SlackAccountController {
    enum State: Equatable {
        case disconnected
        case checking
        case connected(SlackIdentity)
        /// The tokens were rejected. The message says why.
        case needsSignIn(String)
    }

    private static let credentialsKey = "slackCredentials"

    private(set) var state: State = .disconnected
    private(set) var lastError: String?
    private(set) var credentials: SlackCredentials?
    private(set) var isSigningIn = false

    /// The Slack OAuth client for Sign in with Slack, from Settings → Accounts → Setup.
    /// `nil` means it isn't set up and the user token must be pasted.
    var oauthConfiguration: SlackOAuthConfiguration? { configuration.slackClient }

    @ObservationIgnored var onStateChange: ((State) -> Void)?
    @ObservationIgnored private let configuration: ServiceConfiguration
    @ObservationIgnored private let store: CredentialStore

    init(configuration: ServiceConfiguration, store: CredentialStore = KeychainCredentialStore()) {
        self.configuration = configuration
        self.store = store
    }

    var identity: SlackIdentity? {
        if case .connected(let identity) = state { return identity }
        return nil
    }

    /// Loads saved tokens and checks them with `auth.test`.
    func restore() {
        guard let saved = store.loadValue(SlackCredentials.self, for: Self.credentialsKey) else {
            setState(.disconnected)
            return
        }
        credentials = saved
        Task { await verify(saved, persist: false) }
    }

    /// Checks the pasted tokens and saves them if Slack accepts them.
    func save(userToken: String, appToken: String) async {
        let candidate = SlackCredentials(userToken: userToken, appToken: appToken)
        if let problem = candidate.formatProblem {
            lastError = problem
            return
        }
        await verify(candidate, persist: true)
    }

    /// Gets the user token through Slack's OAuth page in the browser, redirected back to a
    /// loopback port (SRC-8). The app-level token still has to be pasted: Slack doesn't
    /// issue it through OAuth.
    func signInWithSlack(appToken: String) async {
        guard let configuration = oauthConfiguration else { return }
        let appToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appToken.hasPrefix("xapp-") else {
            lastError = "Paste the app-level token (xapp-…) first. Slack doesn't issue it through sign-in."
            return
        }
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false }
        do {
            let userToken = try await SlackOAuth.signIn(configuration) { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
            await save(userToken: userToken, appToken: appToken)
        } catch let error as SlackOAuthError {
            lastError = error.message
        } catch {
            lastError = "Slack sign-in failed: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        store.delete(Self.credentialsKey)
        credentials = nil
        lastError = nil
        setState(.disconnected)
    }

    /// Called when Slack rejects the tokens while connected, for example after they're revoked.
    func markNeedsSignIn(_ message: String) {
        lastError = message
        setState(.needsSignIn(message))
    }

    /// Re-checks the saved tokens, for the Panel's Reconnect button.
    func retry() {
        guard let credentials else { return }
        Task { await verify(credentials, persist: false) }
    }

    private func verify(_ candidate: SlackCredentials, persist: Bool) async {
        let previous = state
        setState(.checking)
        lastError = nil
        do {
            let identity = try await LiveSlackWebAPI(credentials: candidate).authTest()
            // Check the app-level token too, so a wrong xapp- token is reported here and not later.
            _ = try await LiveSlackWebAPI(credentials: candidate).openSocketModeURL()
            if persist {
                try store.saveValue(candidate, for: Self.credentialsKey)
            }
            credentials = candidate
            setState(.connected(identity))
        } catch let error as SlackAPIError {
            lastError = error.message
            if persist {
                // New tokens were rejected: keep whatever was working before.
                setState(previous == .checking ? .disconnected : previous)
            } else {
                setState(.needsSignIn(error.message))
            }
        } catch let error as URLError {
            lastError = "Can't reach Slack (\(error.localizedDescription)). Retrying…"
            // Offline, for example at login: try again rather than asking for new tokens.
            Task {
                try? await Task.sleep(for: .seconds(30))
                await self.verify(candidate, persist: persist)
            }
        } catch {
            lastError = error.localizedDescription
            setState(.disconnected)
        }
    }

    private func setState(_ newState: State) {
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }
}

