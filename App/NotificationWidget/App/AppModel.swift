import AppKit
import NotificationWidgetCore
import Observation
import os

let log = Logger(subsystem: "com.adrianeyre.NotificationWidget", category: "app")

/// Wires the app together: settings, the Item store and Alert engine, the Accounts,
/// the Sources, Source health and the Panel.
@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let alerts = AlertEngine()
    let store: ItemStore
    let health = HealthMonitor()
    /// The Google and Slack OAuth clients, entered in Settings → Accounts → Setup.
    let services = ServiceConfiguration()
    let google: GoogleAccountController
    let slack: SlackAccountController
    let focus = FocusMonitor()
    let launchAtLogin = LaunchAtLogin()

    @ObservationIgnored private lazy var panel = PanelController(model: self)
    @ObservationIgnored private lazy var sources = SourceCoordinator(
        store: store, settings: settings, google: google, slack: slack, health: health,
        onEvents: { [weak self] events in self?.scheduleReminders(for: events) }
    )
    @ObservationIgnored private var reminders = ReminderScheduler()
    @ObservationIgnored private var nudges = EventNudgeScheduler()
    @ObservationIgnored private var clockTimer: Timer?
    @ObservationIgnored private var reminderTimer: Timer?

    init() {
        store = ItemStore(persistence: UserDefaultsDismissalPersistence(), alertEngine: alerts)
        google = GoogleAccountController(configuration: services)
        slack = SlackAccountController(configuration: services)
    }

    /// Launch with `-UseSampleItems YES` to fill the Panel with hard-coded Items instead of real Sources.
    var usesSampleItems: Bool {
        UserDefaults.standard.bool(forKey: "UseSampleItems")
    }

    func start() {
        launchAtLogin.apply(settings.launchAtLogin)
        observeSettings()
        alerts.onAlert = { [weak self] alert in self?.present(alert) }
        focus.requestPermissionIfNeeded()

        // The store's and health monitor's clocks: ended Events leave (LIF-3), Slack Items
        // expire after 24 hours (LIF-2), and health turns "out of date" (PNL-8).
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Reminder Times are checked every few seconds so Event Alerts are on time (ALR-6).
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireDueReminders() }
        }

        if usesSampleItems {
            let items = SampleItems.items()
            for source in Source.allCases {
                store.replaceItems(items.filter { $0.source == source }, from: source, isBackfill: true)
            }
            scheduleReminders(for: items.filter { $0.kind == .event })
        } else {
            google.onStateChange = { [weak self] state in self?.sources.googleStateChanged(state) }
            slack.onStateChange = { [weak self] state in self?.sources.slackStateChanged(state) }
            sources.startMonitoringConnectivity(onWake: { [weak self] in
                // Time has jumped: re-evaluate the clock and Reminder Times straight away.
                self?.tick()
                self?.fireDueReminders()
            })
            google.restore()
            slack.restore()
        }

        panel.setVisible(settings.isPanelVisible)
    }

    // MARK: - Panel actions

    func open(_ item: Item) {
        alerts.clearHighlight(item.id)
        guard let url = item.openURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens a Meet or Zoom link. Zoom links go straight to the Zoom app when it's installed (ITM-4).
    func join(_ item: Item) {
        guard let url = item.event?.joinURL else { return }
        alerts.clearHighlight(item.id)
        if let zoomApp = MeetingLink.zoomAppURL(for: url), NSWorkspace.shared.urlForApplication(toOpen: zoomApp) != nil {
            NSWorkspace.shared.open(zoomApp)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func dismiss(_ item: Item) {
        store.dismiss(item.id)
    }

    func health(for source: Source) -> SourceHealth {
        usesSampleItems ? .connected : health.health(for: source)
    }

    func reconnect(_ source: Source) {
        sources.reconnect(source, interactive: true)
    }

    func panelHoverChanged(_ isHovering: Bool) {
        panel.hoverChanged(isHovering)
    }

    // MARK: - Alerts

    /// Plays the sound and raises and shakes the Panel, as the Source's settings and Focus allow.
    private func present(_ alert: Alert) {
        // A Slack Alert can hold DMs and Mentions, which have separate settings (ALR-10).
        let presentation = AlertPresentationPolicy.presentation(
            for: AlertCategory.categories(of: alert.items),
            preferences: settings.alertPreference(for:),
            focus: focus.currentState()
        )
        log.notice("Alert: \(alert.source.rawValue, privacy: .public), \(alert.items.count) Items, sound \(presentation.sound?.storedValue ?? "none", privacy: .public), shake \(presentation.shake), raise \(presentation.raisePanel)")
        if let sound = presentation.sound {
            AlertSound.play(sound)
        }
        if presentation.raisePanel, settings.isPanelVisible {
            panel.presentAlert(shake: presentation.shake)
        }
    }

    private func scheduleReminders(for events: [Item]) {
        reminders.schedule(events.filter { !store.dismissedIDs.contains($0.id) }, now: Date())
        fireDueReminders()
    }

    private func fireDueReminders() {
        let now = Date()
        let due = reminders.due(now: now).filter { !store.dismissedIDs.contains($0.id) }
        if !due.isEmpty {
            alerts.reminderDue(due)
        }

        // Keep nudging for Events that have started until they're clicked or Dismissed (ALR-12).
        let events = store.itemsBySource[.googleCalendar] ?? []
        let nudge = nudges.due(
            events,
            acknowledged: alerts.acknowledgedIDs.union(store.dismissedIDs),
            intervalMinutes: settings.eventRepeatMinutes,
            now: now
        )
        if !nudge.isEmpty {
            alerts.nudge(nudge)
        }
    }

    private func tick() {
        let now = Date()
        store.tick(now: now)
        health.tick(now: now)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.isPanelVisible
            _ = settings.launchAtLogin
            _ = settings.alwaysOnTop
            _ = settings.slackKeywords
            _ = settings.allowScreenCapture
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.panel.setVisible(self.settings.isPanelVisible)
                self.panel.setAlwaysOnTop(self.settings.alwaysOnTop)
                self.panel.setScreenCaptureAllowed(self.settings.allowScreenCapture)
                self.launchAtLogin.apply(self.settings.launchAtLogin)
                self.sources.keywordsChanged()
                self.observeSettings()
            }
        }
    }
}

enum AlertSound {
    /// Where custom sound files are kept (ALR-11).
    static let library: CustomSoundLibrary? = try? CustomSoundLibrary.standard()

    /// Plays a system sound or a custom file once. A missing file falls back to a system sound.
    static func play(_ sound: AlertSoundReference) {
        let nsSound: NSSound?
        switch sound {
        case .system(let name):
            // A copy, so two Alerts close together don't cut each other off.
            nsSound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound
        case .file:
            nsSound = library?.url(for: sound).flatMap { NSSound(contentsOf: $0, byReference: false) }
                ?? NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound
        }
        nsSound?.play()
    }
}
