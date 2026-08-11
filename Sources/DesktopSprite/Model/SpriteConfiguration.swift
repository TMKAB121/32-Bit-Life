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
    /// Keep this an integer multiple of the source artwork's pixel grid, or whole
    /// source pixels land on fractional point boundaries and the sprite shimmers as
    /// it moves. 128 is 8× the 16×16 placeholder art and 4× a 32×32 sprite sheet.
    var spriteSize = CGSize(width: 96, height: 96)

    /// Extra headroom above the sprite's resting position, in points.
    ///
    /// The floating window is `spriteSize.height + jumpClearance` tall so that a
    /// jump does not get clipped by the top of the window.
    var jumpClearance: CGFloat = 90

    /// Vertical nudge applied to the whole strip, in points.
    ///
    /// `0` places the sprite's feet exactly on `NSScreen.visibleFrame.minY`, which
    /// is the line directly above the Dock. Positive values lift it higher.
    var bottomInset: CGFloat = 0

    /// Extra headroom reserved for companion effects, in points.
    ///
    /// Effects are drawn relative to the sprite and routinely sit above its head — a
    /// struck block, a puff of dust, a charge glow. The strip is the only canvas there
    /// is, so anything taller than `jumpClearance` allows would simply be clipped off
    /// the top of the window with no other symptom.
    var effectClearance: CGFloat = 40

    /// Horizontal padding kept between the sprite and the edges of the screen.
    var edgeMargin: CGFloat = 12

    // MARK: - Motion

    /// Horizontal running speed, in points per second.
    var runSpeed: CGFloat = 160

    /// Downward acceleration applied while airborne, in points per second squared.
    var gravity: CGFloat = 1400

    /// Upward velocity applied at the start of a jump, in points per second.
    ///
    /// Peak height is roughly `jumpVelocity² / (2 × gravity)`. With the defaults
    /// that is about 45 points, which fits inside `jumpClearance`.
    var jumpVelocity: CGFloat = 450

    // MARK: - Cursor proximity

    /// Distance at which the sprite notices the cursor, in points.
    var proximityEnterDistance: CGFloat = 60

    /// Distance at which the sprite stops paying attention, in points.
    ///
    /// This is deliberately larger than ``proximityEnterDistance``. The gap between
    /// the two is hysteresis: without it, a cursor resting exactly on the threshold
    /// would flip the sprite between `.idle` and `.surprised` on every single tick.
    var proximityExitDistance: CGFloat = 70

    /// Distance at which the sprite is startled into a hop, in points.
    var startleDistance: CGFloat = 3

    // MARK: - Wander behaviour

    /// How long the sprite loiters before picking a new direction, in seconds.
    var idleDurationRange: ClosedRange<TimeInterval> = 1.5...4.5

    /// How long the sprite runs before stopping again, in seconds.
    var runDurationRange: ClosedRange<TimeInterval> = 0.8...2.5

    /// Probability that a wander decision results in running rather than idling.
    var runProbability: Double = 0.6

    // MARK: - Flourishes

    /// Probability that a wander decision performs a flourish, when one is off cooldown.
    ///
    /// Checked before the run/idle roll, so this is the share of *all* wander decisions,
    /// not of the leftovers. Keep it low: the per-clip cooldown is the real governor, and
    /// this only decides how eagerly the sprite reaches for whatever is available.
    var flourishProbability: Double = 0.35

    /// Clip played when the sprite is clicked, instead of the usual jump.
    ///
    /// A development affordance. Waiting out a 45-second cooldown to see whether the
    /// anchor on an effect is a few pixels off is a miserable way to draw, so point this
    /// at whatever you are working on and click it as often as you like:
    ///
    /// ```swift
    /// var clickClipID: ClipID? = ClipID("fire")
    /// ```
    ///
    /// Cooldowns are ignored, the cursor does not interrupt it (it is by definition
    /// resting on the sprite when you click), and the clip plays exactly one pass whether
    /// or not it loops. Set back to `nil` to restore the jump.
    var clickClipID: ClipID? = nil

    /// Minimum seconds between any two flourishes, whatever their individual cooldowns.
    ///
    /// Per-clip cooldowns stop one animation repeating; this stops six *different*
    /// animations coming off cooldown together and firing back to back, which reads as
    /// the sprite having a fit rather than a personality.
    var flourishSpacing: TimeInterval = 12.0

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
    ///
    /// Used for the default sheet and as the fallback for any sheet the manifest does not
    /// give an explicit size. Frame *counts* are not declared anywhere — they are read
    /// from the artwork. See ``SpriteSheetLibrary``.
    var spriteSheetFrameSize = CGSize(width: 32, height: 32)

    /// Name of the JSON animation manifest to look for in the app bundle.
    ///
    /// Optional. Without it the app animates from the built-in five-clip defaults; with
    /// it, clips, sheets, flourishes and companion effects are all data. See `README.md`.
    var animationManifestName = "Animations"

    // MARK: - Derived values

    /// Total height of the floating window.
    var stripHeight: CGFloat { spriteSize.height + jumpClearance + effectClearance }

    /// How many points one source pixel occupies on screen.
    ///
    /// The conversion factor between artwork space and screen space, and the reason
    /// companion-effect anchors are authored in source pixels: an anchor of "ten pixels
    /// to the right" keeps meaning the same thing when ``spriteSize`` changes.
    var pointsPerSourcePixel: CGFloat { spriteSize.width / max(spriteSheetFrameSize.width, 1) }

    static let `default` = SpriteConfiguration()
}
