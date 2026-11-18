import Foundation
import Testing
@testable import NotificationWidgetCore

@Suite("App version")
struct AppVersionTests {
    @Test("A build at a release tag shows just the version", arguments: ["v1.2.0", nil] as [String?])
    func atRelease(description: String?) {
        let version = AppVersion(version: "1.2.0", build: "88", gitDescription: description)
        #expect(version.distance == nil)
        #expect(version.displayVersion == "1.2.0")
        #expect(version.menuTitle == "Notification Widget 1.2.0")
        #expect(version.releaseNotesURL?.absoluteString == "https://github.com/adrianeyre/notification-widget/releases/tag/v1.2.0")
    }

    @Test("A build after the release shows how far after, and the commit", arguments: [
        ("v1.2.0-1-gabc1234", "1.2.0 + 1 commit (abc1234)"),
        ("v1.2.0-3-gabc1234", "1.2.0 + 3 commits (abc1234)"),
        ("v1.2.0-3-gabc1234-dirty", "1.2.0 + 3 commits (abc1234) modified"),
        ("v1.2.0-dirty", "1.2.0 modified"),
    ])
    func afterRelease(description: String, expected: String) {
        #expect(AppVersion(version: "1.2.0", build: "91", gitDescription: description).displayVersion == expected)
    }

    @Test("Read from a bundle's Info.plist, with the fallback version linking nowhere")
    func fromBundle() {
        let version = AppVersion(bundle: Bundle(for: BundleToken.self))
        #expect(!version.version.isEmpty)
        #expect(AppVersion(version: "0.0.0", build: "1").releaseNotesURL == nil)
        #expect(AppVersion(version: "unknown", build: "").releaseNotesURL == nil)
    }
}

private final class BundleToken {}
