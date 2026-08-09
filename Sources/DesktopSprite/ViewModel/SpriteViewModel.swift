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

    /// The current behaviour state.
    @Published private(set) var state: SpriteState = .idle

    /// The clip currently being drawn.
    ///
    /// Usually the current state's clip, but a flourish overlays its own animation while
    /// leaving the state alone — the sprite is still, behaviourally, idling.
    @Published private(set) var clipID: ClipID = SpriteState.idle.clipID

    /// The frame index within the current clip.
    @Published private(set) var frameIndex: Int = 0

    /// The centre of the sprite, in the window's SwiftUI coordinate space.
    @Published private(set) var spriteCenter: CGPoint = .zero

    /// Which way the sprite is looking. Mirrors companion-effect anchors.
    @Published private(set) var facing: SpriteFacing = .right

    /// Companion animations currently on screen, in draw order.
    @Published private(set) var effects: [EffectRender] = []

    // MARK: Collaborators

    let configuration: SpriteConfiguration
    let catalogue: AnimationCatalogue
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

    // MARK: Flourishes

    /// Seconds since the tick loop started, accumulated from the per-tick delta.
    ///
    /// Deliberately not `Date`: this process runs for days across sleep, wake, and the
    /// occasional clock correction, any of which would make wall-clock arithmetic jump
    /// and either suppress every flourish or fire them all at once.
    private var clock: TimeInterval = 0

    /// When each flourish was last performed, on the ``clock`` timebase.
    ///
    /// Absent means "never", which reads as `0` below — so a clip's first performance is
    /// gated by its own cooldown after launch rather than firing in the opening seconds.
    private var lastFlourish: [ClipID: TimeInterval] = [:]

    /// When *any* flourish was last performed. See `flourishSpacing`.
    private var lastAnyFlourish: TimeInterval = 0

    /// The clip being performed, or `nil` when the sprite is just being itself.
    private var activeFlourish: AnimationClip?

    /// Seconds into the active flourish.
    private var flourishElapsed: TimeInterval = 0

    /// Effects belonging to the active flourish that have not reached their trigger yet.
    private var pendingSpawns: [EffectSpawn] = []

    // MARK: Effects

    private var activeEffects: [ActiveEffect] = []

    /// Monotonic identifier so SwiftUI can tell two effects of the same clip apart.
    private var nextEffectID = 0

    // MARK: Timer

    private var timer: Timer?
    private var currentInterval: TimeInterval?
    private var lastTickDate: Date?
    private var isPaused = false

    /// The strip size in local points, cached from the host.
    private var stripSize: CGSize = .zero

    // MARK: - Init

    init(
        configuration: SpriteConfiguration,
        catalogue: AnimationCatalogue,
        actionRegistry: SpriteActionRegistry
    ) {
        self.configuration = configuration
        self.catalogue = catalogue
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
        clock += delta

        let proximity = sampleCursor()
        updateClickThrough(isOverSprite: proximity.isOverSprite)
        reactToCursor(proximity)
        updateWander(delta: delta, proximity: proximity)
        updatePhysics(delta: delta, proximity: proximity)
        syncClip()
        advanceFrame(delta: delta)
        // Effects before the flourish that owns them, and the order is load-bearing:
        // `updateFlourish` retires a finished clip and discards anything still pending,
        // so an effect triggered on the clip's *last* frame would be dropped a tick
        // before it ever spawned if these two were the other way round.
        updateEffects(delta: delta)
        updateFlourish(delta: delta)
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
        // Attention beats performance. A flourish is a private moment; the instant the
        // cursor arrives the sprite should notice it, so the clip is abandoned rather
        // than played out. Without this the sprite reads as unresponsive for a second or
        // two at exactly the moment the user is trying to interact with it.
        if proximity.isNear {
            cancelFlourish()
        }

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
        // Reactions take priority over strolling around, and a flourish already in
        // progress owns the sprite until it finishes or is interrupted.
        guard state.allowsWandering, !proximity.isNear, !isAirborne, activeFlourish == nil else { return }

        wanderCountdown -= delta
        guard wanderCountdown <= 0 else { return }

        // Checked before the run/idle roll rather than as a third outcome of it: a
        // flourish only ever starts from a standing start, and folding it into the roll
        // below would mean the sprite could only perform when it happened to be idle
        // *and* happened to lose the run coin-flip.
        if state == .idle, beginFlourishIfDue() {
            wanderCountdown = TimeInterval.random(in: configuration.idleDurationRange)
            return
        }

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

    /// Publishes the clip that should be on screen, resetting the frame clock when it changes.
    ///
    /// A single funnel, for the same reason `transition(to:)` is one: a flourish starting
    /// or ending changes the artwork without changing the state, and two places resetting
    /// the frame clock independently is how you end up with an animation that occasionally
    /// starts halfway through.
    private func syncClip() {
        let resolved = activeFlourish?.id ?? state.clipID
        guard resolved != clipID else { return }
        clipID = resolved
        frameIndex = 0
        frameAccumulator = 0
    }

    private func advanceFrame(delta: TimeInterval) {
        // The catalogue is the authority on frame counts, and it reads them out of the
        // artwork. A clip with no entry means the manifest and the sheet disagree; hold
        // on frame zero rather than dividing by a count of nothing.
        guard let clip = currentClip, clip.frameCount > 1 else {
            if frameIndex != 0 { frameIndex = 0 }
            frameAccumulator = 0
            return
        }

        frameAccumulator += delta
        var index = frameIndex
        while frameAccumulator >= clip.frameDuration {
            frameAccumulator -= clip.frameDuration
            let next = index + 1
            if next < clip.frameCount {
                index = next
            } else if clip.loops {
                index = 0
            } else {
                // Hold on the last frame.
                index = clip.frameCount - 1
                frameAccumulator = 0
                break
            }
        }
        // Only publish on an actual change. `@Published` fires `objectWillChange` on
        // every assignment, so writing the same value 60 times a second would re-render
        // the view for nothing.
        if index != frameIndex { frameIndex = index }
    }

    /// Retires a flourish once its clip has played out.
    ///
    /// Nothing else in the app ends a state when its animation finishes — behaviour
    /// states end on a timer or on landing. This is the one animation-driven ending, and
    /// it is why only non-looping clips are allowed to be flourishes.
    private func updateFlourish(delta: TimeInterval) {
        guard let clip = activeFlourish else { return }
        flourishElapsed += delta
        guard flourishElapsed >= clip.duration else { return }

        activeFlourish = nil
        flourishElapsed = 0
        pendingSpawns = []
        // Effects deliberately survive: a struck block keeps wobbling after the character
        // has finished swinging at it. Only an *interrupted* flourish takes them with it.
        transition(to: .idle, force: true)
    }

    /// Spawns effects that have reached their trigger, advances the live ones, and drops
    /// those that have played out.
    private func updateEffects(delta: TimeInterval) {
        spawnDueEffects()

        guard !activeEffects.isEmpty else {
            if !effects.isEmpty { effects = [] }
            return
        }

        for index in activeEffects.indices {
            activeEffects[index].elapsed += delta

            if activeEffects[index].travels {
                // Semi-implicit integration: velocity is updated before it is used, the
                // same order `updatePhysics` uses for the sprite's own gravity. Mixing the
                // two orders would make an effect and the sprite fall at visibly
                // different rates from the same acceleration.
                let acceleration = activeEffects[index].acceleration
                activeEffects[index].velocity.width += acceleration.width * CGFloat(delta)
                activeEffects[index].velocity.height += acceleration.height * CGFloat(delta)

                let velocity = activeEffects[index].velocity
                activeEffects[index].position.x += velocity.width * CGFloat(delta)
                activeEffects[index].position.y += velocity.height * CGFloat(delta)
            } else if activeEffects[index].follows {
                activeEffects[index].position = effectPosition(offset: activeEffects[index].offset)
            }
        }
        activeEffects.removeAll { effect in
            guard effect.isFinished || hasLeftStrip(effect) else { return false }
            // Only travelling effects are worth a line. A projectile that dies on the
            // frame it is born — because its velocity was in the wrong units, or the
            // strip is shorter than the author assumed — is otherwise invisible.
            if effect.travels {
                Self.logger.debug("Effect '\(effect.clip.id.rawValue, privacy: .public)' retired after \(effect.elapsed, format: .fixed(precision: 2))s at x \(Int(effect.position.x)), y \(Int(effect.position.y)).")
            }
            return true
        }
        refreshPublishedEffects()
    }

    /// Drops to a slower tick once the sprite has been idle and alone for a while,
    /// and back to full rate the moment anything happens.
    private func updateTickRate(delta: TimeInterval, proximity: MouseProximity) {
        // A flourish or a live effect counts as activity even though the sprite is
        // standing still and alone. Throttling to 12 Hz underneath a 10 fps animation
        // would drop roughly every other frame of it.
        let isSettled = state == .idle
            && !proximity.isNear
            && !isAirborne
            && activeFlourish == nil
            && activeEffects.isEmpty
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
        // A jump is either a startle or a click. Both outrank a performance.
        cancelFlourish()
        verticalVelocity = configuration.jumpVelocity
        altitude = 0.001  // Lift off the ground so `isAirborne` becomes true immediately.
        transition(to: .jumping, force: true)
    }

    private func land(stillNear: Bool) {
        altitude = 0
        verticalVelocity = 0
        transition(to: stillNear ? .surprised : .idle, force: true)
    }

    // MARK: - Flourishes

    /// The clip driving the frame clock: a performance if one is running, otherwise the
    /// state's own animation.
    private var currentClip: AnimationClip? {
        activeFlourish ?? catalogue.clip(for: state)
    }

    /// Rolls for a flourish and starts one if the dice and the cooldowns allow.
    ///
    /// Three gates, narrowest first, because the cheap ones should reject most calls:
    /// the global spacing, the probability roll, then the per-clip cooldowns.
    ///
    /// - Returns: `true` if a flourish began.
    private func beginFlourishIfDue() -> Bool {
        guard !catalogue.flourishes.isEmpty else { return false }
        guard clock - lastAnyFlourish >= configuration.flourishSpacing else { return false }
        guard Double.random(in: 0...1) < configuration.flourishProbability else { return false }

        let eligible = catalogue.flourishes.filter { clip in
            guard let rule = clip.flourish else { return false }
            return clock - (lastFlourish[clip.id] ?? 0) >= rule.cooldown
        }
        guard let chosen = weightedChoice(from: eligible) else { return false }

        activeFlourish = chosen
        flourishElapsed = 0
        pendingSpawns = chosen.effects
        lastFlourish[chosen.id] = clock
        lastAnyFlourish = clock
        Self.logger.debug("Performing flourish '\(chosen.id.rawValue, privacy: .public)'.")
        return true
    }

    /// Abandons the active flourish and the decoration attached to it.
    ///
    /// Attached effects go with it: a charge glow left hanging in the air after the sprite
    /// has been startled away from it is worse than no effect at all.
    ///
    /// Effects already *travelling* are kept. Once a projectile has left the character it
    /// is its own object, and yanking it out of the air because the user happened to move
    /// the cursor looks like a rendering glitch rather than a reaction.
    private func cancelFlourish() {
        guard activeFlourish != nil else { return }
        activeFlourish = nil
        flourishElapsed = 0
        pendingSpawns = []
        activeEffects.removeAll { !$0.travels }
    }

    private func weightedChoice(from clips: [AnimationClip]) -> AnimationClip? {
        let total = clips.reduce(0.0) { $0 + ($1.flourish?.weight ?? 0) }
        guard total > 0 else { return nil }

        var roll = Double.random(in: 0..<total)
        for clip in clips {
            roll -= clip.flourish?.weight ?? 0
            if roll < 0 { return clip }
        }
        return clips.last
    }

    // MARK: - Effects

    private func spawnDueEffects() {
        guard activeFlourish != nil, !pendingSpawns.isEmpty else { return }

        var stillWaiting: [EffectSpawn] = []
        for spawn in pendingSpawns {
            if isDue(spawn) {
                spawnEffect(spawn)
            } else {
                stillWaiting.append(spawn)
            }
        }
        pendingSpawns = stillWaiting
    }

    private func isDue(_ spawn: EffectSpawn) -> Bool {
        switch spawn.trigger {
        case .onStart:
            return true
        case .onFrame(let frame):
            // `>=` rather than `==`: at 12 Hz a 15 fps clip can skip a frame index
            // entirely, and an effect that silently never fires on a throttled tick is a
            // horrible thing to chase.
            return frameIndex >= frame
        case .afterDelay(let delay):
            return flourishElapsed >= delay
        }
    }

    /// Whether a travelling effect has left the strip and can be forgotten.
    ///
    /// Only travelling effects are tested. A stationary one is bounded by its animation
    /// or its lifetime, and testing it would retire an effect that was deliberately
    /// anchored just off the edge.
    ///
    /// The bounds are grown by the effect's own size so it is retired once it is fully
    /// out of sight rather than the instant its centre crosses the line.
    private func hasLeftStrip(_ effect: ActiveEffect) -> Bool {
        guard effect.travels, stripSize != .zero else { return false }
        let bounds = CGRect(origin: .zero, size: stripSize)
            .insetBy(dx: -effect.size.width, dy: -effect.size.height)
        return !bounds.contains(effect.position)
    }

    private func spawnEffect(_ spawn: EffectSpawn) {
        guard let clip = catalogue[spawn.clip] else { return }
        let offset = effectOffset(spawn.anchor)
        nextEffectID += 1
        // Logged because an effect that never appears has several possible causes —
        // trigger never reached, artwork missing, anchor off the top of the strip — and
        // this line is what separates "it never fired" from "it fired somewhere I can't see".
        Self.logger.debug("Spawning effect '\(clip.id.rawValue, privacy: .public)' at frame \(self.frameIndex).")
        let scale = configuration.pointsPerSourcePixel
        let mirror: CGFloat = facing == .left ? -1 : 1

        // A looping clip that stays put would otherwise never end. One loop is the least
        // surprising default; a manifest asking for longer says so with `lifetime`.
        let travels = spawn.travels
        let lifetime = spawn.lifetime ?? (clip.loops && !travels ? clip.duration : nil)

        activeEffects.append(
            ActiveEffect(
                id: nextEffectID,
                clip: clip,
                z: spawn.z,
                position: effectPosition(offset: offset),
                follows: spawn.follows,
                offset: offset,
                velocity: CGSize(
                    width: spawn.velocity.dx * mirror * scale,
                    height: spawn.velocity.dy * scale
                ),
                acceleration: CGSize(
                    width: spawn.acceleration.dx * mirror * scale,
                    height: spawn.acceleration.dy * scale
                ),
                lifetime: lifetime,
                size: effectSize(for: clip)
            )
        )
    }

    /// Converts a source-pixel anchor into a point offset from the sprite's centre.
    ///
    /// Mirrored on X when the sprite faces left, which is the only thing `facing` is
    /// actually used for — the body artwork has its own left and right rows.
    private func effectOffset(_ anchor: CGPoint) -> CGSize {
        let scale = configuration.pointsPerSourcePixel
        return CGSize(
            width: (facing == .left ? -anchor.x : anchor.x) * scale,
            height: anchor.y * scale
        )
    }

    private func effectPosition(offset: CGSize) -> CGPoint {
        let rect = spriteRect
        return CGPoint(x: rect.midX + offset.width, y: rect.midY + offset.height)
    }

    /// On-screen size of an effect, in points.
    ///
    /// Scaled by the same points-per-source-pixel factor as the sprite, so an effect
    /// drawn on a 64×64 grid comes out twice the size of one drawn on a 32×32 grid —
    /// which is what an artist authoring a big explosion would expect.
    private func effectSize(for clip: AnimationClip) -> CGSize {
        let frame = catalogue.sheets[clip.sheet]?.frameSize ?? configuration.spriteSheetFrameSize
        let scale = configuration.pointsPerSourcePixel
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }

    private func refreshPublishedEffects() {
        let renders = activeEffects
            .sorted { $0.z < $1.z }
            .map { effect in
                EffectRender(
                    id: effect.id,
                    clip: effect.clip.id,
                    frame: effect.frameIndex,
                    position: effect.position,
                    size: effectSize(for: effect.clip),
                    z: effect.z
                )
            }
        // Same rule as everywhere else here: publish only on a real change. `elapsed`
        // moves every tick but the rendered frame usually does not.
        if renders != effects { effects = renders }
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
