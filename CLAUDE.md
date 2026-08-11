# CLAUDE.md

Working reference for this repo. The `README.md` is the user-facing guide (Xcode setup,
design rationale, customising); this file is the short version plus the things that will
bite you when extending the sprite.

## What this is

A macOS desktop companion (`LSUIElement` background agent, no Dock icon): a 16×16 pixel
sprite living in a transparent full-width strip above the Dock. It wanders on its own,
reacts to the cursor, and fires small macOS actions when clicked. Menu-bar item is the
only UI and the only way to quit.

AppKit + SwiftUI. Swift, no third-party dependencies, no test target. macOS 13+.

## Build & run

Xcode is installed but `xcode-select` points at CommandLineTools, so use the full path:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project DesktopSprite/DesktopSprite.xcodeproj -scheme DesktopSprite -configuration Debug build
```

To launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/DesktopSprite-*/Build/Products/Debug/DesktopSprite.app
```

Quit it from the 🎮 menu-bar item — there is no Dock icon and no `⌘Q` outside that menu.

Logs go to the unified log under subsystem `com.thirtytwobitlife.desktopsprite`
(categories: `AppDelegate`, `SpriteViewModel`, `SpriteSheet`, `LoginItem`):

```bash
log stream --predicate 'subsystem == "com.thirtytwobitlife.desktopsprite"' --level debug
```

**The `.xcodeproj` is not folder-synchronized.** All 17 Swift files are listed
individually in `project.pbxproj`, as are the two files in `Resources/`. A new source
file added on disk will *not* be compiled until it is added to the target in Xcode — the
symptom is "cannot find X in scope" for a type you can plainly see in the repo. A new
*resource* fails more quietly: `Animations.json` not added to the Resources build phase
does not break the build, it just silently falls back to the built-in animation defaults.
The loader logs the absent-manifest case explicitly so this is diagnosable.

## Layout

```
Sources/DesktopSprite/
  App/          Entry point, AppDelegate (owns everything), the NSPanel
  Model/        SpriteConfiguration (all tunables), SpriteState (the behaviour machine),
                AnimationClip (clip data, manifest decoding, the catalogue)
  ViewModel/    SpriteViewModel (the tick loop), MouseTracker (proximity)
  Rendering/    SpriteProvider protocol, placeholder pixel art, SpriteSheetLibrary, the View
  Actions/      SpriteAction protocol + registry, built-in actions
  Support/      ScreenGeometry (coordinates), LoginItemController (SMAppService)
  Resources/    SpriteSheet.png, Animations.json (the manifest; optional)
DesktopSprite/DesktopSprite.xcodeproj    Target references ../Sources; do not copy sources in
```

## States vs clips

These are deliberately separate concepts and conflating them is the main way to make a
mess here.

- **`SpriteState`** is *behaviour*: five cases, code-driven, exhaustive switches. What the
  sprite is doing and what it is allowed to do next.
- **`AnimationClip`** is *animation data*: which sheet row, how fast, does it loop, what
  does it drag along with it. Clips are declared in `Resources/Animations.json`, named
  rather than numbered, and their **frame counts are read out of the artwork** — trailing
  transparent cells in a row are not frames.

A state maps to a clip through `SpriteState.clipID`, which works off the enum's raw value
and is deliberately not a switch. Clips can exist that no state maps to — flourishes and
the companion effects they spawn — which is the whole point of the split. The catalogue
is built once at launch by `SpriteProviderFactory.bestAvailable` and is the sole authority
on frame counts, rates and looping.

Ownership flows one way: `AppDelegate` → `SpriteViewModel` → (`MouseTracker`,
`SpriteActionRegistry`). `AppDelegate` conforms to `SpriteHost`, which is the only way
the view model touches the window — it holds no `NSWindow` reference.

## The tick loop

One `Timer` on `RunLoop.main` in `.common` mode drives everything.
`SpriteViewModel.tick()` runs these stages in order, and order matters:

1. `sampleCursor()` — one `NSEvent.mouseLocation` read, converted to local coords
2. `updateClickThrough()` — flips `ignoresMouseEvents` on the window
3. `reactToCursor()` — startle / surprised / settle back to idle; cancels any flourish
4. `updateWander()` — the autonomous AI, suppressed while reacting or airborne; this is
   where a flourish is rolled for
