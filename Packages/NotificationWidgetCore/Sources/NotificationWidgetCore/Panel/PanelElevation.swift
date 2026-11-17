import Foundation

/// Which window level the Panel should be at.
public enum PanelLevel: Equatable, Sendable {
    /// Behind app windows, on the desktop (PNL-2).
    case desktop
    /// Above normal windows, permanently (Always on top, PNL-3).
    case floating
    /// Above everything, including full-screen apps, while an Alert is showing (ALR-3).
    case alert
}

/// Tracks when the Panel is raised for an Alert and when it goes back down (ALR-3, PNL-3).
///
/// After an Alert the Panel stays up for ``raiseDuration`` seconds, or until the mouse
/// leaves it if the user moved onto it. It never drops while the mouse is over it.
public struct PanelElevation: Equatable, Sendable {
    public static let raiseDuration: TimeInterval = 5

    public var alwaysOnTop: Bool
    public private(set) var raisedUntil: Date?
    public private(set) var isHovering = false
    private var hoveredSinceRaise = false

    public init(alwaysOnTop: Bool = false) {
        self.alwaysOnTop = alwaysOnTop
    }

    public var isRaised: Bool { raisedUntil != nil }

    public var level: PanelLevel {
        if isRaised { return .alert }
        return alwaysOnTop ? .floating : .desktop
    }

    public mutating func raise(now: Date) {
        raisedUntil = now.addingTimeInterval(Self.raiseDuration)
        hoveredSinceRaise = isHovering
    }

    public mutating func mouseEntered() {
        isHovering = true
        if isRaised { hoveredSinceRaise = true }
    }

    public mutating func mouseExited(now: Date) {
        isHovering = false
        if isRaised, hoveredSinceRaise { lower() }
        tick(now: now)
    }

    public mutating func tick(now: Date) {
        guard let raisedUntil, now >= raisedUntil, !isHovering else { return }
        lower()
    }

    private mutating func lower() {
        raisedUntil = nil
        hoveredSinceRaise = false
    }
}
