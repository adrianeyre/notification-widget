import Foundation

/// What Alert settings are kept for: each Source, with Slack split into DMs and Mentions (ALR-10).
public enum AlertCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case event = "googleCalendar"
    case dm
    case mention
    case email = "gmail"

    public init(kind: ItemKind) {
        switch kind {
        case .event: self = .event
        case .dm: self = .dm
        case .mention: self = .mention
        case .email: self = .email
        }
    }

    public var displayName: String {
        switch self {
        case .event: "Google Calendar Events"
        case .dm: "Slack DMs"
        case .mention: "Slack Mentions"
        case .email: "Gmail Emails"
        }
    }

    /// The categories an Alert's Items fall into, in priority order (DMs before Mentions).
    public static func categories(of items: [Item]) -> [AlertCategory] {
        let present = Set(items.map { AlertCategory(kind: $0.kind) })
        return allCases.filter(present.contains)
    }
}

/// An Alert sound: a macOS system sound, or a file the user chose (ALR-11).
public enum AlertSoundReference: Equatable, Hashable, Sendable {
    case system(String)
    /// A file name inside the app's custom sounds folder.
    case file(String)

    static let filePrefix = "file:"

    /// Stored as a plain string: a system sound name, or `file:<name>`.
    public init(storedValue: String) {
        if storedValue.hasPrefix(Self.filePrefix) {
            self = .file(String(storedValue.dropFirst(Self.filePrefix.count)))
        } else {
            self = .system(storedValue)
        }
    }

    public var storedValue: String {
        switch self {
        case .system(let name): name
        case .file(let name): Self.filePrefix + name
        }
    }

    public var displayName: String {
        switch self {
        case .system(let name): name
        case .file(let name): (name as NSString).deletingPathExtension
        }
    }
}

/// How Alerts look and sound for one category (ALR-1, ALR-2, ALR-9).
public struct AlertPreference: Codable, Equatable, Sendable {
    public var soundEnabled: Bool
    /// A system sound name such as "Glass", or `file:<name>` for a custom file. See ``sound``.
    public var soundName: String
    public var shakeEnabled: Bool
    /// Alert normally even while a Focus is on (ALR-9). Off by default.
    public var ignoresFocus: Bool

    public init(soundEnabled: Bool = true, soundName: String, shakeEnabled: Bool = true, ignoresFocus: Bool = false) {
        self.soundEnabled = soundEnabled
        self.soundName = soundName
        self.shakeEnabled = shakeEnabled
        self.ignoresFocus = ignoresFocus
    }

    // Settings saved before `ignoresFocus` existed still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        soundName = try container.decode(String.self, forKey: .soundName)
        shakeEnabled = try container.decodeIfPresent(Bool.self, forKey: .shakeEnabled) ?? true
        ignoresFocus = try container.decodeIfPresent(Bool.self, forKey: .ignoresFocus) ?? false
    }

    public var sound: AlertSoundReference {
        get { AlertSoundReference(storedValue: soundName) }
        set { soundName = newValue.storedValue }
    }

    /// Each category has a different default sound.
    public static func defaults(for category: AlertCategory) -> AlertPreference {
        switch category {
        case .dm: AlertPreference(soundName: "Pop")
        case .mention: AlertPreference(soundName: "Tink")
        case .email: AlertPreference(soundName: "Glass")
        case .event: AlertPreference(soundName: "Hero")
        }
    }
}

public enum SystemSounds {
    /// The sounds in /System/Library/Sounds.
    public static let names = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]
}

/// Whether a macOS Focus mode is on, as far as the app can tell (ALR-7).
public enum FocusState: Equatable, Sendable {
    case on
    case off
    /// No permission, or the system didn't say. Alerts behave normally.
    case unknown
}

/// What to do for one Alert.
public struct AlertPresentation: Equatable, Sendable {
    public var sound: AlertSoundReference?
    public var shake: Bool
    /// Bring the Panel to the front briefly (ALR-3).
    public var raisePanel: Bool

    public init(sound: AlertSoundReference?, shake: Bool, raisePanel: Bool) {
        self.sound = sound
        self.shake = shake
        self.raisePanel = raisePanel
    }

    public static let silent = AlertPresentation(sound: nil, shake: false, raisePanel: false)
}

public enum AlertPresentationPolicy {
    /// One category's presentation. While Focus is on there's no sound, shake or raising,
    /// unless the category ignores Focus; Items still appear and are highlighted.
    public static func presentation(for preference: AlertPreference, focus: FocusState) -> AlertPresentation {
        if focus == .on, !preference.ignoresFocus { return .silent }
        return AlertPresentation(
            sound: preference.soundEnabled ? preference.sound : nil,
            shake: preference.shakeEnabled,
            raisePanel: true
        )
    }

    /// An Alert can hold Items of several categories (a Slack Alert with DMs and Mentions).
    /// It plays one sound, from the first category in priority order that has sound on, and
    /// shakes or raises if any category does.
    public static func presentation(
        for categories: [AlertCategory],
        preferences: (AlertCategory) -> AlertPreference,
        focus: FocusState
    ) -> AlertPresentation {
        let each = categories.map { presentation(for: preferences($0), focus: focus) }
        return AlertPresentation(
            sound: each.lazy.compactMap(\.sound).first,
            shake: each.contains { $0.shake },
            raisePanel: each.contains { $0.raisePanel }
        )
    }
}
