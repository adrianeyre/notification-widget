#if DEBUG
import AppKit
import NotificationWidgetCore
import SwiftUI

/// Renders the app's views to PNG files for the README and docs (Debug builds only).
@MainActor
enum DebugSnapshots {
    static func write(model: AppModel, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        highlightOneNewDM(model)
        preloadAvatars(model, near: directory)

        for (name, appearance) in [("panel-light", NSAppearance.Name.aqua), ("panel-dark", .darkAqua)] {
            render(PanelView(model: model).frame(width: PanelController.size.width, height: PanelController.size.height),
                   size: PanelController.size, appearance: appearance, background: true,
                   to: directory.appending(path: "\(name).png"))
        }
        for tab in SettingsTabSnapshot.allCases {
            let height: CGFloat = switch tab {
            case .general: 560
            case .accounts: 540
            case .alerts: 1010
            }
            render(tab.view(model: model).frame(width: 520, height: height),
                   size: CGSize(width: 520, height: height), appearance: .aqua, background: false,
                   to: directory.appending(path: "settings-\(tab.rawValue).png"))
        }
        log.notice("Snapshots written to \\(directory.path, privacy: .public)")
    }

    /// A DM that arrives after the Backfill Alerts, so the screenshot shows a highlight.
    private static func highlightOneNewDM(_ model: AppModel) {
        let handler = model.alerts.onAlert
        model.alerts.onAlert = nil
        let fresh = Item(
            id: .init(source: .slack, value: "snapshot-new-dm"), kind: .dm,
            title: "Can you look at the release notes before 3?", detail: "Priya Shah · DM",
            date: Date(), openURL: URL(string: "slack://open"),
            avatarURL: SampleItems.avatarURL("priya-shah")
        )
        let existing = model.store.itemsBySource[.slack] ?? []
        model.store.replaceItems([fresh] + existing, from: .slack)
        model.alerts.onAlert = handler
    }

    /// Loads the sample people's portraits from the repository's `site/public/avatars/`
    /// (the files the website serves), so the shots have photos without a network fetch
    /// and the synchronous render doesn't catch them still loading.
    private static func preloadAvatars(_ model: AppModel, near directory: URL) {
        var folder: URL?
        var candidate = directory.standardizedFileURL
        for _ in 0..<6 {
            let avatars = candidate.appending(path: "site/public/avatars")
            if FileManager.default.fileExists(atPath: avatars.path) { folder = avatars; break }
            candidate.deleteLastPathComponent()
        }
        guard let folder else {
            log.error("Snapshots: site/public/avatars not found above \(directory.path, privacy: .public); using initials")
            return
        }
        for url in model.store.itemsBySource.values.joined().compactMap(\.avatarURL) {
            if let image = NSImage(contentsOf: folder.appending(path: url.lastPathComponent)) {
                AvatarImages.shared.preload(image, for: url)
            }
        }
    }

    /// Draws `view` into a PNG. Panel shots sit on a desktop-like ground so the material shows.
    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, background: Bool, to url: URL) {
        let ground = appearance == .darkAqua ? Color(white: 0.16) : Color(red: 0.86, green: 0.88, blue: 0.92)
        let content = view
            .padding(background ? 24 : 0)
            .background(background ? ground : Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: appearance)
        let padded = background ? CGSize(width: size.width + 48, height: size.height + 48) : size
        host.frame = CGRect(origin: .zero, size: padded)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
