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
//  To replace this with real artwork, see `SpriteSheet.swift` and the README —
//  you should not need to touch this file.
//

import SwiftUI

/// Programmatic pixel art used when no sprite sheet is available.
///
/// All frames are rasterised once at initialisation and cached, so the render path
/// is just a dictionary lookup.
struct PlaceholderSprite: SpriteProvider {

    private let frames: [SpriteState: [Image]]

    init() {
        let stand = Self.render(Poses.stand)
        let blink = Self.render(Poses.blink)
        let runA = Self.render(Poses.runA)
        let runB = Self.render(Poses.runB)
        let jump = Self.render(Poses.jump)
        let shock = Self.render(Poses.shock)

        // Frame counts here must match `SpriteState.animation.frameCount`.
        let running = [runA, stand, runB, stand].compactMap { $0 }

        frames = [
            .idle: [stand, blink].compactMap { $0 },
            .runningRight: running,
            .runningLeft: running,
            .surprised: [shock, stand].compactMap { $0 },
            .jumping: [jump].compactMap { $0 }
        ]
    }

    func image(for state: SpriteState, frame: Int) -> Image? {
        guard let states = frames[state], !states.isEmpty else { return nil }
        // Wrapping rather than trapping: the frame clock and the artwork can briefly
        // disagree on the tick a state changes.
        return states[frame % states.count]
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
/// Every grid is exactly 16 rows of 16 characters. All poses face **right**;
/// ``DesktopSpriteView`` mirrors them horizontally for leftward movement.
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
