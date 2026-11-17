import Foundation
import Testing
@testable import NotificationWidgetCore

@MainActor
@Suite("Alert engine")
struct AlertEngineTests {
    let clock = TestClock()

    func makeEngine() -> (AlertEngine, ItemStore) {
        let engine = AlertEngine(clock: { [clock] in clock.now })
        return (engine, ItemStore(persistence: InMemoryDismissalPersistence(), alertEngine: engine, now: referenceNow))
    }

    @Test("A new Item outside Backfill Alerts for its Source")
    func newItemAlerts() {
        let (engine, store) = makeEngine()
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }

        store.replaceItems([email("a")], from: .gmail)

        #expect(alerts.map(\.source) == [.gmail])
        #expect(alerts.first?.items.map(\.id.value) == ["a"])
    }

    @Test("Backfill silence: Backfilled Items never Alert, even on a later snapshot")
    func backfillSilence() {
        let (engine, store) = makeEngine()
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }

        store.replaceItems([email("a"), email("b")], from: .gmail, isBackfill: true)
        clock.advance(60)
        store.replaceItems([email("a"), email("b")], from: .gmail)

        #expect(alerts.isEmpty)
        #expect(engine.highlightedIDs.isEmpty)
    }

    @Test("Coalescing: Alerts for one Source within 10 seconds combine into one")
    func coalescing() {
        let (engine, store) = makeEngine()
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }

        store.replaceItems([email("a")], from: .gmail)
        clock.advance(4)
        store.replaceItems([email("a"), email("b")], from: .gmail)
        clock.advance(5)
        store.replaceItems([email("a"), email("b"), email("c")], from: .gmail)
        // Another Source isn't affected.
        store.replaceItems([dm("x")], from: .slack)

        #expect(alerts.map(\.source) == [.gmail, .slack])
        #expect(engine.highlightedIDs.map(\.value).sorted() == ["a", "b", "c", "x"])

        clock.advance(10)
        store.replaceItems([email("a"), email("b"), email("c"), email("d")], from: .gmail)
        #expect(alerts.map(\.source) == [.gmail, .slack, .gmail])
    }

    @Test("Fire once: an Item that leaves and returns doesn't Alert again")
    func fireOnce() {
        let (engine, store) = makeEngine()
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }

        store.replaceItems([email("a")], from: .gmail)
        clock.advance(60)
        store.replaceItems([], from: .gmail)
        store.replaceItems([email("a")], from: .gmail)

        #expect(alerts.count == 1)
    }

    @Test("Highlight clears when the Item is Dismissed or clicked")
    func highlightClearing() {
        let (engine, store) = makeEngine()
        store.replaceItems([email("a"), email("b")], from: .gmail)
        #expect(engine.isHighlighted(.init(source: .gmail, value: "a")))

        store.dismiss(.init(source: .gmail, value: "a"))
        engine.clearHighlight(.init(source: .gmail, value: "b"))

        #expect(engine.highlightedIDs.isEmpty)
    }

    @Test("Events don't Alert when they arrive, only at their Reminder Time")
    func eventsWaitForReminder() {
        let (engine, store) = makeEngine()
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }
        let standup = event("standup", start: referenceNow.addingTimeInterval(600), end: referenceNow.addingTimeInterval(1500))

        store.replaceItems([standup], from: .googleCalendar)
        #expect(alerts.isEmpty)

        engine.reminderDue([standup])
        engine.reminderDue([standup])
        #expect(alerts.map(\.source) == [.googleCalendar])
        #expect(engine.isHighlighted(standup.id))
    }

    @Test("Dismissed Items don't Alert")
    func dismissedDontAlert() {
        let (engine, store) = makeEngine()
        var alerts: [Alert] = []
        engine.onAlert = { alerts.append($0) }
        store.dismiss(.init(source: .gmail, value: "a"))

        store.replaceItems([email("a")], from: .gmail)

        #expect(alerts.isEmpty)
    }

    @Test("Alerts are published on the stream")
    func stream() async {
        let (engine, store) = makeEngine()
        let stream = engine.alerts()
        store.replaceItems([dm("x")], from: .slack)

        var iterator = stream.makeAsyncIterator()
        let alert = await iterator.next()
        #expect(alert?.source == .slack)
    }
}

