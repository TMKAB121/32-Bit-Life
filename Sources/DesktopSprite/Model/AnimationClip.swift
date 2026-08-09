//
//  AnimationClip.swift
//  32-Bit Life
//
//  The animation data model: what a clip is, how clips are described in JSON, and
//  how a manifest is resolved into the catalogue the rest of the app reads.
//
//  This file exists to break a knot. The animation system used to be welded to
//  `SpriteState`: sheet rows were indexed by `SpriteState.allCases` *position* and
//  frame counts came from a hard-coded table on the enum. That made three things
//  impossible — deriving frame counts from the artwork, adding an animation nothing
//  transitions *to*, and referencing a second sheet at all.
//
//  So the two concepts are now separate:
//
//  - `SpriteState` stays the small, code-driven behaviour machine. Unchanged in spirit.
//  - `AnimationClip` is *data*. Rows are named and explicit, frame counts come from
//    the pixels, and a clip needs no Swift code to exist.
//
//  The bridge between them is free: `SpriteState` is `String`-backed with raw values
//  that already read as clip names, so `SpriteState.clipID` is a one-liner and there
//  is no fifth exhaustive switch to maintain.
//

import CoreGraphics
import Foundation
import os

// MARK: - Clip identity

/// The name of an animation clip.
///
/// A string wrapper rather than a bare `String` so that a clip name cannot be passed
/// where a sheet name is wanted, and so the JSON stays readable — clips are referenced
/// by name from the manifest, never by index. That is the whole point: inserting a row
/// no longer renumbers everything beneath it.
struct ClipID: Hashable, RawRepresentable, CustomStringConvertible {

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}

// Decoded from a bare JSON string (`"idle"`) rather than the object Swift would
// synthesise for a `RawRepresentable` *struct* (`{"rawValue": "idle"}`). The
// automatic single-value behaviour only applies to enums, so it is spelled out here.
extension ClipID: Codable {

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Effects

/// When a companion effect is spawned, measured against its parent clip's playback.
///
/// `.onFrame` is the one that matters for impact timing — a block popping on the exact
/// frame the head connects with it. `.afterDelay` exists for effects that should trail
/// the parent by a beat regardless of how many frames it has.
enum EffectTrigger: Equatable {
    case onStart
    case onFrame(Int)
    case afterDelay(TimeInterval)
}

/// A companion animation attached to a parent clip.
///
/// This is the Mario jump-block / Mega Man charge shot mechanism: a second, independently
/// animated sprite that appears at a point relative to the character and plays out its own
/// clip — usually from its own sheet, always with its own frame rate.
struct EffectSpawn {

    /// The clip to play. May live on any sheet, including one the character never uses.
    let clip: ClipID

    /// When, relative to the parent clip, this effect appears.
    let trigger: EffectTrigger

    /// Offset from the centre of the parent sprite's frame, in **source pixels**.
    ///
    /// Source pixels rather than points so the number means the same thing whatever
    /// `spriteSize` is set to — an anchor authored against a 32×32 grid keeps working
    /// when the sprite is scaled from 96pt to 128pt. `+x` is right and `+y` is **down**,
    /// matching how the sheet grid reads, so "six pixels above the head" is `-6`.
    ///
    /// Mirrored horizontally when the sprite faces left, so a muzzle flash stays on the
    /// business end of the character.
    let anchor: CGPoint

    /// Whether the effect tracks the sprite or stays where it was born.
    ///
    /// This single flag is the whole Mario/Mega Man difference: a block stays put while
    /// Mario falls away from it (`false`), while a charge glow rides along with the
    /// character (`true`).
    ///
    /// Ignored once ``velocity`` or ``acceleration`` is non-zero — an effect cannot both
    /// travel under its own steam and stay glued to the sprite, and travelling wins.
    let follows: Bool

    /// Initial speed, in **source pixels per second**.
    ///
    /// Same units and same axes as ``anchor``, so `+y` is down and the x component is
    /// mirrored when the sprite faces left — a shot fired by a left-facing character
    /// travels left without a second entry in the manifest.
    let velocity: CGVector

