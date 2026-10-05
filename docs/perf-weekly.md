# Weekly performance log

Started 2026-10-05. One entry per week: what changed, what we **predicted** it would cost in memory,
battery and CPU, and (filled in at the weekly test) what it actually cost. Predictions are written
*before* measuring so they can be wrong in public.

Target carried over from `perf-links.md`: **mean CPU ≤ 1 % while guiding** (SE-2nd-gen simulator,
Release build, 2-minute run), no per-second burst that visibly drops frames.

## How each number is obtained

| Metric | Method | Caveat |
|---|---|---|
| CPU | `scripts/perf/link_test.py` — 2-minute run on one SE-2nd-gen simulator, Release + `PERF`, walking track at 1.4 m/s; read `mean.cpu_pct`, `cpu_p95`, `cpu_max` | Simulator CPU ≠ device CPU. Run-to-run noise is about ±0.5 point; repeat 3× before believing a difference under 1 point. |
| Redraws | same run: `body.compass`, `body.dial`, `routingPublish`, `appPublish` per second | The most reliable number: it counts work, not time. |
| Memory | `footprint --json <pid>` after 2 minutes, plus `heap <pid>` class counts, simulator and (when possible) device | Compare *resident dirty* size, not virtual. |
| Battery | **Device only.** Same 30-minute outdoor loop on the iPhone SE, full-brightness-off (auto), screen on, same mode, same start charge; read Settings → Battery (% used) and, tethered, Xcode → Energy gauge | The simulator has no energy model. One loop is anecdote; compare week to week on the *same route*. |

Baseline to beat (Release / SE sim, last measured 2026-10-05, guiding, audio tones on):

| | CPU mean | CPU p95 | compass redraws/s | dial redraws/s | route publishes/s |
|---|---|---|---|---|---|
| Needle sway restored, no dead reckoning | 1.19 – 1.63 % | 3.5 – 6.8 % | 0.32 | 0.22 | 0.26 |
| + dead reckoning (default) | 1.89 % | 5.0 % | 0.88 | 0.78 | 1.00 |

Rule of thumb from earlier rounds (`perf-links.md`): **one extra compass redraw per second costs
roughly 0.5 – 1 CPU point in the simulator**, because each `@Published` write re-evaluates the whole
compass screen. Predictions below use that, and say so.

---

## Week of 2026-10-05

### Changes

1. **Dead reckoning** (`DeadReckoning.swift`, `RoutingManager.projectedProgress`, `AppModel.updateProjection`).
   Between GPS fixes the distance to the next turn, ETA, needle bearing and audio cues advance at the last
   measured speed (capped at 6 s and one distance-filter's worth of metres, held short of the next turn and
   of arrival). Display-only: off-route detection and arrival use the real fix. Switch off for tests with
   `-TW_OFF deadreckon`.
2. **Idle-needle fix** (`AppModel.init`, `locationDidUpdate`). Compass heading was no longer republished
   to the UI after the earlier redraw reduction, so the idle/Point-mode needle froze (guidance hid it with
   its 1 Hz refresh). Heading now republishes at most 10×/s, and a new GPS fix republishes when not guiding.
3. **Location-problem card** (`AppModel.locationIssue`, `CompassScreen.locationIssueCard`): denied
   permission, Precise Location off, and "Finding your location…" are shown instead of failing silently.
4. **Temporary full-accuracy request** (`LocationManager.updateAccuracyAuthorization`), once per launch,
   when Precise Location is off.
5. **Real-origin routing** (`AppModel.fetchRouteAndWait`): on a device, never route from the placeholder
   position; wait (0.5 s sleeps) for the first real fix.
6. **Screen stays on while guiding** (`AppModel.updateScreenAwake`): `isIdleTimerDisabled` while guiding,
   not arrived, and the app is in the foreground.

### Predictions (written before measuring)

