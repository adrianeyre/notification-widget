import AppKit
import Network
import NotificationWidgetCore

/// Starts and stops the Sources as Accounts connect and disconnect, runs their polling
/// loops with backoff, reports their health, and reconnects them (with a Backfill) after
/// network loss and sleep (APP-4, PNL-8).
@MainActor
final class SourceCoordinator {
    private let store: ItemStore
    private let settings: AppSettings
    private let google: GoogleAccountController
    private let slack: SlackAccountController
    private let health: HealthMonitor
    /// Called after every Calendar poll with today's Events, to schedule Reminder Time Alerts.
    private let onEvents: ([Item]) -> Void

    private var googleTasks: [Task<Void, Never>] = []
    private var slackTasks: [Task<Void, Never>] = []
    private var slackSource: SlackSource?

    private let pathMonitor = NWPathMonitor()
    private var lastPathSatisfied = true
    private var wakeObserver: NSObjectProtocol?

    init(
        store: ItemStore,
        settings: AppSettings,
        google: GoogleAccountController,
        slack: SlackAccountController,
        health: HealthMonitor,
        onEvents: @escaping ([Item]) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.google = google
        self.slack = slack
        self.health = health
        self.onEvents = onEvents
    }

    // MARK: - Reconnect triggers

    /// Reconnects every Source after sleep and wake, and when the network comes back.
    func startMonitoringConnectivity(onWake: @escaping @MainActor () -> Void) {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                onWake()
                self?.reconnectAll()
            }
        }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                defer { self.lastPathSatisfied = satisfied }
                if satisfied, !self.lastPathSatisfied { self.reconnectAll() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "NotificationWidget.network"))
    }

    func reconnectAll() {
        reconnect(.googleCalendar)
        reconnect(.slack)
    }

    /// Restarts a Source. Every restart begins with a Backfill.
    func reconnect(_ source: Source) {
        switch source {
        case .gmail, .googleCalendar:
            if case .connected(let account) = google.state {
                startGoogle(accountEmail: account.identifier)
            } else if case .needsSignIn = google.state {
                google.connect()
            }
        case .slack:
            switch slack.state {
            case .connected(let identity): startSlack(identity: identity)
            case .needsSignIn: slack.retry()
            case .disconnected, .checking: break
            }
        }
    }

    // MARK: - Google

    func googleStateChanged(_ state: GoogleAccountState) {
        stopGoogle()
        switch state {
        case .connected(let account):
            startGoogle(accountEmail: account.identifier)
        case .needsSignIn:
            // Keep the last Items; the health indicator shows they need a new sign-in.
            for source in [Source.gmail, .googleCalendar] { health.update(source) { $0.markNeedsSignIn() } }
        case .disconnected, .notConfigured:
            for source in [Source.gmail, .googleCalendar] {
                health.update(source) { $0.markDisconnected() }
                store.clearItems(from: source)
            }
            onEvents([])
        }
    }

    private func startGoogle(accountEmail: String) {
        stopGoogle()
        let google = self.google
        let client = GoogleAuthorizedClient(tokenProvider: google, onNeedsSignIn: { await google.markNeedsSignIn() })
        let now = Date()
        for source in [Source.gmail, .googleCalendar] { health.update(source) { $0.markActive(at: now) } }

        let calendar = CalendarSource(api: GoogleCalendarAPI(client: client), store: store)
        googleTasks.append(pollLoop(.googleCalendar, interval: CalendarSource.pollInterval) { [store, onEvents] in
            try await calendar.refresh()
            onEvents(store.itemsBySource[.googleCalendar] ?? [])
        })

        // A new GmailSource starts with a full query: the Backfill for this (re)connect.
        let gmail = GmailSource(api: GoogleGmailAPI(client: client), store: store, accountEmail: accountEmail)
        let settings = self.settings
        googleTasks.append(pollLoop(.gmail, interval: GmailSource.pollInterval) {
            // Read the query every time, so a change in Settings applies on the next poll.
            try await gmail.refresh(query: settings.effectiveGmailQuery)
        })
    }

    private func stopGoogle() {
        googleTasks.forEach { $0.cancel() }
        googleTasks = []
    }

    // MARK: - Slack

    func slackStateChanged(_ state: SlackAccountController.State) {
        switch state {
        case .connected(let identity):
            startSlack(identity: identity)
        case .needsSignIn:
            stopSlack()
            health.update(.slack) { $0.markNeedsSignIn() }
        case .checking:
            break
        case .disconnected:
            stopSlack()
            health.update(.slack) { $0.markDisconnected() }
            store.clearItems(from: .slack)
        }
    }

    func keywordsChanged() {
        slackSource?.setKeywords(settings.effectiveSlackKeywords)
    }

    private func startSlack(identity: SlackIdentity) {
        stopSlack()
        guard let credentials = slack.credentials else { return }
        let api = LiveSlackWebAPI(credentials: credentials)
        let source = SlackSource(api: api, store: store, identity: identity, keywords: settings.effectiveSlackKeywords)
        slackSource = source
        health.update(.slack) { $0.markActive(at: Date()) }

        let client = SocketModeClient(
            api: api,
            connector: URLSessionWebSocketConnector(),
            onStatus: { [weak self] status in await self?.socketStatusChanged(status, source: source) },
            onMessage: { message in await source.handle(message) }
        )
        slackTasks.append(Task { await client.run() })

        // Read state (LIF-2), best effort every 2 minutes.
        slackTasks.append(pollLoop(.slack, interval: SlackSource.readCheckInterval, recordsSuccess: false) {
            // The first run has no Items yet, so it makes no calls.
            try await source.checkReadState()
        })
    }

    private func socketStatusChanged(_ status: SocketModeStatus, source: SlackSource) {
        guard source === slackSource else { return }
        switch status {
        case .connected:
            health.update(.slack) { $0.setSocket(up: true, at: Date()) }
            // Every (re)connect runs a Backfill, to catch what arrived while the socket was down.
            Task {
                do {
                    try await source.backfill()
                    // Drop anything read elsewhere while the socket was down (LIF-2).
                    try await source.checkReadState()
                } catch SlackAPIError.invalidAuth(let code) {
                    slack.markNeedsSignIn(SlackAPIError.invalidAuth(code).message)
                } catch {
                    log.error("Slack Backfill: \(String(describing: error), privacy: .public)")
                }
            }
        case .connecting:
            break
        case .down:
            health.update(.slack) { $0.setSocket(up: false, at: Date()) }
        case .invalidAuth(let code):
            slack.markNeedsSignIn(SlackAPIError.invalidAuth(code).message)
        }
    }

    private func stopSlack() {
        slackTasks.forEach { $0.cancel() }
        slackTasks = []
        slackSource = nil
    }

    // MARK: - Polling

    /// Runs `refresh` every `interval`. After a failure it retries sooner with backoff
    /// (capped at the poll interval), and the health indicator shows "out of date" once
    /// no update has succeeded for 3 intervals.
    private func pollLoop(
        _ source: Source,
        interval: Duration,
        recordsSuccess: Bool = true,
        refresh: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never> {
        let health = self.health
        let seconds = Double(interval.components.seconds)
        return Task {
            var backoff = Backoff(base: 5, maximum: seconds)
            while !Task.isCancelled {
                let delay: TimeInterval
                do {
                    try await refresh()
                    if recordsSuccess { health.update(source) { $0.recordSuccess(at: Date()) } }
                    backoff.reset()
                    delay = seconds
                } catch is CancellationError {
                    return
                } catch {
                    log.error("\(source.displayName, privacy: .public) refresh: \(String(describing: error), privacy: .public)")
                    delay = backoff.nextDelay()
                }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }
}
