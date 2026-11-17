import AppKit
import NotificationWidgetCore
import Observation

/// Connects the Google Account (SRC-1, APP-3) with Google's installed-app OAuth flow:
/// the browser, a loopback redirect and PKCE, using the client entered in
/// Settings → Accounts → Setup. Tokens are kept in the Keychain and refreshed before use,
/// so sign-in is restored at launch without the network.
@MainActor
@Observable
final class GoogleAccountController: GoogleAccessTokenProvider {
    private(set) var state: GoogleAccountState
    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Called whenever ``state`` changes.
    @ObservationIgnored var onStateChange: ((GoogleAccountState) -> Void)?
    @ObservationIgnored private let configuration: ServiceConfiguration
    @ObservationIgnored private let session: GoogleSession

    init(configuration: ServiceConfiguration, store: CredentialStore = KeychainCredentialStore()) {
        self.configuration = configuration
        session = GoogleSession(store: store, client: { await MainActor.run { configuration.googleClient } })
        state = configuration.isGoogleConfigured ? .disconnected : .notConfigured
    }

    /// Restores a saved sign-in from the Keychain.
    func restore() {
        Task {
            if let tokens = await session.current {
                setState(.afterSignIn(email: tokens.email, grantedScopes: tokens.grantedScopes))
            } else {
                setState(configuration.isGoogleConfigured ? .disconnected : .notConfigured)
            }
        }
    }

    /// Call after the client is saved or cleared in Setup.
    func configurationChanged() {
        switch state {
        case .notConfigured where configuration.isGoogleConfigured: setState(.disconnected)
        case .disconnected where !configuration.isGoogleConfigured: setState(.notConfigured)
        default: break
        }
    }

    /// Signs in through the browser, asking for Calendar and Gmail read-only access.
    func connect() {
        guard let client = configuration.googleClient else {
            lastError = "Add the Google client in Setup first."
            return
        }
        isWorking = true
        lastError = nil
        let hint = state.account?.identifier
        Task {
            defer { isWorking = false }
            do {
                let tokens = try await GoogleOAuth.signIn(client: client, loginHint: hint) { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
                try await session.save(tokens)
                setState(.afterSignIn(email: tokens.email, grantedScopes: tokens.grantedScopes))
                if !state.isConnected {
                    lastError = "Allow access to both Calendar and Gmail, then connect again."
                }
                NSApp.activate()
            } catch let error as GoogleOAuthError {
                lastError = error.message
            } catch {
                lastError = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    /// Revokes the app's access (best effort) and forgets the Account.
    func disconnect() {
        isWorking = true
        Task {
            await session.signOut()
            isWorking = false
            lastError = nil
            setState(configuration.isGoogleConfigured ? .disconnected : .notConfigured)
        }
    }

    /// Switches to "needs sign-in", for example after a token was rejected.
    func markNeedsSignIn() {
        guard state != .notConfigured, state != .disconnected else { return }
        setState(.needsSignIn(state.account))
    }

    // MARK: GoogleAccessTokenProvider

    nonisolated func freshAccessToken() async throws -> String {
        do {
            return try await session.freshAccessToken()
        } catch GoogleAPIError.needsSignIn {
            await markNeedsSignIn()
            throw GoogleAPIError.needsSignIn
        }
    }

    private func setState(_ newState: GoogleAccountState) {
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }
}
