import AppKit
import NotificationWidgetCore
import SwiftUI

/// The borderless, non-activating window that holds the Panel (ADR 0001, PNL-1).
final class WidgetPanel: NSPanel {
    /// Just above the desktop icons: behind every normal app window, visible on the desktop (PNL-2).
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    static func windowLevel(for level: PanelLevel) -> NSWindow.Level {
        switch level {
        case .desktop: desktopLevel
        case .floating: .floating
        // Above everything, including full-screen apps, while an Alert shows (ALR-3).
        case .alert: .statusBar
        }
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Set before `level`: changing `isFloatingPanel` resets the level.
        isFloatingPanel = false
        level = Self.desktopLevel
        // On every Space (including full-screen ones, so Alerts can show over them),
        // and left in place by Mission Control and Cmd-Tab.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        // Nothing in the Panel takes typing, so a click or drag on it must not take keyboard
        // focus from the app being used: the Panel only becomes key if a view asks for it.
        becomesKeyOnlyIfNeeded = true
        // Leave the Panel out of screen sharing and screenshots (PNL-6).
        sharingType = .none
    }

    // Can become key only if a view needs the keyboard (`becomesKeyOnlyIfNeeded`); hover and
    // clicks work without it, and the app never becomes active.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A hosting view that handles the first click, so a click on an Item opens it straight away.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Clicks never need the Panel to be key, so they leave keyboard focus with the app in front.
    override var needsPanelToBecomeKey: Bool { false }
}

/// Owns the Panel window: creates it, shows or hides it, and remembers where it was left (PNL-4).
@MainActor
final class PanelController {
    /// Three columns of `PanelView.columnWidth` plus dividers and padding. Short enough to
    /// fit a 1920×360 strip display (with its menu bar), tall enough for 5 Items and "+N more".
    static let size = CGSize(width: 3 * PanelView.columnWidth + 2 * 29 + 28, height: 320)
    private static let placementKey = "panelPlacement"

    private let model: AppModel
    private var panel: WidgetPanel?
    private var observers: [NSObjectProtocol] = []
    private var elevation = PanelElevation()
    private var elevationTimer: Timer?
    private var isAnimating = false

    init(model: AppModel) {
        self.model = model
    }

    func setVisible(_ visible: Bool) {
        if visible {
            let panel = self.panel ?? makePanel()
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    // MARK: - Levels and Alerts

    /// Allow screen capture (PNL-7): `.readOnly` shows the Panel in screenshots and shares;
    /// `.none` (the default) hides it (PNL-6).
    func setScreenCaptureAllowed(_ allowed: Bool) {
        panel?.sharingType = allowed ? .readOnly : .none
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        elevation.alwaysOnTop = alwaysOnTop
        applyLevel()
    }

    /// Brings the Panel above every window without taking focus, shakes it if asked,
    /// then lets it drop back after ~5 seconds or when the mouse leaves (ALR-3).
    func presentAlert(shake: Bool) {
        guard let panel else { return }
        elevation.raise(now: Date())
        applyLevel()
        panel.orderFrontRegardless()
        if shake {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                pulse(panel)
            } else {
                self.shake(panel)
            }
        }
        elevationTimer?.invalidate()
        elevationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateElevation() }
        }
    }

    private func updateElevation() {
        elevation.tick(now: Date())
        applyLevel()
        if !elevation.isRaised {
            elevationTimer?.invalidate()
            elevationTimer = nil
        }
    }

    func hoverChanged(_ isHovering: Bool) {
        if isHovering {
            elevation.mouseEntered()
        } else {
            elevation.mouseExited(now: Date())
        }
        applyLevel()
    }

    private func applyLevel() {
        guard let panel else { return }
        let level = WidgetPanel.windowLevel(for: elevation.level)
        if panel.level != level { panel.level = level }
    }

    private func shake(_ panel: WidgetPanel) {
        guard !isAnimating else { return }
        isAnimating = true
        let origin = panel.frame.origin
        let offsets: [CGFloat] = [-12, 12, -10, 10, -6, 6, -3, 3, 0]
        for (index, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045 * Double(index)) { [weak self] in
                MainActor.assumeIsolated {
                    panel.setFrameOrigin(NSPoint(x: origin.x + offset, y: origin.y))
                    if index == offsets.count - 1 { self?.isAnimating = false }
                }
            }
        }
    }

    /// Reduce Motion: a subtle fade instead of a shake.
    private func pulse(_ panel: WidgetPanel) {
        guard !isAnimating else { return }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0.55
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.35
                    panel.animator().alphaValue = 1
                }, completionHandler: {
                    MainActor.assumeIsolated { self?.isAnimating = false }
                })
            }
        })
    }

    // MARK: - Window

    private func makePanel() -> WidgetPanel {
        let panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: Self.size))
        let view = FirstClickHostingView(rootView: PanelView(model: model))
        view.sizingOptions = []
        panel.contentView = view
        panel.setFrameOrigin(restoredOrigin())
        self.panel = panel
        setAlwaysOnTop(model.settings.alwaysOnTop)
        setScreenCaptureAllowed(model.settings.allowScreenCapture)
        #if DEBUG
        snapshotIfRequested(view)
        #endif

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            // Don't save the in-between positions of a shake.
            MainActor.assumeIsolated { if self?.isAnimating == false { self?.savePlacement() } }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            // A screen was added or removed: put the Panel back where it belongs, or on the main screen.
            MainActor.assumeIsolated { self?.panel?.setFrameOrigin(self?.restoredOrigin() ?? .zero) }
        })

        return panel
    }

    #if DEBUG
    /// `-SnapshotDir /path` writes PNGs of the Panel (light and dark) and each Settings
    /// tab, for the README and docs. The Panel itself is hidden from screenshots (PNL-6),
    /// so this renders the views in-process instead.
    private func snapshotIfRequested(_ view: NSView) {
        guard let directory = UserDefaults.standard.string(forKey: "SnapshotDir") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                DebugSnapshots.write(model: self.model, to: URL(fileURLWithPath: directory))
            }
        }
    }
    #endif

    private func restoredOrigin() -> CGPoint {
        let screens = NSScreen.screens.compactMap(\.info)
        let main = (NSScreen.main ?? NSScreen.screens.first)?.info
            ?? ScreenInfo(id: 0, visibleFrame: CGRect(origin: .zero, size: CGSize(width: 1440, height: 900)))
        return PanelPlacement.origin(for: Self.size, saved: savedPlacement(), screens: screens, mainScreen: main)
    }

    private func savedPlacement() -> SavedPanelPlacement? {
        guard let data = UserDefaults.standard.data(forKey: Self.placementKey) else { return nil }
        return try? JSONDecoder().decode(SavedPanelPlacement.self, from: data)
    }

    private func savePlacement() {
        guard let panel, let screen = panel.screen?.info else { return }
        let placement = PanelPlacement.save(frame: panel.frame, on: screen)
        if let data = try? JSONEncoder().encode(placement) {
            UserDefaults.standard.set(data, forKey: Self.placementKey)
        }
    }
}

private extension NSScreen {
    var info: ScreenInfo? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return ScreenInfo(id: number.uint32Value, visibleFrame: visibleFrame)
    }
}
