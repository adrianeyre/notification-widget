import NotificationWidgetCore
import SwiftUI

/// The Settings window: General, Accounts and Alerts tabs (APP-1, PNL-9).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(settings: model.settings, launchAtLogin: model.launchAtLogin)
            }
            Tab("Accounts", systemImage: "person.crop.circle") {
                AccountsSettingsView(google: model.google, slack: model.slack, services: model.services)
            }
            Tab("Alerts", systemImage: "bell") {
                AlertsSettingsView(settings: model.settings, focus: model.focus)
            }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

/// One Settings tab's content on its own, for the debug screenshots (`-SnapshotDir`).
enum SettingsTabSnapshot: String, CaseIterable {
    case general, accounts, alerts

    @MainActor @ViewBuilder
    func view(model: AppModel) -> some View {
        switch self {
        case .general: GeneralSettingsView(settings: model.settings, launchAtLogin: model.launchAtLogin)
        case .accounts: AccountsSettingsView(google: model.google, slack: model.slack, services: model.services)
        case .alerts: AlertsSettingsView(settings: model.settings, focus: model.focus)
        }
    }
}

fileprivate struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Allow Notification Widget in Login Items.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items…") { launchAtLogin.openLoginItemsSettings() }
                    }
                    .font(.callout)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }

            Section("Panel") {
                Toggle("Always on top", isOn: $settings.alwaysOnTop)
                Text("Keep the Panel above other windows instead of on the desktop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Allow screen capture", isOn: $settings.allowScreenCapture)
                Text("Show the Panel in screenshots and screen sharing. Off keeps it private.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Slack keywords") {
                KeywordListEditor(keywords: $settings.slackKeywords)
                Text("Channel messages containing one of these words appear like Mentions. Whole words, ignoring case.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Gmail") {
                LabeledContent("Email filter") {
                    // Only the query is monospaced, not its label.
                    TextField("Email filter", text: $settings.gmailQuery, prompt: Text(AppSettings.defaultGmailQuery))
                        .font(.body.monospaced())
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("A Gmail search query. Emails matching it appear on the Panel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.gmailQuery = AppSettings.defaultGmailQuery }
                        .disabled(settings.gmailQuery == AppSettings.defaultGmailQuery)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A short editable list of words.
private struct KeywordListEditor: View {
    @Binding var keywords: [String]
    @State private var newKeyword = ""

    var body: some View {
        ForEach(Array(keywords.enumerated()), id: \.offset) { index, keyword in
            HStack {
                Text(keyword)
                Spacer()
                Button {
                    keywords.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(keyword)")
            }
        }
        HStack {
            TextField("Add a keyword", text: $newKeyword)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !keywords.contains(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame }) else { return }
        keywords.append(keyword)
        newKeyword = ""
    }
}

/// Sound, shake and Ignore Focus for each Alert category, with Slack split into DMs and
/// Mentions (ALR-1, ALR-2, ALR-9, ALR-10, ALR-11), Event repeats (ALR-12), and the Focus
/// permission note (ALR-7).
fileprivate struct AlertsSettingsView: View {
    @Bindable var settings: AppSettings
    let focus: FocusMonitor

    var body: some View {
        Form {
            ForEach(AlertCategory.allCases, id: \.self) { category in
                Section(category.displayName) {
                    CategoryAlertControls(settings: settings, category: category)
                    if category == .event {
                        Picker("Repeat when an Event starts", selection: $settings.eventRepeatMinutes) {
                            Text("Off").tag(0)
                            ForEach([1, 2, 3, 5], id: \.self) { Text("Every \($0) min").tag($0) }
                        }
                        Text("Until you click or Dismiss it, for up to 10 minutes after the start.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Focus") {
                if focus.isDenied {
                    Text("Notification Widget can't see your Focus status, so Alerts play sounds and shake even during a Focus. Allow it in System Settings → Privacy & Security → Focus.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if focus.authorization == .notDetermined {
                    HStack {
                        Text("Allow access to your Focus status to silence Alerts while a Focus is on.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow…") { focus.requestPermissionIfNeeded() }
                    }
                } else {
                    Text("While a Focus is on, Alerts make no sound and don't shake, unless Ignore Focus is on. Items still appear and are highlighted.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CategoryAlertControls: View {
    @Bindable var settings: AppSettings
    let category: AlertCategory
    @State private var importError: String?
    /// Bumped after importing, so the picker lists the new file.
    @State private var libraryVersion = 0

    private static let chooseFileTag = "__choose_file__"

    private var preference: Binding<AlertPreference> {
        Binding(
            get: { settings.alertPreference(for: category) },
            set: { settings.alertPreferences[category] = $0 }
        )
    }

    private var soundSelection: Binding<String> {
        Binding(
            get: { preference.wrappedValue.soundName },
            set: { newValue in
                if newValue == Self.chooseFileTag {
                    chooseFile()
                } else {
                    preference.wrappedValue.soundName = newValue
                    // Choosing a sound plays a preview.
                    AlertSound.play(AlertSoundReference(storedValue: newValue))
                }
            }
        )
    }

    var body: some View {
        Toggle("Play a sound", isOn: preference.soundEnabled)
        Picker("Sound", selection: soundSelection) {
            Section("System") {
                ForEach(SystemSounds.names, id: \.self) { Text($0).tag($0) }
            }
            let custom = customSounds
            if !custom.isEmpty {
                Section("Your sounds") {
                    ForEach(custom, id: \.self) { Text($0.displayName).tag($0.storedValue) }
                }
            }
            Divider()
            Text("Choose file…").tag(Self.chooseFileTag)
        }
        .disabled(!preference.wrappedValue.soundEnabled)
        .id(libraryVersion)
        if let importError {
            Text(importError).font(.callout).foregroundStyle(.red)
        }
        Toggle("Shake", isOn: preference.shakeEnabled)
        Toggle("Ignore Focus", isOn: preference.ignoresFocus)
    }

    private var customSounds: [AlertSoundReference] {
        var sounds = AlertSound.library?.importedSounds() ?? []
        // Keep the current choice listed even if its file has gone.
        let current = preference.wrappedValue.sound
        if case .file = current, !sounds.contains(current) { sounds.append(current) }
        return sounds
    }

    /// Picks an AIFF, WAV, MP3 or M4A file and copies it into the app's support folder (ALR-11).
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = CustomSoundLibrary.allowedTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a sound for \(category.displayName)"
        guard panel.runModal() == .OK, let url = panel.url, let library = AlertSound.library else { return }
        do {
            let sound = try library.importSound(from: url)
            importError = nil
            libraryVersion += 1
            preference.wrappedValue.sound = sound
            AlertSound.play(sound)
        } catch {
            importError = "Couldn't use that file: \(error.localizedDescription)"
        }
    }
}