5. `updatePhysics()` — gravity, then clip motion, then running; edge turnaround
6. `syncClip()` — publishes the clip to draw, resetting the frame clock when it changes
7. `advanceFrame()` — animation frame clock, driven by the catalogue's frame count
8. `startDueMotion()` — starts a moving clip's travel once its trigger is reached
9. `updateEffects()` — spawns effects whose trigger has been reached, integrates the
   travelling ones, retires the finished and the off-screen
10. `updateFlourish()` — retires a flourish once its clip has played out *and* the sprite
    has come to rest
11. `refreshPublishedPosition()`
12. `updateTickRate()` — 60 Hz active, 12 Hz after 3s idle-and-alone

New per-frame behaviour goes in as a stage here, not as a second timer.

Stages 8 and 9 sit before stage 10 on purpose: `updateFlourish` discards anything still
pending when it retires a clip, so a motion or an effect triggered on the clip's *last*
frame would never fire if they were swapped. Both read `frameIndex`, so both must also
come after `advanceFrame`.

`advanceFrame` deliberately does nothing on the tick `syncClip` swapped the clip in.
Without that, a flourish starting from dormancy has its first frame advanced past before
it is ever drawn — the tick carries a whole 12 Hz delta — and since flourishes only start
from idle, an authored `onFrame` wind-up would fire almost immediately and almost at
random.

## Invariants — do not break these

- **Click-through.** The strip spans the full screen width. `ignoresMouseEvents` is
  `true` except while the cursor is inside the sprite's box. Anything that makes the
  window permanently interactive swallows every desktop click along the bottom edge.
- **Everything is `@MainActor`.** There is no concurrency here beyond the run-loop
  timer, deliberately. `MainActor.assumeIsolated` is used in the timer and notification
  callbacks because main-thread delivery is already guaranteed.
- **`@Published` writes only on change.** `advanceFrame` and `refreshPublishedPosition`
  both guard on inequality; assigning the same value 60×/sec re-renders for nothing.
- **All transitions go through `transition(to:force:)`.** That single funnel is what
  makes `SpriteState.minimumDuration` mean anything. `force: true` is for physics- and
  user-driven changes (jump, landing, edge turnaround) only.
- **Pixel crispness needs three things:** `shouldInterpolate: false` on the CGImage,
  `.interpolation(.none)` on the SwiftUI `Image`, and `pixelSnapped(_:)` on the
  position. Drop any one and the sprite blurs or shimmers as it moves.
- **Coordinate systems.** AppKit global is bottom-left origin, +Y up. SwiftUI local is
  top-left origin, +Y down. Every crossing goes through `ScreenGeometry.globalToLocal`.
  Inside the view model, local Y grows downward: `altitude` is *subtracted* to go up.
- **No hard-coded numbers outside `SpriteConfiguration`.** Speeds, distances, durations,
  frame rates, sizes all live there. Per-clip animation numbers are the one exception and
  they live in `Animations.json`, not in Swift.
- **Frame counts are never declared in code.** They come from the artwork. The only
  hard-coded counts are the fallback table in `AnimationCatalogue.builtInClips`, used when
  there is no sheet to read — keep it in step with `PlaceholderSprite`.
- **Flourish time is measured on the accumulated tick delta, not `Date`.** This process
  runs for days across sleep, wake, and clock corrections; wall-clock arithmetic would
  either suppress every flourish or fire them all at once.
- **Effects never take hit tests.** They are decoration drawn over a full-width strip; one
  that accepted clicks would hand the strip back its ability to swallow desktop clicks.
- **Every effect must have an ending.** Lifetime, animation length, or leaving the strip —
  one of the three always applies (see `ActiveEffect.isFinished` and the lifetime default
  in `spawnEffect`). A looping effect with no way to die pins the app at 60 Hz forever.
- **Every motion must have an ending**, for the same reason. Landing, the authored
  `distance` cap, or the edge of the strip — one of the three always applies. A moving clip
  holds `activeFlourish` for its whole travel, and `updateTickRate` counts that as activity,
  so a motion that never ends pins the app at 60 Hz just as an immortal effect would. This
  is why a looping clip has its motion dropped at load.
- **A moving clip is uninterruptible.** `cancelFlourish`, `performClip`, `handleTap` and
  `beginJump` all refuse while `isMotionActive`. Abandoning one mid-arc strands the sprite
  in the air with velocity and no clip to explain it. `isMotionActive` is stored, never
  derived from `isAirborne` — an ordinary startle jump is airborne too, and conflating the
  two silently changes how a plain jump interacts with click previews and cancellation.
