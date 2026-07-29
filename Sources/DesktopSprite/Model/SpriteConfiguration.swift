//
//  SpriteConfiguration.swift
//  32-Bit Life
//
//  Every tunable number in the app lives here. Nothing else should hard-code a
//  speed, a distance, or a frame rate — if you want to change how the companion
//  feels, this is the only file you need to open.
//

import Foundation

/// Tunable parameters for the desktop companion.
///
/// A single value is created in `AppDelegate` and handed to everything that
/// needs it, so there is exactly one source of truth at runtime.
struct SpriteConfiguration {

    // MARK: - Geometry

    /// On-screen size of the sprite, in points.
    ///
    /// The placeholder art is a 16×16 pixel grid, so multiples of 16 keep pixels
    /// perfectly square (64 = 4× scale).
    var spriteSize = CGSize(width: 64, height: 64)

    /// Extra headroom above the sprite's resting position, in points.
    ///
    /// The floating window is `spriteSize.height + jumpClearance` tall so that a
    /// jump does not get clipped by the top of the window.
    var jumpClearance: CGFloat = 48

    /// Vertical nudge applied to the whole strip, in points.
    ///
    /// `0` places the sprite's feet exactly on `NSScreen.visibleFrame.minY`, which
    /// is the line directly above the Dock. Positive values lift it higher.
    var bottomInset: CGFloat = 0

    /// Horizontal padding kept between the sprite and the edges of the screen.
    var edgeMargin: CGFloat = 12

    // MARK: - Motion

    /// Horizontal running speed, in points per second.
    var runSpeed: CGFloat = 90

    /// Downward acceleration applied while airborne, in points per second squared.
    var gravity: CGFloat = 1400

    /// Upward velocity applied at the start of a jump, in points per second.
    ///
    /// Peak height is roughly `jumpVelocity² / (2 × gravity)`. With the defaults
    /// that is about 45 points, which fits inside `jumpClearance`.
    var jumpVelocity: CGFloat = 360

    // MARK: - Cursor proximity

    /// Distance at which the sprite notices the cursor, in points.
    var proximityEnterDistance: CGFloat = 50

    /// Distance at which the sprite stops paying attention, in points.
    ///
    /// This is deliberately larger than ``proximityEnterDistance``. The gap between
    /// the two is hysteresis: without it, a cursor resting exactly on the threshold
    /// would flip the sprite between `.idle` and `.surprised` on every single tick.
    var proximityExitDistance: CGFloat = 80

    /// Distance at which the sprite is startled into a hop, in points.
    var startleDistance: CGFloat = 24

    // MARK: - Wander behaviour

    /// How long the sprite loiters before picking a new direction, in seconds.
    var idleDurationRange: ClosedRange<TimeInterval> = 1.5...4.5

    /// How long the sprite runs before stopping again, in seconds.
    var runDurationRange: ClosedRange<TimeInterval> = 0.8...2.5

    /// Probability that a wander decision results in running rather than idling.
    var runProbability: Double = 0.6

    // MARK: - Tick rates

    /// Tick interval used while the sprite is moving or reacting.
    var activeTickInterval: TimeInterval = 1.0 / 60.0

    /// Tick interval used once the sprite has been idle and alone for a while.
    ///
    /// Dropping to 12 Hz keeps the idle animation alive while cutting the wake-ups
    /// this app costs the CPU by 5×. It matters: this process runs all day.
    var dormantTickInterval: TimeInterval = 1.0 / 12.0

    /// How long the sprite must be idle *and* away from the cursor before the tick
    /// rate is throttled, in seconds.
    var dormantDelay: TimeInterval = 3.0

    // MARK: - Artwork

    /// Name of the sprite-sheet image to look for in the app bundle.
    ///
    /// If an image with this name exists it is used; otherwise the app falls back
    /// to the built-in ``PlaceholderSprite`` pixel art. See `README.md`.
    var spriteSheetAssetName = "SpriteSheet"

    /// Size of a single frame within the sprite sheet, in *pixels*.
    var spriteSheetFrameSize = CGSize(width: 16, height: 16)

    // MARK: - Derived values

    /// Total height of the floating window.
    var stripHeight: CGFloat { spriteSize.height + jumpClearance }

    static let `default` = SpriteConfiguration()
}
