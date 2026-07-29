//
//  SpriteViewModel.swift
//  32-Bit Life
//
//  The brain: one tick loop driving physics, the wander AI, the animation state
//  machine, cursor reactions, and the window's click-through state.
//
//  Everything here runs on the main actor. There is no concurrency in this app
//  beyond the run-loop timer, and keeping it that way is intentional.
//

import AppKit
import Combine
import os
import SwiftUI

// MARK: - Host

/// What the view model needs from the window layer.
///
/// Declaring this as a protocol keeps `SpriteViewModel` free of any `NSWindow`
/// reference, so it can be driven by a SwiftUI preview or a test harness.
@MainActor
protocol SpriteHost: AnyObject {

    /// The companion window's frame in global AppKit coordinates.
    var stripFrame: CGRect { get }

    /// Sets whether mouse events pass straight through the window to whatever is
    /// underneath.
    ///
    /// - Parameter enabled: `true` to let clicks through (the normal state),
    ///   `false` while the cursor is over the sprite and clicks should be captured.
    func setClickThrough(_ enabled: Bool)
}

// MARK: - View model

/// Owns the sprite's position, state, and animation frame.
@MainActor
final class SpriteViewModel: ObservableObject {

    private static let logger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "SpriteViewModel")

    // MARK: Published state

    /// The current animation state.
    @Published private(set) var state: SpriteState = .idle

    /// The frame index within the current state's animation.
    @Published private(set) var frameIndex: Int = 0

    /// The centre of the sprite, in the window's SwiftUI coordinate space.
    @Published private(set) var spriteCenter: CGPoint = .zero

    /// Which way the sprite is looking. Drives the horizontal mirror in the view.
    @Published private(set) var facing: SpriteFacing = .right

    // MARK: Collaborators

    let configuration: SpriteConfiguration
    private let actionRegistry: SpriteActionRegistry
    private let mouseTracker: MouseTracker
    weak var host: SpriteHost?

    // MARK: Physics and behaviour

    /// Horizontal position of the sprite's centre, in local points.
    private var positionX: CGFloat = 0

    /// Height of the sprite's feet above the ground line, in points. Never negative.
    private var altitude: CGFloat = 0

    /// Vertical velocity, in points per second. Positive is upward.
    private var verticalVelocity: CGFloat = 0

    /// Seconds spent in the current state, used to enforce `minimumDuration`.
    private var stateElapsed: TimeInterval = 0

    /// Accumulated time towards the next animation frame.
    private var frameAccumulator: TimeInterval = 0

    /// Seconds until the wander AI makes its next decision.
    private var wanderCountdown: TimeInterval = 0

    /// Seconds spent idle and away from the cursor, used to decide when to throttle.
    private var dormantElapsed: TimeInterval = 0

    /// Whether the sprite has already been startled by the current cursor approach.
    private var hasStartled = false

    /// Last value pushed to the host, so `setClickThrough` is only called on change.
    private var lastClickThrough: Bool?

    // MARK: Timer

    private var timer: Timer?
    private var currentInterval: TimeInterval?
    private var lastTickDate: Date?
    private var isPaused = false

    /// The strip size in local points, cached from the host.
    private var stripSize: CGSize = .zero

    // MARK: - Init

    init(configuration: SpriteConfiguration, actionRegistry: SpriteActionRegistry) {
        self.configuration = configuration
        self.actionRegistry = actionRegistry
        self.mouseTracker = MouseTracker(configuration: configuration)
        self.wanderCountdown = TimeInterval.random(in: configuration.idleDurationRange)
    }

    // MARK: - Lifecycle

    /// Starts the tick loop.
    func start() {
        guard timer == nil else { return }
        isPaused = false
        lastTickDate = Date()
        schedule(interval: configuration.activeTickInterval)
    }

    /// Stops the tick loop entirely.
    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = nil
        lastTickDate = nil
    }

    /// Suspends animation without tearing down state, e.g. while the display sleeps.
    ///
    /// There is no point animating a sprite nobody can see, and on a laptop it is
    /// the difference between a background app that costs battery and one that does not.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        stop()
        mouseTracker.reset()
        Self.logger.debug("Paused.")
    }

    /// Resumes after ``pause()``.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        dormantElapsed = 0
        start()
        Self.logger.debug("Resumed.")
    }

    /// Informs the view model of the window's current size.
    ///
    /// Called on launch and again whenever the screen configuration changes, so the
    /// sprite stays inside the visible area after a resolution or Dock change.
    func updateStripSize(_ size: CGSize) {
        let isFirstLayout = stripSize == .zero
        stripSize = size

        if isFirstLayout {
            positionX = size.width / 2
        }
        positionX = clampedX(positionX)
        refreshPublishedPosition()
    }

    // MARK: - Interaction

    /// Handles a click on the sprite.
    ///
    /// Plays a bounce and fires the registry's default action.
    func handleTap() {
        Self.logger.debug("Sprite tapped.")
        beginJump()
        actionRegistry.performDefaultAction()
    }

    // MARK: - Tick loop

    private func schedule(interval: TimeInterval) {
        guard currentInterval != interval else { return }
        timer?.invalidate()
        currentInterval = interval

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // The timer is attached to the main run loop, so this closure always runs
            // on the main thread; `assumeIsolated` tells the compiler what is already
            // true at runtime rather than hopping actors on every frame.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // `.common` keeps the sprite animating while a menu is open or a window is
        // being dragged, which `.default` would stall.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        // Measure the real elapsed time rather than trusting the timer interval.
        // Timers drift, and the interval changes when the app throttles; clamping
        // guards against a huge delta after a stall producing a physics explosion.
        let delta = min(now.timeIntervalSince(lastTickDate ?? now), 0.1)
        lastTickDate = now
        guard delta > 0, stripSize != .zero else { return }

        stateElapsed += delta

        let proximity = sampleCursor()
        updateClickThrough(isOverSprite: proximity.isOverSprite)
        reactToCursor(proximity)
        updateWander(delta: delta, proximity: proximity)
        updatePhysics(delta: delta, proximity: proximity)
        advanceFrame(delta: delta)
        refreshPublishedPosition()
        updateTickRate(delta: delta, proximity: proximity)
    }

    // MARK: Tick stages

    private func sampleCursor() -> MouseProximity {
        guard let host else {
            return MouseProximity(location: .zero, distance: .greatestFiniteMagnitude, isNear: false, isOverSprite: false)
        }
        return mouseTracker.sample(spriteRect: spriteRect, stripFrame: host.stripFrame)
    }

    /// Flips the window between click-through and click-capturing.
    ///
    /// This is the whole reason a full-width transparent strip is usable at all.
    /// The window covers the entire bottom of the screen; if it accepted mouse events
    /// it would swallow every click on the desktop and on the bottom edge of other
    /// windows. So it ignores them by default and only captures while the cursor is
    /// actually over the sprite's bounding box — a few dozen square points.
    private func updateClickThrough(isOverSprite: Bool) {
        let clickThrough = !isOverSprite
        guard clickThrough != lastClickThrough else { return }
        lastClickThrough = clickThrough
        host?.setClickThrough(clickThrough)
    }

    private func reactToCursor(_ proximity: MouseProximity) {
        guard proximity.isNear else {
            // Re-arm the startle once the cursor has properly gone away.
            hasStartled = false
            // Settle back down. This is not optional: `.surprised` disallows
            // wandering, so if nothing here returned the sprite to `.idle` it would
            // stay startled forever once the cursor left.
            if state == .surprised {
                transition(to: .idle)
            }
            return
        }

        // A very close cursor startles the sprite into a hop — but only once per
        // approach. Without the latch it would hop over and over for as long as the
        // cursor hovered, which is exhausting to look at.
        if !hasStartled, !isAirborne, proximity.distance < configuration.startleDistance {
            hasStartled = true
            beginJump()
            return
        }

        transition(to: .surprised)
    }

    private func updateWander(delta: TimeInterval, proximity: MouseProximity) {
        // Reactions take priority over strolling around.
        guard state.allowsWandering, !proximity.isNear, !isAirborne else { return }

        wanderCountdown -= delta
        guard wanderCountdown <= 0 else { return }

        if state.isRunning || Double.random(in: 0...1) > configuration.runProbability {
            transition(to: .idle)
            wanderCountdown = TimeInterval.random(in: configuration.idleDurationRange)
        } else {
            let direction: SpriteFacing = Bool.random() ? .right : .left
            transition(to: .running(direction))
            wanderCountdown = TimeInterval.random(in: configuration.runDurationRange)
        }
    }

    private func updatePhysics(delta: TimeInterval, proximity: MouseProximity) {
        // Vertical.
        if isAirborne {
            verticalVelocity -= configuration.gravity * CGFloat(delta)
            altitude += verticalVelocity * CGFloat(delta)
            if altitude <= 0 {
                land(stillNear: proximity.isNear)
            }
        }

        // Horizontal.
        guard state.isRunning else { return }
        let direction: CGFloat = state == .runningRight ? 1 : -1
        let proposed = positionX + direction * configuration.runSpeed * CGFloat(delta)
        let clamped = clampedX(proposed)
        positionX = clamped

        // Turn around at the edges instead of grinding against them.
        if clamped != proposed {
            transition(to: .running(direction > 0 ? .left : .right), force: true)
            wanderCountdown = TimeInterval.random(in: configuration.runDurationRange)
        }
    }

    private func advanceFrame(delta: TimeInterval) {
        let animation = state.animation
        guard animation.frameCount > 1 else {
            if frameIndex != 0 { frameIndex = 0 }
            frameAccumulator = 0
            return
        }

        frameAccumulator += delta
        var index = frameIndex
        while frameAccumulator >= animation.frameDuration {
            frameAccumulator -= animation.frameDuration
            let next = index + 1
            if next < animation.frameCount {
                index = next
            } else if animation.loops {
                index = 0
            } else {
                // Hold on the last frame.
                index = animation.frameCount - 1
                frameAccumulator = 0
                break
            }
        }
        // Only publish on an actual change. `@Published` fires `objectWillChange` on
        // every assignment, so writing the same value 60 times a second would re-render
        // the view for nothing.
        if index != frameIndex { frameIndex = index }
    }

    /// Drops to a slower tick once the sprite has been idle and alone for a while,
    /// and back to full rate the moment anything happens.
    private func updateTickRate(delta: TimeInterval, proximity: MouseProximity) {
        let isSettled = state == .idle && !proximity.isNear && !isAirborne
        dormantElapsed = isSettled ? dormantElapsed + delta : 0

        let interval = dormantElapsed >= configuration.dormantDelay
            ? configuration.dormantTickInterval
            : configuration.activeTickInterval
        schedule(interval: interval)
    }

    // MARK: - State machine

    /// The single funnel for every state change.
    ///
    /// Routing all transitions through one place is what makes `minimumDuration`
    /// meaningful: a state triggered by a continuously-true condition (cursor
    /// proximity, say) cannot restart its own animation on every tick.
    ///
    /// - Parameter force: Bypasses the minimum-duration check. Used for transitions
    ///   driven by physics or by a direct user action rather than by a sampled condition.
    private func transition(to newState: SpriteState, force: Bool = false) {
        guard newState != state else { return }
        // Airborne is not interruptible — a jump always plays out to its landing.
        guard force || (!isAirborne && stateElapsed >= state.minimumDuration) else { return }

        state = newState
        stateElapsed = 0
        frameIndex = 0
        frameAccumulator = 0
        if let implied = newState.impliedFacing {
            facing = implied
        }
    }

    private func beginJump() {
        guard !isAirborne else { return }
        verticalVelocity = configuration.jumpVelocity
        altitude = 0.001  // Lift off the ground so `isAirborne` becomes true immediately.
        transition(to: .jumping, force: true)
    }

    private func land(stillNear: Bool) {
        altitude = 0
        verticalVelocity = 0
        transition(to: stillNear ? .surprised : .idle, force: true)
    }

    // MARK: - Geometry

    private var isAirborne: Bool { altitude > 0 }

    /// The sprite's bounding box in the window's SwiftUI coordinate space.
    ///
    /// Local Y grows downward, so the sprite's feet sit at `stripSize.height` when
    /// grounded, and subtracting `altitude` moves it *up* the screen.
    var spriteRect: CGRect {
        let size = configuration.spriteSize
        return CGRect(
            x: positionX - size.width / 2,
            y: stripSize.height - altitude - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func clampedX(_ value: CGFloat) -> CGFloat {
        let halfWidth = configuration.spriteSize.width / 2
        let minimum = configuration.edgeMargin + halfWidth
        let maximum = stripSize.width - configuration.edgeMargin - halfWidth
        guard minimum < maximum else { return stripSize.width / 2 }
        return min(max(value, minimum), maximum)
    }

    private func refreshPublishedPosition() {
        let rect = spriteRect
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // See `advanceFrame` — publish only on change to avoid pointless re-renders
        // while the sprite is standing still.
        if center != spriteCenter { spriteCenter = center }
    }
}