- **Travelling effects integrate velocity before position**, matching the order
  `updatePhysics` uses for the sprite. Mixing the two orders makes an effect and the
  sprite fall at visibly different rates from the same acceleration.

## Extending it

**Add an animation** — no Swift. Draw a row, add a clip to `Resources/Animations.json`
naming its sheet and row. Frame count comes from the pixels. Give it a `flourish` rule
and the sprite performs it spontaneously; hang `effects` off it for companion animations,
and a `motion` block to make it move the sprite itself (a leap, a pounce, a dash). See the
README for the full schema.

`"scale"` on a clip trims the size it is *drawn* at, for art that shares the sheet's cell
size but should not read as big as the character. Drawn size only — anchors and velocities
stay in world source pixels — and it is honoured for **effects only**, since `spriteSize`
is what the hit-test box and the ground line are measured from. The loader logs a clip that
sets one and is never spawned as an effect.

Motion and effects share a vocabulary on purpose — source-pixel units, the same `trigger`,
mirrored on facing — the difference being that an effect moves decoration away from the
character while `motion` moves the character. Only a *performed* clip can move the sprite:
a flourish, or whatever `clickClipID` points at. Motion on a state clip or an effect-only
clip is inert, and the loader logs it.

**Add an animation *state*** — only when you need new *behaviour*, not just a new
animation. Add a case to `SpriteState`, then fill in the three switches
(`minimumDuration`, `impliedFacing`, `allowsWandering`). They are exhaustive, so the
compiler lists what you owe. The tick loop needs no change. The case's raw value is its
clip name, so give it a manifest entry under that name; without a sheet you also need a
pose in `PlaceholderSprite`, whose frame counts must match the fallback table in
`AnimationCatalogue.builtInClips`.

**Add an action** — conform to `SpriteAction` (id, title, systemImage, `perform()`),
register it in `AppDelegate.registerActions()`. It appears in the menu bar
automatically. `actionRegistry.defaultActionID` picks what a click on the sprite fires.
`LogAction` in `BuiltInActions.swift` is the minimal template.

**Add artwork** — see the README. Drop a `SpriteSheet.png` into the bundle and
`SpriteProviderFactory` picks it up at launch with no code change; it falls back to the
placeholder art on any problem. Author facing **right** and set `"mirrors": true` on any
clip that should flip when the sprite faces left — that is per-clip and off by default, so
a clip with its own drawn left row (like `runningLeft`, if you keep one) is never flipped.

**Tune the feel** — `SpriteConfiguration.swift`, nothing else.

## Conventions

- Every file opens with a header comment saying what it is *for*, and doc comments
  explain **why** a decision was made, not what the code does. This is the house style
  and it is unusually heavy — match it. Several of these comments are load-bearing
  (they record traps that cost real debugging time).
- British spelling in comments (`behaviour`, `rasterised`, `initialisation`).
- `// MARK: -` section dividers in every file over ~50 lines.
- Failures in optional subsystems (sprite sheet, login item) are logged and swallowed,
  never fatal. A background app the user can barely see must not crash or trap.

## Known rough edges

- `README.md` is stale in two places: it says there is no `.xcodeproj` (one is now
  committed) and that the project has never been compiled (it builds and runs). The
  setup instructions are still useful history but no longer the path to a build.
- Deployment target in the project is **13.5**, not the 13.0 the README states.
- Three different names are in play: repo `32-Bit-Life`, target/product `DesktopSprite`,
  bundle id `sayge.dev.DesktopSprite`, log subsystem `com.thirtytwobitlife.desktopsprite`.
  A rename touches: the file-header comment in all 16 sources, `MenuBarExtra` title and
  the Quit button in `DesktopSpriteApp.swift`, the notification action text in
  `BuiltInActions.swift`, four `Logger(subsystem:)` literals, `PRODUCT_BUNDLE_IDENTIFIER`
  and the target/scheme names in the project, the `Sources/DesktopSprite/` directory,
  and the README.
- Nothing persists across launches except the login item (macOS stores that itself).
  Sprite visibility and the chosen default action reset every time.
- Primary display only; single axis of gravity; reduced-motion is not honoured.
