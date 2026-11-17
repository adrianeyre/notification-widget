import Foundation
import Observation

/// The user's settings, stored locally in `UserDefaults` so they survive restarts (APP-2).
@MainActor
@Observable
public final class AppSettings {
    public static let defaultGmailQuery = "in:inbox category:primary is:unread"

    enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let gmailQuery = "gmailQuery"
        static let isPanelVisible = "isPanelVisible"
        static let alwaysOnTop = "alwaysOnTop"
        static let slackKeywords = "slackKeywords"
        static let alertPreferences = "alertPreferences"
        static let allowScreenCapture = "allowScreenCapture"
        static let eventRepeatMinutes = "eventRepeatMinutes"
    }

    /// The default gap between repeat Alerts for an Event that has started (ALR-12).
    public static let defaultEventRepeatMinutes = 2

    /// Start the app at login (APP-1). On by default.
    public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// The Gmail search query that decides which Emails appear (SRC-4).
    public var gmailQuery: String {
        didSet { defaults.set(gmailQuery, forKey: Key.gmailQuery) }
    }

    /// Whether the Panel is shown (PNL-9).
    public var isPanelVisible: Bool {
        didSet { defaults.set(isPanelVisible, forKey: Key.isPanelVisible) }
    }

    /// Keep the Panel above other windows instead of at desktop level (PNL-3).
    public var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    /// Words that turn a Slack channel message into an Item (SRC-7).
    public var slackKeywords: [String] {
        didSet { defaults.set(slackKeywords, forKey: Key.slackKeywords) }
    }

    /// Sound, shake and Focus settings for each Alert category: Events, DMs, Mentions
    /// and Emails (ALR-1, ALR-2, ALR-9, ALR-10).
    public var alertPreferences: [AlertCategory: AlertPreference] {
        didSet {
            let encoded = Dictionary(uniqueKeysWithValues: alertPreferences.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(encoded) {
                defaults.set(data, forKey: Key.alertPreferences)
            }
        }
    }

    public func alertPreference(for category: AlertCategory) -> AlertPreference {
        alertPreferences[category] ?? .defaults(for: category)
    }

    /// Let the Panel appear in screenshots and screen sharing (PNL-7). Off by default.
    public var allowScreenCapture: Bool {
        didSet { defaults.set(allowScreenCapture, forKey: Key.allowScreenCapture) }
    }

    /// Minutes between repeat Alerts for an Event that has started; 0 is off (ALR-12).
    public var eventRepeatMinutes: Int {
        didSet { defaults.set(eventRepeatMinutes, forKey: Key.eventRepeatMinutes) }
    }

    /// The keyword list with blanks and duplicates removed.
    public var effectiveSlackKeywords: [String] {
        var seen = Set<String>()
        return slackKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The Gmail query to use: the saved one, or the default if it's blank.
    public var effectiveGmailQuery: String {
        let trimmed = gmailQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultGmailQuery : trimmed
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        gmailQuery = defaults.string(forKey: Key.gmailQuery) ?? Self.defaultGmailQuery
        isPanelVisible = defaults.object(forKey: Key.isPanelVisible) as? Bool ?? true
        alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        slackKeywords = defaults.stringArray(forKey: Key.slackKeywords) ?? []

        allowScreenCapture = defaults.bool(forKey: Key.allowScreenCapture)
        eventRepeatMinutes = defaults.object(forKey: Key.eventRepeatMinutes) as? Int ?? Self.defaultEventRepeatMinutes
        alertPreferences = Self.loadAlertPreferences(defaults.data(forKey: Key.alertPreferences))
    }

    /// Reads saved Alert preferences. Settings saved before DMs and Mentions were split
    /// had one "slack" entry, which now applies to both.
    nonisolated static func loadAlertPreferences(_ data: Data?) -> [AlertCategory: AlertPreference] {
        var decoded: [String: AlertPreference] = [:]
        if let data, let saved = try? JSONDecoder().decode([String: AlertPreference].self, from: data) {
            decoded = saved
        }
        if let slack = decoded["slack"] {
            decoded[AlertCategory.dm.rawValue] = decoded[AlertCategory.dm.rawValue] ?? slack
            decoded[AlertCategory.mention.rawValue] = decoded[AlertCategory.mention.rawValue] ?? slack
        }
        var preferences: [AlertCategory: AlertPreference] = [:]
        for category in AlertCategory.allCases {
            preferences[category] = decoded[category.rawValue] ?? .defaults(for: category)
        }
        return preferences
    }
}