@Suite("Alert presentation")
struct AlertPresentationTests {
    let preference = AlertPreference(soundEnabled: true, soundName: "Pop", shakeEnabled: true)

    @Test("Focus off or unknown follows the settings")
    func focusOffOrUnknown() {
        let expected = AlertPresentation(sound: .system("Pop"), shake: true, raisePanel: true)
        #expect(AlertPresentationPolicy.presentation(for: preference, focus: .off) == expected)
        #expect(AlertPresentationPolicy.presentation(for: preference, focus: .unknown) == expected)
    }

    @Test("Focus on: no sound, no shake, no raising")
    func focusOn() {
        #expect(AlertPresentationPolicy.presentation(for: preference, focus: .on) == .silent)
    }

    @Test("Sound and shake toggles apply separately")
    func toggles() {
        let quiet = AlertPreference(soundEnabled: false, soundName: "Pop", shakeEnabled: false)
        #expect(AlertPresentationPolicy.presentation(for: quiet, focus: .off) == AlertPresentation(sound: nil, shake: false, raisePanel: true))
    }

    @Test("Each Alert category has a different default sound")
    func distinctDefaults() {
        let sounds = AlertCategory.allCases.map { AlertPreference.defaults(for: $0).soundName }
        #expect(Set(sounds).count == AlertCategory.allCases.count)
        #expect(sounds.allSatisfy(SystemSounds.names.contains))
    }
}

@Suite("Panel elevation")
struct PanelElevationTests {
    @Test("An Alert raises the Panel, which drops back after 5 seconds")
    func timeout() {
        var elevation = PanelElevation()
        #expect(elevation.level == .desktop)
        elevation.raise(now: referenceNow)
        #expect(elevation.level == .alert)
        elevation.tick(now: referenceNow.addingTimeInterval(4))
        #expect(elevation.level == .alert)
        elevation.tick(now: referenceNow.addingTimeInterval(5))
        #expect(elevation.level == .desktop)
    }

    @Test("It stays up while hovered and drops when the mouse leaves")
    func hover() {
        var elevation = PanelElevation()
        elevation.raise(now: referenceNow)
        elevation.mouseEntered()
        elevation.tick(now: referenceNow.addingTimeInterval(30))
        #expect(elevation.level == .alert)
        elevation.mouseExited(now: referenceNow.addingTimeInterval(31))
        #expect(elevation.level == .desktop)
    }

    @Test("The mouse leaving early also lowers it")
    func earlyLeave() {
        var elevation = PanelElevation()
        elevation.raise(now: referenceNow)
        elevation.mouseEntered()
        elevation.mouseExited(now: referenceNow.addingTimeInterval(1))
        #expect(elevation.level == .desktop)
    }

    @Test("Always on top keeps the floating level, and returns to it after an Alert")
    func alwaysOnTop() {
        var elevation = PanelElevation(alwaysOnTop: true)
        #expect(elevation.level == .floating)
        elevation.raise(now: referenceNow)
        #expect(elevation.level == .alert)
        elevation.tick(now: referenceNow.addingTimeInterval(6))
        #expect(elevation.level == .floating)
    }
}

@MainActor
@Suite("Alert settings")
struct AlertSettingsTests {
    @Test("Alert preferences, Always on top and keywords survive a restart")
    func persistence() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.alertPreference(for: .dm) == .defaults(for: .dm))
        #expect(first.alwaysOnTop == false)
        first.alertPreferences[.email] = AlertPreference(soundEnabled: false, soundName: "Tink", shakeEnabled: false)
        first.alwaysOnTop = true
        first.slackKeywords = ["deploy", " ", "Deploy", "incident"]

        let second = AppSettings(defaults: defaults)
        #expect(second.alertPreference(for: .email) == AlertPreference(soundEnabled: false, soundName: "Tink", shakeEnabled: false))
        #expect(second.alertPreference(for: .dm) == .defaults(for: .dm))
        #expect(second.alwaysOnTop)
        #expect(second.effectiveSlackKeywords == ["deploy", "incident"])
    }
}
