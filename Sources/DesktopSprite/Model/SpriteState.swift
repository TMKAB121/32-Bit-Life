//
//  SpriteState.swift
//  32-Bit Life
//
//  The animation state machine: what states exist, how each one animates, and
//  the rules governing when one state is allowed to replace another.
//

import Foundation

// MARK: - Facing

/// Which way the sprite is looking.
///
/// Artwork is authored facing right and mirrored horizontally for `.left`, so a
/// sprite sheet only ever needs one set of directional frames.
enum SpriteFacing {
    case left
    case right
}

// MARK: - State

/// The sprite's behaviour state.
///
/// Each case carries its own transition rules, so adding a new state is a matter of
/// adding a case and filling in the switches below — no changes to the view model's
/// tick loop are required.
///
/// Note what is *not* here any more: how a state animates. Frame counts, rates and
/// looping now live in ``AnimationCatalogue``, keyed by ``clipID`` and ultimately read
/// out of the artwork itself. A state is a behaviour; a clip is a piece of animation;
/// and clips are free to exist that no state ever transitions to.
enum SpriteState: String, CaseIterable {
    case idle
    case runningRight
    case runningLeft
    case surprised
    case jumping

    /// The clip played while in this state.
    ///
    /// Free of charge, because the raw values were already written as clip names. This
    /// is deliberately *not* a switch: a fifth exhaustive switch to maintain would have
    /// undercut the point of moving animation data out of this enum in the first place.
    var clipID: ClipID { ClipID(rawValue) }

    /// The shortest time this state is allowed to stay on screen, in seconds.
    ///
    /// This is what stops a state from being re-entered on every tick. `.surprised`
    /// in particular is triggered by cursor proximity, which can change many times
    /// per second — without a floor here the sprite would visibly stutter.
    var minimumDuration: TimeInterval {
        switch self {
        case .idle:          return 0.10
        case .runningRight,
             .runningLeft:   return 0.25
        case .surprised:     return 0.60
        case .jumping:       return 0.0  // Ends on landing, not on a timer.
        }
    }

    /// The direction this state implies, or `nil` to keep the previous facing.
    ///
    /// `.idle`, `.surprised` and `.jumping` all return `nil`: a sprite that turns to
    /// face right just because it stopped running looks broken.
    var impliedFacing: SpriteFacing? {
        switch self {
        case .runningRight: return .right
        case .runningLeft:  return .left
        case .idle, .surprised, .jumping: return nil
        }
    }

    /// Whether the sprite is travelling horizontally in this state.
    var isRunning: Bool {
        self == .runningRight || self == .runningLeft
    }

    /// Whether autonomous wandering is allowed to run while in this state.
    ///
    /// The wander AI is suppressed during reactions so the sprite does not try to
    /// stroll away mid-startle.
    var allowsWandering: Bool {
        switch self {
        case .idle, .runningRight, .runningLeft: return true
        case .surprised, .jumping: return false
        }
    }

    /// The running state for a given direction.
    static func running(_ facing: SpriteFacing) -> SpriteState {
        facing == .right ? .runningRight : .runningLeft
    }
}
