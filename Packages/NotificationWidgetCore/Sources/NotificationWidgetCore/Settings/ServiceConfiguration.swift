import Foundation
import Observation

/// The Google and Slack OAuth clients, entered in Settings → Accounts → Setup.
/// Client IDs are kept in preferences; client secrets in the Keychain.
@MainActor
@Observable
public final class ServiceConfiguration {
    enum Key {
        static let googleClientID = "googleClientID"
        static let slackClientID = "slackClientID"
        static let googleClientSecret = "googleClientSecret"
        static let slackClientSecret = "slackClientSecret"
    }

    public private(set) var googleClientID: String
    public private(set) var slackClientID: String
    /// Whether a secret is saved, without holding it in observed state.
    public private(set) var hasGoogleClientSecret: Bool
    public private(set) var hasSlackClientSecret: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secrets: CredentialStore

    public init(defaults: UserDefaults = .standard, secrets: CredentialStore = KeychainCredentialStore()) {
        self.defaults = defaults
        self.secrets = secrets
        googleClientID = defaults.string(forKey: Key.googleClientID) ?? ""
        slackClientID = defaults.string(forKey: Key.slackClientID) ?? ""
        hasGoogleClientSecret = secrets.load(Key.googleClientSecret) != nil
        hasSlackClientSecret = secrets.load(Key.slackClientSecret) != nil
    }

    // MARK: Google

    /// The Google client, once both values are saved.
    public var googleClient: GoogleOAuthClient? {
        guard !googleClientID.isEmpty, let secret = secret(Key.googleClientSecret) else { return nil }
        return GoogleOAuthClient(clientID: googleClientID, clientSecret: secret)
    }

    public var isGoogleConfigured: Bool { !googleClientID.isEmpty && hasGoogleClientSecret }

    /// Saves the Google client. A blank secret keeps the saved one, so the ID can be
    /// edited without retyping it.
    public func saveGoogle(clientID: String, clientSecret: String) throws {
        let candidate = GoogleOAuthClient(clientID: clientID, clientSecret: clientSecret.isEmpty ? (secret(Key.googleClientSecret) ?? "") : clientSecret)
        if let problem = candidate.formatProblem { throw ConfigurationError(message: problem) }
        try secrets.save(Data(candidate.clientSecret.utf8), for: Key.googleClientSecret)
        defaults.set(candidate.clientID, forKey: Key.googleClientID)
        googleClientID = candidate.clientID
        hasGoogleClientSecret = true
    }

    public func clearGoogle() {
        secrets.delete(Key.googleClientSecret)
        defaults.removeObject(forKey: Key.googleClientID)
        googleClientID = ""
        hasGoogleClientSecret = false
    }

    // MARK: Slack

    /// The Slack OAuth client for Sign in with Slack, once both values are saved.
    public var slackClient: SlackOAuthConfiguration? {
        guard !slackClientID.isEmpty, let secret = secret(Key.slackClientSecret) else { return nil }
        return SlackOAuthConfiguration(clientID: slackClientID, clientSecret: secret)
    }

    public func saveSlack(clientID: String, clientSecret: String) throws {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let keptSecret = secret.isEmpty ? (self.secret(Key.slackClientSecret) ?? "") : secret
        guard !id.isEmpty else { throw ConfigurationError(message: "Enter the Slack client ID.") }
        guard !keptSecret.isEmpty else { throw ConfigurationError(message: "Enter the Slack client secret.") }
        try secrets.save(Data(keptSecret.utf8), for: Key.slackClientSecret)
        defaults.set(id, forKey: Key.slackClientID)
        slackClientID = id
        hasSlackClientSecret = true
    }

    public func clearSlack() {
        secrets.delete(Key.slackClientSecret)
        defaults.removeObject(forKey: Key.slackClientID)
        slackClientID = ""
        hasSlackClientSecret = false
    }

    private func secret(_ key: String) -> String? {
        secrets.load(key).map { String(decoding: $0, as: UTF8.self) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct ConfigurationError: Error, Equatable, Sendable {
    public var message: String
}
