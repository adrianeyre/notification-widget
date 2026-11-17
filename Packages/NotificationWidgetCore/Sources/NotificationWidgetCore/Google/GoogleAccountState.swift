import Foundation

/// The state of the Google Account, shown in Settings and used by the health indicator (PNL-8).
public enum GoogleAccountState: Equatable, Sendable {
    /// The app has no Google client ID configured, so sign-in can't work.
    case notConfigured
    /// No Google Account is connected.
    case disconnected
    /// Signed in, with every scope the app needs.
    case connected(Account)
    /// A refresh failed, a token was rejected, or a scope is missing: the user must sign in again.
    case needsSignIn(Account?)

    public var account: Account? {
        switch self {
        case .connected(let account): account
        case .needsSignIn(let account): account
        case .notConfigured, .disconnected: nil
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Decides the state after a sign-in or a restored sign-in.
    public static func afterSignIn(email: String?, grantedScopes: [String]) -> GoogleAccountState {
        let account = email.map(Account.google(email:))
        let granted = Set(grantedScopes)
        guard let account, GoogleScope.all.allSatisfy(granted.contains) else {
            return .needsSignIn(account)
        }
        return .connected(account)
    }
}