    /// Change in ``velocity`` per second, in source pixels per second squared.
    ///
    /// This is what separates a flat projectile from a tossed coin: give a coin an upward
    /// velocity and a downward acceleration and it arcs. Mirrored on x like the velocity.
    let acceleration: CGVector

    /// Seconds before the effect disappears, regardless of its animation.
    ///
    /// Optional, and the default depends on what the effect is doing. A non-looping clip
    /// ends when its animation ends. A *looping* clip has no natural end, so one that
    /// stays put plays its loop through exactly once, and one that travels lives until it
    /// leaves the strip. Set this when you want something other than that.
    let lifetime: TimeInterval?

    /// Draw order relative to the sprite, which sits at `0`. Negative draws behind.
    let z: Int

    /// Whether this effect moves under its own steam.
    var travels: Bool {
        velocity != .zero || acceleration != .zero
    }
}

/// Rules governing a clip the sprite performs of its own accord.
struct FlourishRule {

    /// Minimum seconds between two performances of this clip.
    ///
    /// The point of a flourish is that it is a surprise. Without a floor here the wander
    /// AI would roll the same animation every few seconds and it would stop reading as
    /// a personality quirk and start reading as a loop.
    let cooldown: TimeInterval

    /// Relative likelihood of being picked when several clips are off cooldown.
    let weight: Double
}

// MARK: - Clip

/// A single animation: where its frames are, how fast they play, and what it drags
/// along with it.
struct AnimationClip {

    let id: ClipID

    /// Name of the sheet holding this clip's frames.
    let sheet: String

    /// Row within that sheet, counting from the top.
    let row: Int

    /// Number of frames actually drawn.
    ///
    /// Normally derived from the artwork by ``SpriteSheetLibrary`` rather than declared,
    /// which is what lets an animation grow by editing the PNG alone.
    let frameCount: Int

    let framesPerSecond: Double

    /// When `true` the clip wraps; when `false` it holds on its last frame and, for a
    /// flourish, reports itself finished.
    let loops: Bool

    /// Present if the sprite may perform this clip spontaneously.
    let flourish: FlourishRule?

    /// Companion animations spawned while this clip plays.
    let effects: [EffectSpawn]

    /// Seconds each frame is on screen.
    ///
    /// The `max` guard is deliberate: a manifest is authored by hand, and `"fps": 0`
    /// would otherwise divide by zero in a background app nobody is watching.
    var frameDuration: TimeInterval { 1.0 / max(framesPerSecond, 0.001) }

    /// Seconds for one complete pass through the clip.
    var duration: TimeInterval { frameDuration * Double(frameCount) }

    init(
        id: ClipID,
        sheet: String,
        row: Int,
        frameCount: Int,
        framesPerSecond: Double,
        loops: Bool,
        flourish: FlourishRule? = nil,
        effects: [EffectSpawn] = []
    ) {
        self.id = id
        self.sheet = sheet
        self.row = row
        self.frameCount = max(frameCount, 1)
        self.framesPerSecond = framesPerSecond
        self.loops = loops
        self.flourish = flourish
        self.effects = effects
    }
}

// MARK: - Frame-count source

/// What the catalogue needs from the artwork layer to finish resolving a clip.
///
/// Declared here, in the model, so `AnimationCatalogue` never has to import the
/// rendering layer to ask "how many frames are actually drawn in this row?".
/// ``SpriteSheetLibrary`` is the only conformer that ships.
protocol FrameCountSource {

    /// Number of drawn frames in a sheet row, or `nil` if the sheet or the row is absent.
    func frameCount(sheet: String, row: Int) -> Int?
}

// MARK: - Sheets

/// A sprite sheet the catalogue knows about.
struct SheetDescriptor {

    let name: String

    /// Size of one frame within the sheet, in file pixels.
    let frameSize: CGSize

