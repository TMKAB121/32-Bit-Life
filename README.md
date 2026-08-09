# 32-Bit Life

A macOS desktop companion: a retro 8-bit sprite that lives in a transparent strip
across the bottom of your screen, wanders around on its own, reacts to your cursor,
and runs small macOS actions when you click it.

Built with AppKit + SwiftUI. Requires **macOS 13 Ventura** or later, and **Xcode 15**
or later to build.

---

## Setting up the Xcode project

There is no `.xcodeproj` in this repository — only sources. Creating the target
yourself takes about two minutes and means the project settings are ones you chose.

### 1. Create the app target

1. Xcode → **File ▸ New ▸ Project…**
2. Choose **macOS ▸ App**, then **Next**.
3. Product Name: `DesktopSprite` · Interface: **SwiftUI** · Language: **Swift**.
   Leave "Use Core Data" and "Include Tests" unchecked.
4. Save it **inside this repository folder** (the same directory as this README).

### 2. Remove the generated boilerplate

Delete the two files Xcode generated — this project supplies its own versions:

- `ContentView.swift`
- `DesktopSpriteApp.swift` *(whatever Xcode named your `@main` file)*

Choose **Move to Trash**, not "Remove Reference".

### 3. Add the sources

Drag the `Sources/DesktopSprite` folder from Finder into the Xcode project navigator,
then — **this is the step that matters** — tell Xcode not to copy the files:

- **Xcode 16 and later:** set **Action** to **Reference files in place**.
  The default is *Copy files to destination*; do not leave it there.
- **Xcode 15 and earlier:** leave **Copy items if needed** *unchecked*.
- Either way, tick the **DesktopSprite** target.

If the `Groups` dropdown offers a folder-synchronized option, prefer it — Xcode will
then pick up files added on disk automatically, instead of you re-adding them by hand
after every `git pull` that introduces a new source file.

> **Why this matters.** Copying puts a second set of sources inside the project folder,
> and Xcode compiles *those*. Your edits and any `git pull` then go to the repo copy
> while the build silently keeps using the stale one — so fixes appear to have no
> effect and errors look unfixable. If you suspect this has happened, select any source
> file, open the File Inspector (⌥⌘1), and check that **Full Path** points inside the
> Git repository and not inside the `.xcodeproj`'s folder.

> **Then remove `Info.plist` and `DesktopSprite.entitlements` from Build Phases ▸
> Copy Bundle Resources.** Dragging the folder in adds them as bundle resources, but
> they are referenced by build settings and must not be copied. If you skip this you
> get the warning *"The Copy Bundle Resources build phase contains this target's
> Info.plist file"* — that is this step.

### 4. Build settings

In the target's **Build Settings**, set:

| Setting | Value |
|---|---|
| macOS Deployment Target | `13.0` or later |
| Info.plist File | `../Sources/DesktopSprite/Info.plist` |
| Code Signing Entitlements | `../Sources/DesktopSprite/DesktopSprite.entitlements` |
| Generate Info.plist File | `No` |

Those two paths are relative to the **`.xcodeproj`**, not to the repository root. Xcode
puts a new project in a subfolder named after the product — `32-Bit-Life/DesktopSprite/` —
so reaching `32-Bit-Life/Sources/` needs the leading `../`. If you moved the project to
the repository root instead, drop the `../`. Xcode shows the resolved path when you hover
the value, which is the quickest way to confirm you got it right.

`Info.plist` intentionally does not contain `LSMinimumSystemVersion` — Xcode injects
it from the deployment target. Leave that build setting wherever you want it (13.0 or
newer); nothing needs to be kept in sync by hand.

If you would rather keep Xcode's generated Info.plist, skip the plist rows above and
instead go to **Build Settings**, search for `LSUIElement`, and set
**Application is agent (UIElement)** to `YES`. That single key is the only thing in
`Info.plist` that the app actually depends on.

### 5. Build and run

⌘R. The sprite appears above your Dock and a 🎮 icon appears in the menu bar.

