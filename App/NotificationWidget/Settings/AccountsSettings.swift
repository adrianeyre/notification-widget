import NotificationWidgetCore
import SwiftUI

/// Settings → Accounts: one card per Account, each with its status, one primary action,
/// and a Setup section for the OAuth client (open until it's filled in).
struct AccountsSettingsView: View {
    let google: GoogleAccountController
    let slack: SlackAccountController
    let services: ServiceConfiguration

    var body: some View {
        Form {
            Section {
                GoogleAccountCard(google: google, services: services)
            }
            Section {
                SlackAccountCard(slack: slack, services: services)
            }
        }
        .formStyle(.grouped)
    }
}

private enum DocsLink {
    static let base = "https://github.com/adrianeyre/notification-widget/blob/main/docs/setup/"
    static let google = URL(string: base + "google-oauth-client.md")!
    static let slack = URL(string: base + "slack-app.md")!
}

// MARK: - Shared parts

/// A status in its own colour: green connected, red needs attention, grey otherwise.
private struct StatusBadge: View {
    enum Tone { case success, danger, neutral }

    let text: String
    let tone: Tone

    private var color: Color {
        switch tone {
        case .success: .green
        case .danger: .red
        case .neutral: .secondary
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

/// The card's first row: the Account, who it is, its status and its one action.
private struct AccountHeader<Actions: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    let status: StatusBadge
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    status
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            actions()
        }
        .padding(.vertical, 2)
    }
}

/// "Setup" with a quiet state on the right, opening to the client fields.
private struct SetupGroup<Content: View>: View {
    let isComplete: Bool
    let incompleteText: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Setup").font(.system(size: 13))
                Spacer()
                if isExpanded {
                    EmptyView()
                } else if isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(incompleteText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A labelled field on a fixed label column, so the fields line up.
private struct SetupField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var secure = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Group {
                if secure {
                    SecureField(label, text: $text, prompt: Text(prompt))
                } else {
                    TextField(label, text: $text, prompt: Text(prompt))
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
        }
    }
}

private struct InlineError: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Google

private struct GoogleAccountCard: View {
    let google: GoogleAccountController
    let services: ServiceConfiguration
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var setupError: String?
    @State private var isSetupExpanded = false

