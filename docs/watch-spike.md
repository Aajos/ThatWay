# Watch spike — report and test protocol

Status: **built, unit-tested and run in the watchOS simulator. The three on-wrist tests have NOT been run**: no Apple Watch
was connected to this Mac, and signing the watch app needs a one-time step in Xcode (below). Every number in the
"Results" tables is therefore empty on purpose; nothing has been guessed. This file says what is ready, how to run each
test in about two minutes of setup, how the logs become the numbers, and what we already learned.

## 0. How the watch app is controlled now (latest)
| Gesture | Does |
|---|---|
| Swipe **left** | next theme (Ember, Tide, Paper, Arcade; remembered) |
| Swipe **right** | voice destination search: tap the big mic button (watchOS cannot start dictation by itself), say a place, tap a result: real route for the current mode, Point mode if no route |
| Swipe **up / down** | next / previous travel mode: **Walk, Run, Cycle** only (wraps; Cycle fetches its own route) |
| Long-press the compass | next needle skin |
| **⋯** button | test tools: heading debug, wrist-down session, haptic blind test |

**Drive guard.** If the paired iPhone is in **Drive** mode the watch refuses to guide: it stops location, heading, any session and the route, shows
"Not while driving", and closes itself after 6 s. The iPhone sends only its travel mode (WatchConnectivity); the watch reads the stored value at
launch, which takes about 3 s to arrive on a cold start. An unpaired or out-of-range watch is not blocked. watchOS has no "quit", so the app calls
`exit(0)`: fine for the spike, but App Review dislikes it, so revisit before shipping.

**The watch app is now the iPhone app's companion** (embedded in it, bundle id `com.aadittesting.ThatWay.ThatWay.watchkitapp`), which the phone-to-watch link
requires. Consequence: building the iPhone app **for a real device** now also signs the watch app, so Xcode needs your account signed in
(Settings > Accounts) and the watch registered. Simulator builds and tests are unaffected. Install by running the **ThatWay** scheme from Xcode with the paired
iPhone as destination; it installs both. (The container id for pulling logs is now `com.aadittesting.ThatWay.ThatWay.watchkitapp`.)

## 1. What was built

| Piece | Where | State |
|---|---|---|
| Shared module `ThatWayCore` (local Swift package, Foundation + CoreLocation only) | `ThatWayCore/` | Done. iOS app and watch app both import it; `swift test` runs 22 tests on the Mac |
| watchOS target `ThatWayWatch` (SwiftUI, standalone watch-only app, watchOS 10.0+) | `ThatWayWatch/` | Builds for the watchOS simulator; **not yet signed for a real watch** |
| Main screen: Point/Guide toggle, large needle, speed bottom right, arrow + distance to next waypoint bottom left | `MainView.swift` | Verified in the simulator (moving GPS track, test route) |
| Test 1 switch: A background location / B workout run / B workout cycle | `SessionController.swift`, page 3 | A verified end-to-end in the simulator; B fails gracefully there (needs signing, see §3) |
| Test 2 `HeadingBlender` + debug overlay + live threshold tuning | `HeadingBlender.swift`, `DebugView.swift` | 12 unit tests; overlay verified in the simulator |
| Test 3 haptic candidates + blind test | `HapticPatterns.swift`, `HapticTester.swift`, page 4 | Patterns unit-tested (all differ, ≤ 2 s); **feel untested** |
| Log analysis | `scripts/watch/analyze_spike_log.py` | Run on a simulator log |

### The extraction (setup step 1)
Moved into `ThatWayCore` and made `public`: route models (`Route`, `RouteStep`, `TurnShape`, `TurnDir`, …), bearing/distance
maths (`CompassManager`), `TravelMode` + `ModeTuning` + `TravelProfile`, `ContinuousAngle`, plus new `AngleMath`,
`HeadingBlender`, `RouteTracker`, `SyntheticRoute`, `HapticPatterns`. The iOS app compiles against the package and all of its
existing tests pass unchanged, so nothing regressed.
**Not moved (bigger than the spike needs):** `RoutingManager` (progress is entangled with fetching, Combine and published
state), `CompassTilt`, `DeadReckoning`, `CompassHealth`, `LocationProfile`. The watch uses the new `RouteTracker`, which is a
clean, UI-free copy of `RoutingManager`'s windowed nearest-point progress maths. **Follow-up:** make `RoutingManager` use
`RouteTracker` so the logic exists once. Two app-only things stayed in the app: `TravelProfile.baseURL` (reads `Config`).

### The shared look (added after the first version)
The watch app now reuses the iPhone's look instead of drawing its own: `ThatWayUI` (second product of the same package) holds the four theme
palettes, the glow/lift helpers, the Nunito font and the needle/wheel/clock skins, and both apps import it. The iPhone app was switched over
too (its definitions were moved, not copied) and all of its tests still pass. On the watch: tap the compass for the next theme, long-press
for the next needle skin. The font file now ships inside the package and is registered at launch by `ThatWayFonts.register()`.

## 2. Heading blender (Test 2) — design and thresholds to start from
- GPS **course** when speed ≥ **1.5 m/s** and the course is valid (≥ 0, accuracy ≤ 35°, fix ≤ 3 s old); magnetometer when speed
  drops **below 0.8 m/s**. Between 0.8 and 1.5 the current source is kept (hysteresis), and a switch needs the condition to hold
  for **1.0 s** (dwell), so a one-sample spike cannot flip it.