> **There is no Dock icon and no application menu.** `LSUIElement` makes this a
> background agent, which is what makes it feel like part of the desktop rather than
> a window you have to manage. **Quit from the menu-bar icon.** If you remove the
> `MenuBarExtra` from `DesktopSpriteApp.swift`, you will have no way to quit the app
> short of Activity Monitor.

---

## How it fits together

```
App/
  DesktopSpriteApp.swift   @main. MenuBarExtra + NSApplicationDelegateAdaptor.
  AppDelegate.swift        Owns the window, view model and actions. Watches the
                           system for screen and sleep changes.
  SpriteWindow.swift       The transparent NSPanel and its hosting view.
Model/
  SpriteConfiguration.swift  Every tunable number in the app.
  SpriteState.swift          The behaviour machine: states and transition rules.
  AnimationClip.swift        Clips, effects, flourishes; the manifest and the catalogue.
ViewModel/
  SpriteViewModel.swift    The tick loop: physics, wander AI, reactions, flourishes,
                           effects, throttling.
  MouseTracker.swift       Cursor proximity, with hysteresis.
Rendering/
  SpriteProvider.swift     Protocol seam between behaviour and artwork.
  PlaceholderSprite.swift  Built-in pixel art, authored as character grids.
  PixelArt.swift           Character grid → CGImage.
  SpriteSheetLibrary.swift PNG sheets → per-clip frames, counts derived from the pixels.
  DesktopSpriteView.swift  The SwiftUI view. No logic — it reads and draws.
Resources/
  SpriteSheet.png          The artwork.
  Animations.json          The manifest. Optional; see "The animation manifest".
Actions/
  SpriteAction.swift       Protocol + registry.
  BuiltInActions.swift     Sound, notification, open-link, and a logging template.
Support/
  ScreenGeometry.swift       Screen selection and coordinate conversion.
  LoginItemController.swift  SMAppService wrapper for "Open at Login".
```

---

## Design notes

These are the decisions that are not obvious from the code, and the reasons behind them.

**The strip is click-through except where the sprite is.** The window spans the full
width of the screen. If it accepted mouse events it would swallow every click on the
desktop and on the bottom edge of every other window. So `ignoresMouseEvents` is `true`
by default, and `SpriteViewModel` flips it off only while the cursor is inside the
sprite's bounding box. This is the single most important thing to preserve if you
refactor the window code.

**Cursor position is polled, not monitored.** `NSEvent.mouseLocation` is read once per
tick. A *local* event monitor would see nothing, because the window ignores mouse events
almost everywhere. A *global* monitor would work — global mouse monitors do not need
Accessibility permission, only keyboard ones do — but polling is synchronous, always in
step with the physics it feeds, and has no object lifetime to manage.

**`NSScreen.screens.first`, not `NSScreen.main`.** `NSScreen.main` is the screen with
*keyboard focus*, so it changes every time you click on a different display. The
companion is docked to the primary screen instead.

**Proximity uses two thresholds.** The sprite starts reacting at 50 points and stops at
80. With one threshold, a cursor parked on the boundary flickers the sprite between
states on every tick.

**`.interpolation(.none)` is required.** Without it, a 16×16 sprite scaled to 64×64 on
a Retina display is smeared into a blur. Both the CGImage (`shouldInterpolate: false`)
and the SwiftUI `Image` set it.

**Position is snapped to the physical pixel grid.** Nearest-neighbour scaling alone is
not enough. The view model advances position by `speed × delta`, which lands the sprite
on fractional point values; at 4× scale that makes some pixel columns render one device
pixel wider than others, with the pattern shifting every frame. The result is a sprite
that shimmers and crawls as it moves. `DesktopSpriteView.pixelSnapped(_:)` rounds the
centre to whole device pixels using `@Environment(\.displayScale)`, so it stays correct
when the window moves between a Retina and a non-Retina display.

**One timer, two rates.** A single tick drives physics, cursor sampling and frame
advance. It runs at 60 Hz while anything is happening and drops to 12 Hz once the sprite
has been idle and alone for three seconds, and suspends entirely when the display sleeps.
This app runs all day; `TimelineView(.animation)` would keep the GPU busy forever.

---

## Customising it

### Tuning the feel

