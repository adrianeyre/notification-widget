import CoreGraphics
import Foundation

/// A screen the Panel can be placed on, described without AppKit so the logic can be tested.
public struct ScreenInfo: Equatable, Sendable {
    /// The display's `NSScreenNumber`.
    public var id: UInt32
    /// The screen's visible frame, in global screen coordinates (origin bottom-left).
    public var visibleFrame: CGRect

    public init(id: UInt32, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

/// Where the Panel was last left: the screen and the Panel's top-left corner relative
/// to that screen's visible frame (PNL-4).
public struct SavedPanelPlacement: Codable, Equatable, Sendable {
    public var screenID: UInt32
    /// Offset of the Panel's top-left corner from the screen's visible top-left corner.
    /// `x` grows right, `y` grows down.
    public var offsetFromTopLeft: CGPoint

    public init(screenID: UInt32, offsetFromTopLeft: CGPoint) {
        self.screenID = screenID
        self.offsetFromTopLeft = offsetFromTopLeft
    }
}

public enum PanelPlacement {
    /// The default margin from the top-right corner when there's no saved placement.
    public static let defaultMargin: CGFloat = 24

    /// Records where a Panel with `frame` sits, relative to the screen it's on.
    public static func save(frame: CGRect, on screen: ScreenInfo) -> SavedPanelPlacement {
        SavedPanelPlacement(
            screenID: screen.id,
            offsetFromTopLeft: CGPoint(
                x: frame.minX - screen.visibleFrame.minX,
                y: screen.visibleFrame.maxY - frame.maxY
            )
        )
    }

    /// Works out the Panel's frame origin (bottom-left, global coordinates).
    ///
    /// Uses the saved screen if it's still connected, and falls back to the main
    /// screen if it isn't. The result is clamped so the Panel stays on screen.
    public static func origin(
        for size: CGSize,
        saved: SavedPanelPlacement?,
        screens: [ScreenInfo],
        mainScreen: ScreenInfo
    ) -> CGPoint {
        if let saved, let screen = screens.first(where: { $0.id == saved.screenID }) {
            let frame = screen.visibleFrame
            let origin = CGPoint(
                x: frame.minX + saved.offsetFromTopLeft.x,
                y: frame.maxY - saved.offsetFromTopLeft.y - size.height
            )
            return clamp(origin, size: size, in: frame)
        }

        let frame = mainScreen.visibleFrame
        let origin = CGPoint(
            x: frame.maxX - size.width - defaultMargin,
            y: frame.maxY - size.height - defaultMargin
        )
        return clamp(origin, size: size, in: frame)
    }

    static func clamp(_ origin: CGPoint, size: CGSize, in frame: CGRect) -> CGPoint {
        let x = min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - size.width))
        let y = min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - size.height))
        return CGPoint(x: x, y: y)
    }
}
