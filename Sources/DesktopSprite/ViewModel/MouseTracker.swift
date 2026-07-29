//
//  MouseTracker.swift
//  32-Bit Life
//
//  Cursor proximity, with hysteresis.
//
//  Deliberately has no dependency on NSWindow or on the view model, so proximity
//  logic can be reasoned about (and unit tested) in isolation.
//

import AppKit

/// The result of one cursor sample.
struct MouseProximity {

    /// The cursor position in the strip window's SwiftUI coordinate space.
    let location: CGPoint

    /// Shortest distance from the cursor to the sprite's bounding box, in points.
    /// Zero when the cursor is over the sprite.
    let distance: CGFloat

    /// Whether the sprite should currently be reacting to the cursor.
    ///
    /// This is the *hysteretic* answer, not a raw threshold comparison — see
    /// ``MouseTracker/sample(spriteRect:stripFrame:)``.
    let isNear: Bool

    /// Whether the cursor is directly over the sprite's bounding box.
    let isOverSprite: Bool
}

/// Samples the cursor position and reports how close it is to the sprite.
///
/// ### Why polling rather than an event monitor
///
/// The obvious approach is `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`.
/// It does not work well here: the companion window sets `ignoresMouseEvents = true`
/// for all but a few pixels of the screen, and a *local* monitor therefore sees
/// almost nothing. A *global* monitor would work — global mouse monitors do not
/// require Accessibility permission, only keyboard ones do — but it adds a second
/// asynchronous source of truth and an object whose lifetime must be managed.
///
/// Since the view model already ticks every frame, reading `NSEvent.mouseLocation`
/// there is simpler, synchronous, allocation-free, and always in step with the
/// physics it feeds.
@MainActor
final class MouseTracker {

    private let configuration: SpriteConfiguration

    /// Latched proximity. This is the state the hysteresis is applied to.
    private(set) var isNear = false

    init(configuration: SpriteConfiguration) {
        self.configuration = configuration
    }

    /// Samples the cursor and updates the latched proximity state.
    ///
    /// Proximity uses two thresholds rather than one. The sprite starts reacting when
    /// the cursor comes within `proximityEnterDistance`, and only stops once it has
    /// retreated past the larger `proximityExitDistance`. With a single threshold, a
    /// cursor parked exactly on the boundary — or one jittering by a pixel — would
    /// toggle the reaction on and off on every tick, which reads as a flicker.
    ///
    /// - Parameters:
    ///   - spriteRect: The sprite's bounding box in the window's SwiftUI coordinates.
    ///   - stripFrame: The window frame in global AppKit coordinates.
    func sample(spriteRect: CGRect, stripFrame: CGRect) -> MouseProximity {
        let local = ScreenGeometry.globalToLocal(NSEvent.mouseLocation, in: stripFrame)
        let distance = ScreenGeometry.distance(from: local, to: spriteRect)

        if isNear {
            if distance > configuration.proximityExitDistance { isNear = false }
        } else {
            if distance < configuration.proximityEnterDistance { isNear = true }
        }

        return MouseProximity(
            location: local,
            distance: distance,
            isNear: isNear,
            isOverSprite: spriteRect.contains(local)
        )
    }

    /// Clears the latched state, e.g. when the sprite is hidden or the app sleeps.
    func reset() {
        isNear = false
    }
}