Everything lives in `SpriteConfiguration.swift` — speed, gravity, jump height, the
proximity thresholds, the wander timings, the tick rates, the sprite size. Nothing else
in the app hard-codes a number.

### Dropping in a real sprite sheet

The app ships with programmatic pixel art so it looks like something the moment you
build it. To replace it with real artwork:

1. Author a PNG laid out as **one row per clip, one column per frame**:

   | Row | Clip | Frames |
   |---|---|---|
   | 0 | idle | 2 |
   | 1 | runningRight | 4 |
   | 2 | runningLeft | 4 |
   | 3 | surprised | 2 |
   | 4 | jumping | 1 |

   **Frame counts are read from the artwork, not declared anywhere.** Trailing
   transparent cells in a row are not frames, so rows may be as short as they like — draw
   a third idle pose into row 0 and the idle animation becomes three frames with no other
   change. A transparent cell in the *middle* of a row is respected as a real frame, so
   blink-off and flicker gaps work.

   At the default 32×32 frame size the table above is a 128×160 pixel image.

2. Name it `SpriteSheet.png` and add it to the target — either into `Assets.xcassets`
   or directly as a file resource. Both are checked.

3. Build. That is all: `SpriteProviderFactory` looks for the asset at launch and uses
   it if it is there, falling back to the placeholder art if it is missing or unreadable.
   **No code changes are needed.**

   To use a different name or frame size, change `spriteSheetAssetName` /
   `spriteSheetFrameSize` in `SpriteConfiguration.swift`.

Author facing **right**. Whether a clip is flipped when the sprite faces left is a per-clip
decision (`"mirrors": true` in the manifest), so a directional animation can either be
drawn twice — `runningLeft` gets its own row — or drawn once and mirrored.

### The animation manifest

Everything past the five built-in clips is data. Drop an `Animations.json` into the
bundle beside the PNG and you can add animations, extra sheets, spontaneous flourishes
and companion effects **without touching Swift at all**.

The file is optional — without it the app animates from the five clips above.

```json
{
  "version": 1,
  "sheets": {
    "SpriteSheet": { "frameSize": [32, 32] },
    "Effects":     { "frameSize": [32, 32] }
  },
  "clips": [
    { "id": "idle", "sheet": "SpriteSheet", "row": 0, "fps": 2.5, "loops": true },

    { "id": "charge", "sheet": "SpriteSheet", "row": 5, "fps": 8, "loops": false,
      "flourish": { "cooldown": 45, "weight": 1 },
      "effects": [
        { "clip": "chargeShot", "trigger": { "onFrame": 3 },
          "anchor": [12, -8], "velocity": [120, 0], "z": 1 }
      ] },

    { "id": "chargeShot", "sheet": "Effects", "row": 0, "fps": 12, "loops": true }
  ]
}
```

**Clips.** `row` is stated explicitly, so adding a clip never renumbers the rows beneath
it and a clip can live on a sheet of its own. `frames` may be given to override the count
derived from the pixels, but it is rarely needed. The five built-in clips are always
present; listing one here retunes it rather than replacing the set.

**`"mirrors": true`** flips a clip horizontally when the sprite faces left. Set it on
anything drawn in one direction only — most flourishes, and almost every effect. Without
it a shot authored pointing right flies leftwards still pointing right, which reads as the
sprite firing backwards.

It is off by default rather than on, because flipping is not always what you want: art can
be symmetric, or deliberately always face the viewer, or have its own drawn left-hand row.
For an effect the decision is made when it spawns, so a shot already in flight keeps
pointing the way it was fired even if the sprite turns around behind it.

This is also how to get one run cycle instead of two — point both running clips at the
same row and let the left one flip:

```json
{ "id": "runningRight", "sheet": "SpriteSheet", "row": 1, "fps": 10, "loops": true },
{ "id": "runningLeft",  "sheet": "SpriteSheet", "row": 1, "fps": 10, "loops": true, "mirrors": true }
```

The two *states* stay as they are — they carry the direction of travel, which the physics
reads — but the artwork collapses to one row.