    /// Authoring scale. `2` means the sheet was drawn at twice its nominal resolution.
    ///
    /// Largely cosmetic — the view resizes to `spriteSize` regardless — but it keeps the
    /// intrinsic size of a decoded frame honest.
    let scale: CGFloat
}

// MARK: - Catalogue

/// Every clip the app knows about, resolved and ready to play.
///
/// Built once at launch and handed to the view model and the view. Nothing mutates it
/// afterwards; reloading means rebuilding.
struct AnimationCatalogue {

    static let logger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "AnimationCatalogue")

    private let clips: [ClipID: AnimationClip]

    /// Clips the sprite may perform spontaneously, in a stable order.
    ///
    /// Sorted rather than left in dictionary order: `Dictionary` iteration order varies
    /// between launches, and a weighted random pick that silently reshuffles its input
    /// is the kind of thing that makes "it feels different today" impossible to debug.
    let flourishes: [AnimationClip]

    let sheets: [String: SheetDescriptor]

    init(clips: [ClipID: AnimationClip], sheets: [String: SheetDescriptor]) {
        self.clips = clips
        self.sheets = sheets
        self.flourishes = clips.values
            .filter { $0.flourish != nil }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    subscript(id: ClipID) -> AnimationClip? { clips[id] }

    /// Every clip, in a stable order. Used by the slicer to decide what to cut.
    var allClips: [AnimationClip] {
        clips.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The clip a behaviour state plays.
    func clip(for state: SpriteState) -> AnimationClip? { clips[state.clipID] }

    /// A copy with unplayable flourishes removed.
    ///
    /// Used at launch to drop flourishes the chosen provider has no artwork for — the
    /// placeholder art has poses for the five behaviour states and nothing else, so
    /// without this the sprite would periodically "perform" a red error rectangle.
    func filteringFlourishes(_ isPlayable: (ClipID) -> Bool) -> AnimationCatalogue {
        var kept = clips
        for clip in flourishes where !isPlayable(clip.id) {
            Self.logger.info("Flourish '\(clip.id.rawValue, privacy: .public)' has no artwork; it will not be performed.")
            kept[clip.id] = AnimationClip(
                id: clip.id,
                sheet: clip.sheet,
                row: clip.row,
                frameCount: clip.frameCount,
                framesPerSecond: clip.framesPerSecond,
                loops: clip.loops,
                flourish: nil,
                effects: clip.effects
            )
        }
        return AnimationCatalogue(clips: kept, sheets: sheets)
    }
}

// MARK: - Built-in defaults

extension AnimationCatalogue {

    /// The five behaviour clips, exactly as they were hard-coded on `SpriteState`.
    ///
    /// This is the safety net. A missing manifest, a malformed one, or one that simply
    /// forgets `jumping` must still leave the sprite fully animated — so these are laid
    /// down first and the manifest is overlaid on top, never the other way round.
    ///
    /// The frame counts are fallbacks only: if the sheet can be read, the artwork wins.
    static func builtInClips(sheet: String, frameCounts: FrameCountSource?) -> [ClipID: AnimationClip] {
        let table: [(id: String, row: Int, frames: Int, fps: Double, loops: Bool)] = [
            (id: "idle",         row: 0, frames: 2, fps: 2.5, loops: true),
            (id: "runningRight", row: 1, frames: 4, fps: 10,  loops: true),
            (id: "runningLeft",  row: 2, frames: 4, fps: 10,  loops: true),
            (id: "surprised",    row: 3, frames: 2, fps: 6,   loops: true),
            // Jumping is a single held pose; its duration is governed by physics, not
            // by the frame clock.
            (id: "jumping",      row: 4, frames: 1, fps: 1,   loops: false)
        ]

        var result: [ClipID: AnimationClip] = [:]
        for entry in table {
            let id = ClipID(entry.id)
            result[id] = AnimationClip(
                id: id,
                sheet: sheet,
                row: entry.row,
                frameCount: frameCounts?.frameCount(sheet: sheet, row: entry.row) ?? entry.frames,
                framesPerSecond: entry.fps,
                loops: entry.loops
            )
        }
        return result
    }

    /// The catalogue used when there is no manifest to read.
    static func defaults(configuration: SpriteConfiguration, frameCounts: FrameCountSource?) -> AnimationCatalogue {
        let sheet = SheetDescriptor(
            name: configuration.spriteSheetAssetName,
            frameSize: configuration.spriteSheetFrameSize,
            scale: 1
        )
        return AnimationCatalogue(
            clips: builtInClips(sheet: sheet.name, frameCounts: frameCounts),
            sheets: [sheet.name: sheet]
        )
    }
}

// MARK: - Manifest

/// The JSON shape. See `Animations.json` in the bundle for a worked example.
///
/// Almost every field is optional and every failure is survivable. A manifest is
/// hand-authored alongside artwork, so it *will* be wrong sometimes; the rule that
/// governs this whole file is that a bad clip is dropped and logged while everything
/// around it keeps working. A background app the user can barely see must not crash.
struct AnimationManifest: Decodable {

    struct Sheet: Decodable {
        /// `[width, height]` in file pixels.
        let frameSize: [CGFloat]?
        let scale: CGFloat?
    }

    struct Flourish: Decodable {
        let cooldown: TimeInterval
        let weight: Double?
    }

    /// Written as an object with exactly one key set: `{"onFrame": 3}`, `{"afterDelay": 0.25}`,
    /// or omitted entirely for "on start".
    struct Trigger: Decodable {
        let onFrame: Int?
        let afterDelay: TimeInterval?

        var resolved: EffectTrigger {
            if let onFrame { return .onFrame(max(onFrame, 0)) }
            if let afterDelay { return .afterDelay(max(afterDelay, 0)) }
            return .onStart
        }
    }

    struct Effect: Decodable {
        let clip: ClipID
        let trigger: Trigger?
        /// `[x, y]` in source pixels from the parent frame's centre; `+y` is down.
        let anchor: [CGFloat]?
        /// `[x, y]` in source pixels per second.
        let velocity: [CGFloat]?
        /// `[x, y]` in source pixels per second squared.
        let acceleration: [CGFloat]?
        let lifetime: TimeInterval?
        let follows: Bool?
        let z: Int?
    }

    struct Clip: Decodable {
        let id: ClipID
        let sheet: String?
        let row: Int
        /// Overrides the count derived from the artwork. Rarely needed.
        let frames: Int?
        let fps: Double?
        let loops: Bool?
        let flourish: Flourish?
        let effects: [Effect]?
    }

    let version: Int?
    let sheets: [String: Sheet]?
    let clips: [Clip]
}

// MARK: - Loading

extension AnimationCatalogue {

    /// Reads the manifest from the bundle, or returns `nil` if it is absent or unreadable.
    ///
    /// Split out from ``resolve`` so the sheet list can be known *before* the sheets are
    /// loaded — the frame sizes live in the manifest, and the library needs them to slice
    /// anything at all.
    static func loadManifest(configuration: SpriteConfiguration, bundle: Bundle = .main) -> AnimationManifest? {
        guard let url = bundle.url(forResource: configuration.animationManifestName, withExtension: "json") else {
            // Logged at `info`, not `error`: shipping without a manifest is a supported
            // configuration. It is called out explicitly because a manifest that was
            // added to the folder but not to the Resources build phase looks exactly
            // like "my manifest is being ignored", and this line is how you tell.
            logger.info("No '\(configuration.animationManifestName, privacy: .public).json' in the bundle; using built-in animation defaults.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AnimationManifest.self, from: data)
        } catch {
            logger.error("Could not read '\(configuration.animationManifestName, privacy: .public).json' (\(error.localizedDescription, privacy: .public)); using built-in animation defaults.")
            return nil
        }
    }

    /// The sheets a manifest asks for, falling back to the single configured sheet.
    static func sheetDescriptors(
        manifest: AnimationManifest?,
        configuration: SpriteConfiguration
    ) -> [String: SheetDescriptor] {
        let fallback = SheetDescriptor(
            name: configuration.spriteSheetAssetName,
            frameSize: configuration.spriteSheetFrameSize,
            scale: 1
        )
        guard let declared = manifest?.sheets, !declared.isEmpty else {
            return [fallback.name: fallback]
        }

        var result: [String: SheetDescriptor] = [:]
        for (name, sheet) in declared {
            let size: CGSize
            if let pair = sheet.frameSize, pair.count == 2, pair[0] > 0, pair[1] > 0 {
                size = CGSize(width: pair[0], height: pair[1])
            } else {
                size = configuration.spriteSheetFrameSize
            }
            result[name] = SheetDescriptor(name: name, frameSize: size, scale: max(sheet.scale ?? 1, 1))
        }
        return result
    }

    /// Turns a decoded manifest into a catalogue, deriving frame counts from the artwork.
    ///
    /// The built-in clips are laid down first and the manifest overlays them, so a
    /// manifest can retune `runningRight`'s frame rate without having to redeclare every
    /// behaviour clip — and cannot accidentally delete one by omission.
    static func resolve(
        manifest: AnimationManifest?,
        configuration: SpriteConfiguration,
        sheets: [String: SheetDescriptor],
        frameCounts: FrameCountSource?
    ) -> AnimationCatalogue {
        let defaultSheet = sheets[configuration.spriteSheetAssetName]?.name
            ?? sheets.keys.sorted().first
            ?? configuration.spriteSheetAssetName

        var clips = builtInClips(sheet: defaultSheet, frameCounts: frameCounts)
        guard let manifest else {
            return AnimationCatalogue(clips: clips, sheets: sheets)
        }

        for entry in manifest.clips {
            let sheetName = entry.sheet ?? defaultSheet
            guard sheets[sheetName] != nil else {
                logger.error("Clip '\(entry.id.rawValue, privacy: .public)' names unknown sheet '\(sheetName, privacy: .public)'; skipping it.")
                continue
            }
            guard entry.row >= 0 else {
                logger.error("Clip '\(entry.id.rawValue, privacy: .public)' has negative row \(entry.row); skipping it.")
                continue
            }

            // A `nil` count means the row is off the end of the sheet or the sheet could
            // not be read. An explicit `frames` value overrides the artwork; the built-in
            // fallback covers the case where neither is available.
            let derived = frameCounts?.frameCount(sheet: sheetName, row: entry.row)
            guard let frameCount = entry.frames ?? derived ?? clips[entry.id]?.frameCount else {
                logger.error("Clip '\(entry.id.rawValue, privacy: .public)' points at row \(entry.row) of '\(sheetName, privacy: .public)', which has no drawn frames; skipping it.")
                continue
            }

            let effects: [EffectSpawn] = (entry.effects ?? []).map { effect in
                func pair(_ values: [CGFloat]?) -> CGVector {
                    guard let values, values.count == 2 else { return .zero }
                    return CGVector(dx: values[0], dy: values[1])
                }
                let anchor = pair(effect.anchor)

                return EffectSpawn(
                    clip: effect.clip,
                    trigger: effect.trigger?.resolved ?? .onStart,
                    anchor: CGPoint(x: anchor.dx, y: anchor.dy),
                    // Effects are usually part of the character's own action, so tracking
                    // is the default; pinning is the deliberate special case.
                    follows: effect.follows ?? true,
                    velocity: pair(effect.velocity),
                    acceleration: pair(effect.acceleration),
                    lifetime: effect.lifetime.map { max($0, 0) },
                    z: effect.z ?? 1
                )
            }

            let existing = clips[entry.id]
            let loops = entry.loops ?? existing?.loops ?? true

            var flourish = entry.flourish.map {
                FlourishRule(cooldown: max($0.cooldown, 0), weight: max($0.weight ?? 1, 0))
            }
            // A flourish ends when its animation does — that is the only way the sprite
            // knows to go back to idling. A looping one would hold the sprite hostage
            // until the cursor happened to come near, so the rule is dropped rather than
            // the clip, and the clip stays available as an effect or a state animation.
            if flourish != nil, loops {
                logger.error("Clip '\(entry.id.rawValue, privacy: .public)' is a looping flourish, which would never end; it will not be performed. Set \"loops\": false.")
                flourish = nil
            }

            clips[entry.id] = AnimationClip(
                id: entry.id,
                sheet: sheetName,
                row: entry.row,
                frameCount: frameCount,
                framesPerSecond: entry.fps ?? existing?.framesPerSecond ?? 10,
                loops: loops,
                flourish: flourish,
                effects: effects
            )
        }

        // An effect naming a clip that does not exist would silently never draw, which is
        // a miserable thing to debug from a PNG. Say so once, at load.
        for clip in clips.values {
            for effect in clip.effects where clips[effect.clip] == nil {
                logger.error("Clip '\(clip.id.rawValue, privacy: .public)' spawns unknown effect clip '\(effect.clip.rawValue, privacy: .public)'; it will never appear.")
            }
        }

        return AnimationCatalogue(clips: clips, sheets: sheets)
    }
}

// MARK: - Live effects

/// A companion animation currently on screen.
struct ActiveEffect {

    /// Distinguishes two live instances of the same clip. See ``EffectRender``.
    let id: Int

    let clip: AnimationClip
    let z: Int

    /// Seconds since this effect began playing.
    var elapsed: TimeInterval = 0

    /// Where it sits, in the window's SwiftUI coordinate space.
    ///
    /// For a following effect this is recomputed from the sprite every tick; for a pinned
    /// one it is captured once at spawn and never touched again.
    var position: CGPoint

    let follows: Bool

    /// Offset from the sprite's centre in points, already mirrored for facing.
    let offset: CGSize

    /// Current speed in points per second. Integrated every tick when travelling.
    var velocity: CGSize

    /// Change in ``velocity`` per second, in points per second squared.
    let acceleration: CGSize

    /// Seconds before this effect disappears, or `nil` to let the animation decide.
    let lifetime: TimeInterval?

    /// On-screen size in points. Held here so the off-screen test has something to
    /// measure without going back to the catalogue every tick.
    let size: CGSize

    /// Whether this effect moves independently of the sprite.
    var travels: Bool {
        velocity != .zero || acceleration != .zero
    }

    /// Frame currently showing, clamped to the clip.
    var frameIndex: Int {
        let index = Int(elapsed / clip.frameDuration)
        guard clip.loops else { return min(index, clip.frameCount - 1) }
        return index % clip.frameCount
    }

    /// Whether this effect has run out of time.
    ///
    /// The three cases, in the order they are checked:
    ///
    /// 1. An explicit ``lifetime`` always wins.
    /// 2. A looping clip has no natural end, so it survives this test — something else
    ///    must retire it. A travelling one is retired when it leaves the strip; a
    ///    stationary one is given a lifetime of one loop at spawn, which is why the
    ///    "immortal effect" case cannot arise.
    /// 3. Otherwise the effect lasts exactly as long as its animation.
    var isFinished: Bool {
        if let lifetime { return elapsed >= lifetime }
        if clip.loops { return false }
        return elapsed >= clip.duration
    }
}

/// The slice of an effect the view actually needs.
///
/// Published instead of ``ActiveEffect`` because `elapsed` changes on every single tick
/// while the *rendered* frame does not. Comparing this smaller, `Equatable` form is what
/// keeps the app honouring its "`@Published` writes only on change" rule — otherwise a
/// live effect would re-render the view 60 times a second to show the same pixels.
struct EffectRender: Equatable, Identifiable {

    let id: Int
    let clip: ClipID
    let frame: Int
    let position: CGPoint
    let size: CGSize
    let z: Int
}