| # | Change | CPU (sim, mean) | Memory | Battery (device) | Why |
|---|---|---|---|---|---|
| 1 | Dead reckoning | **+0 to +0.7 pt** while moving; 0 when still (it needs speed ≥ 0.7 m/s) | **< +0.1 MB**; no new allocations that persist (one `Double` and a binary search per second) | **+0 to +1 %/h** — not the GPS (same fix rate), only ~0.6 extra compass redraws/s | Measured 2026-10-05: compass redraws 0.44→0.88/s, dial 0.28→0.78/s; CPU 1.89 % on vs 2.44 % off, inside the noise. Rule of thumb gives +0.3–0.6 pt. |
| 2 | Idle-needle heading republish | **+0.5 to +2.5 pt** in idle/Point while the phone is moving; ≈ 0 when held still. Worst case 10 redraws/s ≈ +5 pt for the seconds you are actively turning | none | **+0.5 to +2 %/h**, only while the app is open in Point/idle | Heading filter is 2–3°, so a steady walk gives roughly 1–4 heading updates/s, each a full compass-screen redraw (rule of thumb). **Not measurable in the simulator (no heading)** — device only. This is the most likely item to push us further from 1 %. |
| 3 | Location-problem card | 0 (a card that only exists in a fault state) | < +0.05 MB | 0 | — |
| 4 | Full-accuracy request | 0 (one system prompt, once) | 0 | 0 — but it *raises* GPS quality for users who had Precise off, which costs a normal GPS's power | — |
| 5 | Real-origin wait loop | ≈ 0: at most a 2 Hz sleep loop, only while guidance was started with no fix yet | 0 | 0 | Loop ends at the first fix. |
| 6 | Screen stays on | **0 CPU** | 0 | **+8 to +20 %/h vs. letting the screen lock**, dominant of everything this week. Roughly: display on is the largest single draw on an SE-class phone; locking it and navigating by audio is the cheapest mode this app has. Un-measured estimate, device only. | Biggest decision of the week; see "Open question" below. |

**Predicted net for the week (guiding, simulator):** mean CPU **≈ 1.7 – 2.4 %** (still above the 1 % target),
memory **unchanged within ±1 MB**, device battery **dominated by #6**, i.e. a 30-minute screen-on walk should cost
the same as before plus whatever the screen was previously off for.

### Open question carried to next week
`isIdleTimerDisabled` is a default I chose, not something agreed. If the weekly device test shows the
battery cost is too high, the options are: a Settings toggle (default on/off), or keep the screen on only
inside the last ~200 m of a turn, or rely on audio + lock screen (already supported via the `audio` and
`location` background modes).

### To fill in at the weekly test (2026-10-12)

| | Predicted | Measured | Verdict |
|---|---|---|---|
| CPU mean, guiding, DR on (sim, 3 runs) | 1.7 – 2.4 % | | |
| CPU mean, guiding, DR off (sim, 3 runs) | 1.3 – 1.8 % | | |
| Compass redraws/s, guiding | ≈ 0.9 | | |
| Compass redraws/s, idle phone moving (device) | 1 – 4 | | |
| Resident memory after 2 min (sim) | baseline ± 1 MB | | |
| Battery, 30-min loop, screen on (device) | 4 – 8 % | | |
| Battery, same loop, screen locked, audio only (device) | 2 – 4 % | | |
| Idle needle follows a 90° turn within 0.3 s (device) | yes | | |

(The two battery rows are rough guesses to be replaced by the first real measurement; treat the first week
as establishing the baseline rather than judging it.)

### Candidate optimisations to test next (not done yet)

- Split `GuidanceCardStack` / `NextCardsStack` / ETA row to value-driven `Equatable` inputs (only the dial is
  split today). Expected: −0.3 to −0.6 pt, which is what brings 1 % within reach.
- Throttle idle heading redraws to the *dial only* (a `TimelineView`/CA-driven rotation) instead of the whole
  screen. Expected: removes most of #2's cost.
- Publish the dead-reckoned readout every 2 s instead of every 1 s. Expected: −0.2 to −0.4 pt, at the cost
  of a visibly steppier countdown at walking pace.

---

## Week of 2026-10-05, second batch (search fix, compass health, card split, clean-ups)

### Changes