**Flourishes** are clips the sprite performs of its own accord — a wave, a stretch, a
charge-up. They must be non-looping, because a flourish ends when its animation does.
`cooldown` is the minimum gap between two performances of *that* clip; `weight` biases
the pick when several are eligible. Two more knobs live in `SpriteConfiguration.swift`:
`flourishProbability` (how eagerly the sprite reaches for one) and `flourishSpacing`
(the floor between *any* two flourishes, so several coming off cooldown together do not
fire back to back). A flourish only ever starts from a standing idle, and the cursor
arriving — or a click — abandons it immediately.

**Effects** are companion animations attached to a clip: the block Mario headbutts, the
glow around a charged shot.

- `trigger` — `{"onFrame": 3}`, `{"afterDelay": 0.25}`, or omitted for "on start".
- `anchor` — `[x, y]` from the centre of the sprite, in **source pixels** so the number
  survives a change to `spriteSize`. `+y` is down. Mirrored when the sprite faces left.
- `follows` — `true` (default) rides along with the sprite; `false` pins it where it was
  born. This is the whole Mario/Mega Man difference: a struck block stays put while the
  character falls away from it.
- `velocity` — `[x, y]` in source pixels per second. Anything non-zero makes the effect
  travel under its own steam, and `follows` is then ignored. Mirrored with facing, so one
  declaration fires left when the sprite faces left.
- `acceleration` — `[x, y]` in source pixels per second squared. Velocity plus
  acceleration is what turns a flat shot into a tossed coin: give it an upward velocity
  and a downward acceleration and it arcs.
- `lifetime` — seconds before it disappears, whatever its animation is doing.
- `z` — draw order; the sprite is `0`, so negative draws behind it.

**How long an effect lives**, in the order the rules apply: an explicit `lifetime` always
wins; otherwise a non-looping clip lasts exactly as long as its animation; a looping clip
that travels lives until it leaves the strip; and a looping clip that stays put plays
through once. There is no way to author an effect that never goes away.

That second rule is the one that catches people out with projectiles. A two-frame clip at
8 fps lasts 0.25 seconds, so a shot with a long, graceful arc will vanish a quarter of a
second after it is fired unless you either loop the clip or give it a `lifetime`.

Effects outlive the flourish that spawned them if it ends naturally. If it is *interrupted*
— the cursor arrives, or you click — attached effects are cleared with it, but anything
already travelling is left to fly on, since a projectile that has left the character is its
own object by then.

If an effect is drawn far above the sprite, raise `effectClearance` in
`SpriteConfiguration.swift` — the strip is the only canvas, and anything taller than it is
simply clipped.

Every failure here is survivable and logged: a missing manifest falls back to the
built-ins, a malformed one does the same, and a single clip naming a missing sheet or an
empty row is dropped while the rest keep working. Watch for it with:

```bash
log stream --predicate 'subsystem == "com.thirtytwobitlife.desktopsprite"' --level debug
```

### Adding an action

Conform to `SpriteAction` and register it in `AppDelegate.registerActions()`:

```swift
struct OpenTerminalAction: SpriteAction {
    let id = "terminal"
    let title = "Open Terminal"
    let systemImage = "terminal"

    func perform() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }
}
```

Registered actions appear in the menu bar automatically. Set
`actionRegistry.defaultActionID` to choose which one clicking the sprite fires.

`LogAction` in `BuiltInActions.swift` is the minimal template.

### Adding a state

Most new animations do **not** need a state — if the sprite should simply perform
something now and then, add a clip with a `flourish` rule to the manifest and stop there.

A state is for new *behaviour*: something the sprite enters and leaves under its own
rules. Add a case to `SpriteState` and fill in the three switches — `minimumDuration`,
`impliedFacing`, `allowsWandering` — then give it a row in the manifest under the same
name as the case. The tick loop needs no changes.

---

## Launch at login

The menu bar has an **Open at Login** toggle, backed by `SMAppService` (macOS 13+,
no helper target required — it replaced the old `SMLoginItemSetEnabled` bundle dance).

**This cannot be meaningfully tested from Xcode.** `SMAppService` registers *the path
the app currently occupies*, and running from Xcode that path is inside DerivedData,
which gets wiped on the next clean build. Registration appears to succeed and then
silently stops working. To actually test it: Product ▸ Archive, export the app, move it
to `/Applications`, and toggle it there.