- Circular exponential low-pass, time-constant based: **0.5 s** on course, **0.4 s** on the magnetometer, always the shortest
  arc, so 359°/0° is never crossed the long way. A jump of more than 120° snaps instead of crawling.
- Tuning on the wrist: Debug page → `GPS ≥` and `Mag <` buttons change the thresholds live; the values are written to the log.
- Unit tests cover wraparound, threshold flapping (speed jittering 1.0↔1.6 m/s: zero switches), single-sample spikes,
  invalid / stale / inaccurate course, no-magnetometer, flipped-magnetometer snap, and convergence across north.

## 3. What you need to do once (about 5 minutes)
1. Open `ThatWay.xcodeproj` in Xcode → target **ThatWayWatch** → *Signing & Capabilities*: choose your Team. Xcode creates the
   App ID/profile (the command line can't: it reports "No Accounts"). The HealthKit capability is already in
   `ThatWayWatch.entitlements`. **If Xcode refuses HealthKit on a free (Personal) team**, remove that capability: A still works, B cannot be tested
   and we have our first finding.
2. Watch: Settings → Privacy & Security → Developer Mode on; pair/trust it, then pick it as the run destination and Run.
3. First launch: allow location (While Using), allow Health sharing when option B starts.
Capabilities requested: **location** (both tests), **HealthKit workout** (B only), background modes `location` + `workout-processing`.
Gotcha found while testing: CoreLocation crashes the app if `UIBackgroundModes` doesn't list `location` even on watchOS
(`WKBackgroundModes` alone is not enough). Both keys are declared and A checks first.

## 4. Test protocols
### Test 1 — staying alive wrist-down
Tools (the ⋯ button, then swipe to the Session page) → pick **A · location** → *Start session*. Walk or jog 30 minutes with
the wrist down and the screen off ("Tap each minute" on: you should feel a click every minute if the app is alive). Raise the
wrist a few times; note whether the app is there. Stop. Repeat with **B · workout run** and **B · workout cycle**. Start both
at a similar battery level. The workout is never saved: no workout builder is ever created, so nothing can reach Health.
Record from the log: location and heading updates per 30 s tick (a tick with 0 = silent), battery start/end, thermal state,
scene phases, heartbeats felt vs logged.

### Test 2 — compass while moving
Main screen in Guide mode (Tools, Debug page → *Set test route* builds a route relative to where you stand), jog 10+ minutes in
straight stretches and turns, wrist swinging normally. Log lines carry speed, course, magnetometer, accuracy, source and
filtered heading; the analyser reports the error of the raw magnetometer and of the blended heading against GPS course.

### Test 3 — haptics
Tools, Haptics page: feel each pattern standing still, then **Blind test L/R ×10** while jogging (answer on the buttons), then **all ×20**.
Two candidate sets: `count` (left = 2 clicks, right = 3 clicks, arrive = success, off-route = 2 failure buzzes) and
`direction` (left = 2× directionDown, right = 2× directionUp, arrive = success, off-route = retry·retry·failure).
Run each set; the analyser prints correct/total per set and per event, with what each mistake was confused for.

### Getting the logs to Claude
Plug the watch's paired iPhone in with the cable, then:
`xcrun devicectl device copy from --device <watch-id> --domain-type appDataContainer --domain-identifier com.aadittesting.ThatWay.ThatWay.watchkitapp --source Documents/SpikeLogs --destination <folder>`
(or Xcode → Window → Devices and Simulators → the watch → ThatWayWatch → Download Container). Then:
`python3 scripts/watch/analyze_spike_log.py <folder>`. Logs hold numbers only — never coordinates.

## 5. Pass criteria and results (to fill in)
| # | Criterion | Result |
|---|---|---|
| 1 | Guidance runs 30 min uninterrupted wrist-down | A: ____   B-run: ____   B-cycle: ____ |
| 2 | Needle usable while jogging; logged error vs GPS course | raw magnetometer median/p90: ____ / ____   blended: ____ / ____ |
| 3 | Left/right identified ≥ 9/10 while moving | count set: ____/10   direction set: ____/10 |
| 4 | Battery drop per 30 min | A: ____ %   B-run: ____ %   B-cycle: ____ % |
Recommended session type: ____   Final blender thresholds: ____   Chosen haptic patterns: ____   Unexpected: ____

## 6. What the simulator already showed (limits: no magnetometer, no real wrist, no energy model)
- Session A starts, ticks every 30 s and logs location counts; the analyser reads it. Without a magnetometer the blender stays on
  GPS (100 %), as designed.
- Session B cannot start in an unsigned simulator build ("Missing com.apple.developer.healthkit entitlement"), reported cleanly in the log.
- A crash was found and fixed before it could waste a walk (see the CoreLocation gotcha in §3).

## 7. Risks to watch for on the wrist
- B uses a workout **session without a workout builder**; if watchOS refuses to keep the app running without one, that
  is the first thing to report (the code is a small change: create `associatedWorkoutBuilder()` and call `discardWorkout()`).
- Workout sessions keep the heart-rate sensor on: part of B's battery cost, and a side effect to note (workout indicator on the watch face).
- Wrist-swing magnetometer error while jogging is exactly what Test 2 measures; expect the blended heading to beat it, and watch
  the 0.8–1.5 m/s band (brisk walking) for source switching.
