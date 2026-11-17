import CoreGraphics
import Foundation
import Testing
@testable import NotificationWidgetCore

@MainActor
@Suite("App settings")
struct AppSettingsTests {
    @Test("Defaults: Launch at login on, default Gmail query, Panel visible")
    func defaults() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.launchAtLogin)
        #expect(settings.gmailQuery == "in:inbox category:primary is:unread")
        #expect(settings.isPanelVisible)
    }

    @Test("Settings survive a restart")
    func persistence() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.launchAtLogin = false
        first.gmailQuery = "in:inbox is:unread"
        first.isPanelVisible = false

        let second = AppSettings(defaults: defaults)
        #expect(second.launchAtLogin == false)
        #expect(second.gmailQuery == "in:inbox is:unread")
        #expect(second.isPanelVisible == false)
    }

    @Test("A blank Gmail query falls back to the default")
    func blankQuery() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.gmailQuery = "   "
        #expect(settings.effectiveGmailQuery == AppSettings.defaultGmailQuery)
    }
}

@Suite("Panel placement")
struct PanelPlacementTests {
    let main = ScreenInfo(id: 1, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    let external = ScreenInfo(id: 2, visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415))
    let size = CGSize(width: 340, height: 560)

    @Test("A saved placement round-trips on the same screen")
    func roundTrip() {
        let frame = CGRect(origin: CGPoint(x: 2000, y: 600), size: size)
        let saved = PanelPlacement.save(frame: frame, on: external)

        let origin = PanelPlacement.origin(for: size, saved: saved, screens: [main, external], mainScreen: main)

        #expect(origin == frame.origin)
    }

    @Test("If the saved screen is gone, the Panel falls back to the main screen")
    func fallback() {
        let saved = SavedPanelPlacement(screenID: 99, offsetFromTopLeft: CGPoint(x: 10, y: 10))

        let origin = PanelPlacement.origin(for: size, saved: saved, screens: [main], mainScreen: main)

        #expect(main.visibleFrame.contains(CGRect(origin: origin, size: size)))
        #expect(origin == CGPoint(x: 1440 - 340 - 24, y: 875 - 560 - 24))
    }

    @Test("A saved position off the edge is pulled back on screen")
    func clamped() {
        let saved = SavedPanelPlacement(screenID: 1, offsetFromTopLeft: CGPoint(x: 5000, y: -200))

        let origin = PanelPlacement.origin(for: size, saved: saved, screens: [main], mainScreen: main)

        #expect(origin == CGPoint(x: 1440 - 340, y: 875 - 560))
    }
}
