import Foundation

/// The app's version, shown in Settings → General and the menu bar menu.
///
/// Releases are git tags (`v1.2.0`, made by semantic-release), and the app is built from
/// a clone, so `scripts/stamp-version.sh` writes the version from the latest tag into the
/// built app's Info.plist: `CFBundleShortVersionString`, `CFBundleVersion` (the commit
/// count) and `NWGitDescription` (`git describe`). Without tags it keeps `MARKETING_VERSION`.
public struct AppVersion: Equatable, Sendable {
    /// `1.2.0`.
    public var version: String
    /// The build number: the commit count, or `CURRENT_PROJECT_VERSION`.
    public var build: String
    /// `git describe --tags --dirty` at build time, for example `v1.2.0-3-gabc1234-dirty`.
    public var gitDescription: String?

    public init(version: String, build: String, gitDescription: String? = nil) {
        self.version = version
        self.build = build
        self.gitDescription = gitDescription
    }

    public init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        self.init(
            version: (info["CFBundleShortVersionString"] as? String)?.nilIfBlank ?? "unknown",
            build: (info["CFBundleVersion"] as? String)?.nilIfBlank ?? "",
            gitDescription: (info["NWGitDescription"] as? String)?.nilIfBlank
        )
    }

    public static let current = AppVersion(bundle: .main)

    /// How the build relates to the release it's based on.
    public struct Distance: Equatable, Sendable {
        /// Commits after the release tag.
        public var commits: Int
        /// The abbreviated commit it was built from.
        public var commit: String
        /// Built with uncommitted changes.
        public var isModified: Bool
    }

    /// `nil` for a build exactly at a release tag (or one without git details).
    public var distance: Distance? {
        guard var description = gitDescription else { return nil }
        let isModified = description.hasSuffix("-dirty")
        if isModified { description.removeLast("-dirty".count) }
        // v1.2.0-3-gabc1234: the last two parts are the commit count and hash.
        let parts = description.split(separator: "-")
        if parts.count >= 3, let commits = Int(parts[parts.count - 2]), parts[parts.count - 1].hasPrefix("g") {
            return Distance(commits: commits, commit: String(parts[parts.count - 1].dropFirst()), isModified: isModified)
        }
        return isModified ? Distance(commits: 0, commit: "", isModified: true) : nil
    }

    /// "1.2.0", or "1.2.0 + 3 commits (abc1234)" for a build after the release.
    public var displayVersion: String {
        guard let distance else { return version }
        var parts: [String] = []
        if distance.commits > 0 {
            parts.append("+ \(distance.commits) \(distance.commits == 1 ? "commit" : "commits") (\(distance.commit))")
        }
        if distance.isModified { parts.append("modified") }
        return ([version] + parts).joined(separator: " ")
    }

    /// The GitHub release for this version, or `nil` for the fallback version.
    public var releaseNotesURL: URL? {
        guard version.first?.isNumber == true, version != "0.0.0" else { return nil }
        return URL(string: "https://github.com/adrianeyre/notification-widget/releases/tag/v\(version)")
    }

    /// The menu bar menu's line: "Notification Widget 1.2.0".
    public var menuTitle: String { "Notification Widget \(displayVersion)" }
}
