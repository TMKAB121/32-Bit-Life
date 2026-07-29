//
//  ScreenGeometry.swift
//  32-Bit Life
//
//  Screen selection and coordinate conversion.
//
//  macOS has two coordinate systems in play here and they disagree about which
//  way is up. Everything that crosses between them goes through this file.
//

import AppKit

/// Helpers for placing the companion window and translating cursor positions
/// into the sprite's coordinate space.
enum ScreenGeometry {

    // MARK: - Screen selection

    /// The screen the companion lives on.
    ///
    /// Deliberately **not** `NSScreen.main`: that property returns the screen with
    /// keyboard focus, which changes every time the user clicks on a different
    /// display. A companion docked to the bottom of the screen should not migrate
    /// when you click somewhere else, so the first entry in `NSScreen.screens` —
    /// the primary display, the one whose origin is `(0, 0)` — is used instead.
    ///
    /// Falls back to `NSScreen.main` on the theory that a wrong screen beats no
    /// screen at all.
    static func hostScreen() -> NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    // MARK: - Window placement

    /// The frame of the companion window, in global (screen) coordinates.
    ///
    /// Anchored to `visibleFrame.minY`, which is the top of the Dock — or the
    /// bottom of the screen when the Dock is hidden or moved to a side. Using
    /// `visibleFrame` rather than `frame` is what makes the sprite sit *on* the
    /// Dock instead of behind it.
    ///
    /// - Note: The Dock can be resized, hidden, or moved at any time. Observe
    ///   `NSApplication.didChangeScreenParametersNotification` and recompute —
    ///   `AppDelegate` does exactly that.
    static func stripFrame(for screen: NSScreen, configuration: SpriteConfiguration) -> CGRect {
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX,
            y: visible.minY + configuration.bottomInset,
            width: visible.width,
            height: configuration.stripHeight
        )
    }

    // MARK: - Coordinate conversion

    /// Converts a global AppKit point into the companion window's SwiftUI coordinates.
    ///
    /// This is the single most error-prone line in the project, so it gets spelled out:
    ///
    /// - **AppKit global coordinates** (what `NSEvent.mouseLocation` returns) have
    ///   their origin at the **bottom-left** of the primary display, with **+Y up**.
    /// - **SwiftUI view coordinates** inside the window have their origin at the
    ///   **top-left** of the window, with **+Y down**.
    ///
    /// So X is a simple translation, but Y must be both translated *and* flipped:
    /// a point at the very top of the window (`global.y == frame.maxY`) must come out
    /// as local `y == 0`.
    ///
    /// - Parameters:
    ///   - point: A point in global AppKit coordinates.
    ///   - frame: The window's frame in global AppKit coordinates.
    /// - Returns: The equivalent point in the window's SwiftUI coordinate space.
    ///   Values outside the window are returned unclamped — negative `y` simply means
    ///   "above the window", which is useful for proximity checks.
    static func globalToLocal(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: point.x - frame.minX,
            y: frame.maxY - point.y
        )
    }

    /// The shortest distance from a point to a rectangle, or `0` if the point is inside it.
    ///
    /// Used for cursor proximity. Measuring to the sprite's *bounding box* rather
    /// than to its centre means the 50-point threshold means the same thing whether
    /// you approach from the side or from above.
    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
