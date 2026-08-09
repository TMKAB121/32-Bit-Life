//
//  PlaceholderSprite.swift
//  32-Bit Life
//
//  Built-in 16×16 pixel art, so the app runs and looks like something the moment
//  you build it — no assets required.
//
//  Six poses are authored below and recombined into the four animation cycles.
//  Running reuses the standing pose as its "passing" frame, which is the classic
//  four-frame walk cycle trick: contact, pass, contact, pass.
//
//  This covers the five behaviour clips and nothing else. Flourishes and companion
//  effects are sheet-only by design — they are described in a manifest that ships
//  alongside artwork, and there is no point hand-authoring fallback poses for animations
//  the user invented. ``SpriteProviderFactory`` prunes any flourish this file cannot draw.
//
//  To replace this with real artwork, see `SpriteSheetLibrary.swift` and the README —
//  you should not need to touch this file.
//

import SwiftUI

/// Programmatic pixel art used when no sprite sheet is available.
///
/// All frames are rasterised once at initialisation and cached, so the render path
/// is just a dictionary lookup.
struct PlaceholderSprite: SpriteProvider {

    private let frames: [ClipID: [Image]]

    init() {
        let stand = Self.render(Poses.stand)
        let blink = Self.render(Poses.blink)
        let runA = Self.render(Poses.runA)
        let runB = Self.render(Poses.runB)
        let jump = Self.render(Poses.jump)
        let shock = Self.render(Poses.shock)

        // Frame counts here must match the fallback table in
        // `AnimationCatalogue.builtInClips` — that table is what the catalogue uses when
        // there is no sheet to derive counts from, which is exactly when this art is in play.
        let running = [runA, stand, runB, stand].compactMap { $0 }

        frames = [
            SpriteState.idle.clipID: [stand, blink].compactMap { $0 },
            SpriteState.runningRight.clipID: running,
            SpriteState.runningLeft.clipID: running,
            SpriteState.surprised.clipID: [shock, stand].compactMap { $0 },
            SpriteState.jumping.clipID: [jump].compactMap { $0 }
        ]
    }

    func image(for clip: ClipID, frame: Int) -> Image? {
        guard let images = frames[clip], !images.isEmpty else { return nil }
        // Wrapping rather than trapping: the frame clock and the artwork can briefly
        // disagree on the tick a clip changes.
        return images[frame % images.count]
    }

    func hasArtwork(for clip: ClipID) -> Bool {
        frames[clip]?.isEmpty == false
    }

    private static func render(_ rows: [String]) -> Image? {
        PixelArt.makeSwiftUIImage(rows: rows)
    }
}

// MARK: - Pose data

/// The character grids.
///
/// Legend: `.` transparent · `K` outline · `S` skin · `R` cap/shirt ·
/// `B` overalls · `Y` hair/shoes · `W` eye highlight.
///
/// Every grid is exactly 16 rows of 16 characters. All poses face **right**. Nothing here
/// is flipped — `runningLeft` reuses the same grids and the built-in clips do not set
/// `mirrors`. Flipping is opt-in per clip in the manifest; see ``AnimationClip/mirrors``.
private enum Poses {

    /// Neutral standing pose.
    static let stand: [String] = [
        "................",
        "....RRRRR.......",
        "...RRRRRRRRR....",
        "...YYYSSKS......",
        "..YSYSSSKSSS....",
        "..YSYYSSSKSSS...",
        "..YYSSSSSSSS....",
        "....SSSSSSS.....",
        "...RRBRRRR......",
        "..RRRBBRRRRR....",
        ".RRRRBBBBRRRR...",
        ".SSRBBYBBYBRSS..",
        ".SSSBBBBBBBSSS..",
        "..SBBBBBBBBBS...",
        "...BBB...BBB....",
        "..YYYY...YYYY..."
    ]

    /// Standing with the eye closed — the second half of the idle cycle.
    static let blink: [String] = [
        "................",
        "....RRRRR.......",
        "...RRRRRRRRR....",
        "...YYYSSSS......",
        "..YSYSSSSSSS....",
        "..YSYYSSSSSSS...",
        "..YYSSSSSSSS....",
        "....SSSSSSS.....",
        "...RRBRRRR......",
        "..RRRBBRRRRR....",
        ".RRRRBBBBRRRR...",
        ".SSRBBYBBYBRSS..",
        ".SSSBBBBBBBSSS..",
        "..SBBBBBBBBBS...",
        "...BBB...BBB....",
        "..YYYY...YYYY..."
    ]

    /// Run contact pose — legs split wide.
    static let runA: [String] = [
        "................",
        "....RRRRR.......",
        "...RRRRRRRRR....",
        "...YYYSSKS......",
        "..YSYSSSKSSS....",
        "..YSYYSSSKSSS...",
        "..YYSSSSSSSS....",
        "....SSSSSSS.....",
        "...RRBRRRR......",
        "..RRRBBRRRRR....",
        ".RRRRBBBBRRRR...",
        ".SSRBBYBBYBRSS..",
        "..SSSBBBBBSSS...",
        "...BBBBBBBB.....",
        "..BB......BB....",
        ".YYY.......YYY.."
    ]

    /// Run pass pose — legs together.
    static let runB: [String] = [
        "................",
        "....RRRRR.......",
        "...RRRRRRRRR....",
        "...YYYSSKS......",
        "..YSYSSSKSSS....",
        "..YSYYSSSKSSS...",
        "..YYSSSSSSSS....",
        "....SSSSSSS.....",
        "...RRBRRRR......",
        "..RRRBBRRRRR....",
        ".RRRRBBBBRRRR...",
        ".SSRBBYBBYBRSS..",
        "..SSSBBBBBSSS...",
        "....BBBBBB......",
        "....BBBBBB......",
        "...YYYYYY......."
    ]

    /// Airborne pose — arms up, legs tucked. Note the whole body sits one row higher.
    static let jump: [String] = [
        "................",
        "....RRRRR.......",
        "...RRRRRRRRR....",
        "...YYYSSKS......",
        "..YSYSSSKSSS....",
        "..YSYYSSSKSSS...",
        "..YYSSSSSSSS....",
        "....SSSSSSS.....",
        ".SS.RRBRRRR.SS..",
        ".SSRRRBBRRRRRSS.",
        "..RRRRBBBBRRRR..",
        "...RBBYBBYBR....",
        "...SBBBBBBBS....",
        "...BBB..BBB.....",
        "..YYY....YYY....",
        "................"
    ]

    /// Startled pose — wide eye, arms flung out, cap popping off.
    static let shock: [String] = [
        "....RRRRR.......",
        "...RRRRRRRRR....",
        "................",
        "...YYYSWKS......",
        "..YSYSSWKSSS....",
        "..YSYYSSSKSSS...",
        "..YYSSSSSSSS....",
        "....SSSSSSS.....",
        "SS..RRBRRRR..SS.",
        ".SSRRRBBRRRRRSS.",
        ".RRRRBBBBRRRR...",
        ".SSRBBYBBYBRSS..",
        ".SSSBBBBBBBSSS..",
        "..SBBBBBBBBBS...",
        "...BBB...BBB....",
        "..YYYY...YYYY..."
    ]
}
