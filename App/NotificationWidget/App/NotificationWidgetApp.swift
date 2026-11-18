import NotificationWidgetCore
import SwiftUI

@main
struct NotificationWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notification Widget", systemImage: "rectangle.stack") {
            MenuBarMenu(model: appDelegate.model)
        }

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

/// The menu bar menu (PNL-9): the app's version, Show/Hide Panel, Settings…, Quit.
private struct MenuBarMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // A disabled item, as macOS menus show an app's version.
        Text(AppVersion.current.menuTitle)

        Divider()

        Button(model.settings.isPanelVisible ? "Hide Panel" : "Show Panel") {
            model.settings.isPanelVisible.toggle()
        }
        .keyboardShortcut("p")

        Button("Settings…") {
            // A menu bar app isn't active, so bring it forward or Settings opens behind other windows.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Notification Widget") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