Registration can also land in `.requiresApproval` rather than `.enabled` — macOS puts
it there when the user has previously disabled the item in System Settings. The menu
shows an **Approve in System Settings…** shortcut when that happens.

Every failure is logged and swallowed. Failing to become a login item is a
disappointment, not a reason for a background app to misbehave at launch. Check
Console.app for the `LoginItem` category if the toggle does not stick.

---

## Sandboxing

The app runs inside the App Sandbox and none of the built-in actions need an exception.
Reading the cursor position, floating a window, playing a system sound and posting a
local notification are all permitted.

One limit worth knowing: `NSWorkspace.open` works under the sandbox for registered URL
schemes (`https`, `mailto`, and so on), but **launching an arbitrary `.app` by file path
does not**. If you add an action that needs to do that, set
`com.apple.security.app-sandbox` to `<false/>` in `DesktopSprite.entitlements`.

Notification permission is requested lazily, the first time a notification action runs —
not at launch. A background app that fires a permission prompt the instant it starts is
obnoxious, and the prompt makes more sense once the user has actually asked for one.

---

## Verifying it works

This prototype has not been compiled — it was written on a machine without Xcode, so
the first build is yours. Beyond "it launches", here is what is worth checking:

1. **No Dock icon**, sprite visible above the Dock, and Quit works from the menu bar.
2. **Click on the empty desktop through the strip.** The click must reach the desktop.
   If the strip swallows it, `ignoresMouseEvents` is not being managed correctly.
3. **Move the cursor slowly toward the sprite.** It should react once at roughly 50
   points away, and hovering exactly at that boundary should *not* flicker.
4. **Click the sprite.** It bounces and the default action fires (a "Pop" sound).
5. **Toggle Dock auto-hide, then change the Dock size.** The strip re-anchors each time.
6. **Switch Spaces, then open a full-screen app.** The sprite follows and stays visible.
7. **Leave it alone for a minute** and watch it in Activity Monitor. CPU should drop
   noticeably as the tick throttles from 60 Hz to 12 Hz. (This is the design intent,
   not a measured figure — the throttle has never been profiled.)
8. **Plug in a second display**, or change resolution. The sprite stays on the primary
   screen and stays inside its bounds.
9. **Watch the sprite closely while it runs.** Pixels should stay crisp and uniform.
   Shimmering or pixel columns changing width means `pixelSnapped(_:)` is not doing
   its job.
10. **Open at Login** — only testable from `/Applications`, see above.

---

## Known limitations

- The sprite lives on the primary display only. Multi-display support would mean one
  window per screen and a policy for which one the sprite occupies.
- The Dock is treated as being at the bottom. With the Dock on the left or right,
  `visibleFrame` still gives a correct bottom edge, so the sprite works — it just does
  not know the Dock is beside it.
- `.jumping` is a single held pose. A real jump would want separate rise, apex and fall
  frames; add them as frames 0–2 and give the state `loops: false`.
- Physics are deliberately minimal: one axis of gravity, no collision with anything but
  the ground line and the screen edges.
- **Nothing persists.** Sprite visibility and the chosen default action reset on every
  launch. Only the login item survives, because macOS stores that itself.
- **A click can be dropped in one narrow case.** The `ignoresMouseEvents` flip happens
  on the tick, which is 83 ms while dormant. Moving the cursor from outside the 50-point
  proximity radius onto the sprite and clicking within that window sends the click to
  the desktop instead. Approaching at any normal speed restores the 60 Hz tick first.
- **The sprite appears in screenshots and screen shares.** Setting
  `window.sharingType = .none` in `SpriteWindow` excludes it from capture while leaving
  it visible to you.
- **Reduced motion is not honoured.** A perpetually moving object in peripheral vision
  is a real accessibility problem. Checking
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and suppressing the wander
  — keeping only cursor reactions — would address it.
- **A global hide/show hotkey would need Accessibility permission.** Mouse monitoring
  does not, but keyboard monitoring does, which changes the app's install story.