    var body: some View {
        AccountHeader(title: "Google", symbol: "calendar", subtitle: subtitle, status: status) {
            switch google.state {
            case .notConfigured:
                EmptyView()
            case .disconnected:
                Button("Connect") { google.connect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(google.isWorking)
            case .connected:
                Button("Disconnect") { google.disconnect() }
                    .disabled(google.isWorking)
            case .needsSignIn:
                HStack(spacing: 8) {
                    Button("Disconnect") { google.disconnect() }
                    Button("Sign in") { google.connect() }
                        .buttonStyle(.borderedProminent)
                }
                .disabled(google.isWorking)
            }
        }
        if google.isWorking, !google.state.isConnected {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        InlineError(message: google.lastError)

        SetupGroup(isComplete: services.isGoogleConfigured, incompleteText: "Needed to connect", isExpanded: $isSetupExpanded) {
            Text("A Google Cloud OAuth client of type Desktop app, with the Calendar and Gmail APIs enabled.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SetupField(label: "Client ID", prompt: "…apps.googleusercontent.com", text: $clientID)
            SetupField(label: "Client secret", prompt: services.hasGoogleClientSecret ? "Saved. Leave blank to keep it" : "GOCSPX-…",
                       text: $clientSecret, secure: true)
            InlineError(message: setupError)
            HStack {
                Link("How to create the client", destination: DocsLink.google)
                    .font(.system(size: 12))
                Spacer()
                if services.isGoogleConfigured {
                    Button("Clear") {
                        services.clearGoogle()
                        clientID = ""
                        clientSecret = ""
                        google.configurationChanged()
                    }
                }
                Button("Save") { save() }
                    .disabled(clientID.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            clientID = services.googleClientID
            isSetupExpanded = !services.isGoogleConfigured
        }
    }

    private func save() {
        do {
            try services.saveGoogle(clientID: clientID, clientSecret: clientSecret)
            clientSecret = ""
            setupError = nil
            google.configurationChanged()
            isSetupExpanded = false
        } catch let error as ConfigurationError {
            setupError = error.message
        } catch {
            setupError = "Couldn't save to the Keychain: \(error.localizedDescription)"
        }
    }

    private var subtitle: String {
        switch google.state {
        case .notConfigured, .disconnected: "Calendar and Gmail"
        case .connected(let account): account.displayName
        case .needsSignIn(let account): account?.displayName ?? "Calendar and Gmail"
        }
    }

    private var status: StatusBadge {
        switch google.state {
        case .notConfigured: StatusBadge(text: "Not set up", tone: .neutral)
        case .disconnected: StatusBadge(text: "Not connected", tone: .neutral)
        case .connected: StatusBadge(text: "Connected", tone: .success)
        case .needsSignIn: StatusBadge(text: "Needs sign-in", tone: .danger)
        }
    }
}

// MARK: - Slack

/// Slack: the app-level token (always pasted), then Sign in with Slack or a pasted user
/// token (SRC-1a, SRC-8). Both are checked with Slack before they're saved.
private struct SlackAccountCard: View {
    let slack: SlackAccountController
    let services: ServiceConfiguration
    @State private var appToken = ""
    @State private var userToken = ""
    @State private var isSaving = false
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var setupError: String?
    @State private var isSetupExpanded = false

    private var isConnected: Bool {
        if case .connected = slack.state { return true }
        return false
    }

    var body: some View {
        AccountHeader(title: "Slack", symbol: "number", subtitle: subtitle, status: status) {
            switch slack.state {
            case .connected, .needsSignIn:
                Button("Disconnect") {
                    appToken = ""
                    userToken = ""
                    slack.disconnect()
                }
            case .checking:
                ProgressView().controlSize(.small)
            case .disconnected:
                EmptyView()
            }
        }

        if !isConnected {
            VStack(alignment: .leading, spacing: 10) {
                SetupField(label: "App-level token", prompt: "xapp-…", text: $appToken, secure: true)
                if slack.oauthConfiguration != nil {
                    HStack {
                        Spacer()
                        Button("Sign in with Slack…") {
                            Task { await slack.signInWithSlack(appToken: appToken) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appToken.isEmpty || slack.isSigningIn)
                    }
                    if slack.isSigningIn {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Finish signing in in your browser…").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                SetupField(label: "User token", prompt: slack.oauthConfiguration == nil ? "xoxp-…" : "xoxp-… (or sign in above)",
                           text: $userToken, secure: true)
                HStack {
                    Link("How to get the tokens", destination: DocsLink.slack)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Save") {
                        isSaving = true
                        Task {
                            await slack.save(userToken: userToken, appToken: appToken)
                            isSaving = false
                            if isConnected {
                                appToken = ""
                                userToken = ""
                            }
                        }
                    }
                    .disabled(userToken.isEmpty || appToken.isEmpty || isSaving)
                }
            }
            .padding(.vertical, 2)
        }
        InlineError(message: slack.lastError)

        SetupGroup(isComplete: services.slackClient != nil, incompleteText: "Optional", isExpanded: $isSetupExpanded) {
            Text("For Sign in with Slack instead of pasting the user token: the Slack app's client ID and secret, from Basic Information → App Credentials.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SetupField(label: "Client ID", prompt: "1234567890.1234567890123", text: $clientID)
            SetupField(label: "Client secret", prompt: services.hasSlackClientSecret ? "Saved. Leave blank to keep it" : "Client secret",
                       text: $clientSecret, secure: true)
            InlineError(message: setupError)
            HStack {
                Link("How to set up Sign in with Slack", destination: DocsLink.slack)
                    .font(.system(size: 12))
                Spacer()
                if services.slackClient != nil {
                    Button("Clear") {
                        services.clearSlack()
                        clientID = ""
                        clientSecret = ""
                    }
                }
                Button("Save") { save() }
                    .disabled(clientID.isEmpty)
            }
        }
        .onAppear { clientID = services.slackClientID }
    }

    private func save() {
        do {
            try services.saveSlack(clientID: clientID, clientSecret: clientSecret)
            clientSecret = ""
            setupError = nil
            isSetupExpanded = false
        } catch let error as ConfigurationError {
            setupError = error.message
        } catch {
            setupError = "Couldn't save to the Keychain: \(error.localizedDescription)"
        }
    }

    private var subtitle: String {
        switch slack.state {
        case .connected(let identity): "\(identity.userName) in \(identity.teamName)"
        default: "DMs and Mentions"
        }
    }

    private var status: StatusBadge {
        switch slack.state {
        case .disconnected: StatusBadge(text: "Not connected", tone: .neutral)
        case .checking: StatusBadge(text: "Checking…", tone: .neutral)
        case .connected: StatusBadge(text: "Connected", tone: .success)
        case .needsSignIn: StatusBadge(text: "Needs new tokens", tone: .danger)
        }
    }
}