1. **Search layout** (`CompassScreen`): the whole screen now ignores the keyboard (it used to shrink the layout
   area by the keyboard's height and push everything down); the top pills hide while searching; results scroll
   above the keyboard (`keyboardWillChangeFrame` → bottom padding). Zero cost outside search.
2. **Heading orientation fixed to portrait** (`LocationManager`). It used to follow the phone's physical orientation,
   which can swing the heading 90°/180° when the phone is tipped. *This is not the cause of the flips the user
   saw (Apple's own Compass app shows them too, so the sensor or its system calibration is at fault).* It does
   remove a source of error and the device-orientation notifications.
3. **Compass health** (`CompassHealth`, `AppModel.updateCompassHealth`, `CompassGhostOverlay`). Compares the compass
   with the GPS direction of travel on clean samples only (≥ 1 m/s, course steady for 6 s): checks after 1, then 3,
   then 5 minutes while it agrees; a disagreement is re-checked after 10 s and only a second one marks it suspect;
   heading accuracy worse than 30° is suspect at once. While suspect: a ghost compass (north marked at the GPS
   direction), **Recalibrate compass** (restarts the heading service — iOS exposes no way to reset the magnetometer)
   and **Use GPS direction** (steers the dial by GPS course, offset re-measured while moving; ends when the compass
   agrees again). Check cost: one comparison a second, only while the screen is on.
4. **Heading redraws moved off the whole screen** (`DialHost`): the dial observes the location manager itself, so a
   heading change re-evaluates only the dial. This replaces last week's forward-everything fix (prediction #2 above).
5. **Card split**: `GuidanceCardStack`, `NextCardsStack`, `PeekCard` take plain values (`GuidanceStackState`,
   `NextStackState`, `CardFace`) and are `Equatable`; they redraw only when card text changed.
6. **Progress publishes by quantum**: `RoutingManager.progressAlong` is no longer `@Published`; it announces itself
   on a real fix, a card change, or every 4 m of dead-reckoned movement.
7. **Clean-ups of older code**: `ETAManager` built two `DateFormatter`s on every read (several reads per redraw) and
   published two values nobody observed each second; the idle tick is 3 s instead of 1 s; device-orientation
   notifications are off.

### Measured (Release, SE-2nd-gen simulator, 2-minute runs, one run each — noise ±0.5 pt in CPU)

| Scenario | Build | CPU mean | CPU p95 | compass redraws/s | dial redraws/s | cards redraws/s | route publishes/s |
|---|---|---|---|---|---|---|---|
| Full trip, walk | last week's commit | 2.74 % | 10.8 % | 1.06 | 0.96 | – | 1.18 |
| Full trip, walk | + dial/card split, clean-ups | 1.51 % | 4.1 % | 0.98 | 0.27 | 0.31 | 1.10 |
| Full trip, walk | + progress quantum | 2.09 % (machine busier, load 158) | 6.4 % | **0.56** | 0.27 | 0.31 | **0.64** |
| Last 450 m (route line drawn), drive | last week's commit | 1.38 % | 5.4 % | 1.29 | 0.97 | – | 1.63 |
| Last 450 m, drive | + dial/card split, clean-ups | 1.27 % | 3.8 % | 1.30 | 0.16 | 0.41 | 1.63 |
| Last 450 m, drive | + progress quantum | **0.91 %** | 3.7 % | **0.68** | 0.17 | 0.39 | 0.99 |

Reading it: the *work counts* are the trustworthy column. Dial redraws fell ~75–85 %, compass-screen redraws fell
~40–50 %, and the last-450 m scenario (the route line phase, not measured before) is under the 1 % target for the first
time. The full-trip CPU figure is noisy across runs (1.5 – 2.1 % for essentially the same code); it needs three runs
before a verdict. Heading redraws (item 4) cannot be measured in the simulator — device only.

### Predicted vs. measured for last week's open items

| Item | Predicted | Result |
|---|---|---|
| Card/ETA split | −0.3 to −0.6 pt | Dial split alone ≈ −0.3 to −1.2 pt depending on run; cards redraw 0.3–0.4/s instead of ~1/s |
| Idle heading cost (#2) | +0.5 to +2.5 pt | Replaced by dial-only redraw (item 4); expected back to ≈ +0.1–0.4 pt. Verify on the phone |
| Dead-reckoned readout every 2 s | −0.2 to −0.4 pt | Superseded by the 4 m quantum (equivalent saving, no visible stepping) |

### Predictions for this batch (to verify on 2026-10-12)

| Change | CPU | Memory | Battery (device) |
|---|---|---|---|
| Compass health check | +0 pt (one comparison/s, no allocation beyond a ≤ 8-sample array) | < +0.05 MB | ≈ 0 |
| Ghost overlay (only while suspect) | +0.1 – 0.3 pt while shown (dashed ring + blur-free fill) | < +0.1 MB | ≈ 0 |
| Recalibrate (heading restart) | one-off | 0 | one-off, negligible |
| Heading to dial only | −0.5 to −2 pt vs last week's idle forward | 0 | −0.5 to −2 %/h in Point/idle |
| Progress quantum + card split | −0.2 to −0.6 pt guiding | 0 | −0.5 to −1 %/h guiding |
| 3 s idle tick | −0.05 pt | 0 | < −0.2 %/h idle |
| Search layout | 0 | 0 | 0 |

### Test tools added
`scripts/perf/make_tail_trip.py` trims a trip to its last N metres so a run starts inside the route-line reveal
zone; `link_test.py` gained a `deadreckon` link. `-TW_GHOST` (PERF builds only) forces the compass-warning overlay
so it can be inspected in the simulator.
