# Link-by-link performance evaluation

Written **before** any measurement, so the predictions can be judged honestly.

## Threshold (deliberately unrealistic, to be negotiated after the data)
Release build, iPhone SE (2nd gen) simulator, 2-minute run, scripted walk, screen on, guidance active:

| metric | target |
|---|---|
| app CPU | <= 1.5 % of one core (was ~5-8 % in the earlier long runs) |
| main-thread wakeups (ticks + location + heading callbacks) | <= 5 / s |
| AppModel published-state changes | <= 4 / s |
| CompassScreen body evaluations | <= 3 / s |
| screen off (backgrounded) | <= 0.3 % CPU |
| **smoothness guard** | needle update gap p95 <= 100 ms; shown-position age p95 <= 1.5 s |
| **beauty guard** | no switch that changes pixels may be kept off without a visual review |

## Predictions (ranked by expected weight)
| # | link | prediction | verdict-to-be |
|---|---|---|---|
| 1 | published-state fan-out (one big AppModel) | biggest hidden cost: every write redraws the whole screen | cut back: split / coalesce |
| 2 | dial 3D + shadows + materials | biggest GPU cost, medium CPU | keep, rasterise static layers |
| 3 | spring animations (needle / tilt / lean) | medium; cost only while values move | keep, retime |
| 4 | route-line canvas + blur | high when visible (not covered here) | keep, cache |
| 5 | location stream | small per fix, but drives everything downstream | keep, already throttled |
| 6 | 1 Hz guidance refresh | small | keep |
| 7 | cards + blur | small-medium | keep |
| 8 | aura animation | zero in guidance now | keep |
| 9 | cosmetic tick | zero in guidance now | keep |
| 10 | scheduler poll | negligible | keep |
| 11 | audio engine idle | negligible after release | keep |
| 12 | heading stream | probably the heaviest sensor link on a real phone | **cannot be measured in the simulator** (no compass) |

Simulator limits: no compass heading, no real GPU/energy numbers. It ranks CPU, wakeups and redraws; the Energy Log on a real iPhone SE confirms the top suspects.

---

# Results (Release, SE 2nd gen simulator, 2-minute runs, scripted walk, guidance on)
Charts and the full table: `docs/perf-links.html`. Raw runs: `scripts/perf/link_test.py` (21 cases, each switched off in turn).
Baseline noise: CPU 1.94 – 2.62 % across three identical runs (±0.35 points), so CPU alone only resolves effects above ~0.7 points. The exact counters (publishes, redraws, wakeups) have no such noise and are the primary evidence.

| link (switched off) | CPU % | AppModel publishes /s | compass redraws /s | observation |
|---|---|---|---|---|
| baseline | 2.2 | 2.19 | 1.10 | already ~1.5 points under the earlier Debug numbers (5-8 %) |
| **tilt stages** | 1.40 | **0.19** | **0.32** | **the finding**: two unguarded @Published writes per second redrew the whole compass screen twice a second for no visible change |
| tick / 1 Hz refresh | 1.4 / 1.6 | 0.19 | 0.10 | same cause (the tilt writes live inside the refresh) |
| location stream | 0.82 | 2.19 | 1.10 | -1.4 points, but it also removes everything downstream; part of this is CoreLocation's own threads |
| location accuracy profile | 2.40 | 2.19 | 1.10 | no CPU saving at all; **fixes were 5.0 s apart with it, 3.0 s without** |
| scheduler, advance, arrival, persist, audio | 1.9 - 2.6 | 2.0 - 2.19 | 1.0 - 1.1 | all inside noise: negligible |
| dial (removed entirely) | 1.88 | 2.19 | 1.10 | -0.3 points: within noise |
| dial effects, springs, aura, cards, top bar, ETA row | 2.1 - 2.5 | 2.19 | 1.10 | all inside noise on the CPU side |
| everything off | 0.33 | 0.00 | 0.00 | the floor: ~1.9 points belong to the chain + UI |
| ETA calculation | 3.45 | 2.19 | 1.10 | **worse** when off: it changes which dial text is shown; confounded, not a saving |

## Verdicts
- **Remove nothing.** No link is both costly and useless. The one real waste was a bug, not a feature.
- **Fixed now:** guard the tilt writes. Re-measured: publishes 2.19 -> 0.26 /s, compass redraws 1.10 -> 0.32 /s, main-thread CPU about -30 %, CPU 2.2 -> ~1.7 % (two runs, 1.44 and 1.89).
- **Predictions vs reality:** #1 (fan-out) confirmed and traced to its source. #2-#4 (dial effects, springs, canvas) could **not** be confirmed or refuted: their cost is GPU/compositor work done outside the app process, which this method cannot see. #5 location: costlier than predicted. #6-#11: negligible as predicted.
- **Smoothness guard FAILS in the simulator:** position age p95 is 5.0 s at walking pace (6 m distance filter), above the 1.5 s target. Cheap cure that costs no battery: dead-reckon the position along the route between fixes (advance by speed x elapsed each refresh) so the cards and needle move smoothly whatever the GPS rate. Not built yet. The simulator's own feed is coarse (3 s even with no filter), so confirm on a device.

## Where to look next (in order)
1. Real-device Energy Log / Metal HUD on the iPhone SE for the render links (dial effects, springs, canvas, blur) — the only way to rank GPU cost.
2. Dead-reckoning between fixes, then re-run the smoothness guard.
3. Route-line canvas and bake: not covered, needs a near-destination scenario (the line only exists within 50-500 m).
4. Heading stream: needs a device (no compass in the simulator).
5. Why the location stream costs ~1.4 points of CPU with one fix per 4 s: likely simulator overhead, check on device.

---

# Round 2: the 1 % limit (agreed: mean app CPU <= 1 %, no run over)
Method change: the first round's probe flushed its JSON every second (rename + fsync = ~17 % of a Time Profiler trace); it now flushes every 15 s. Time Profiler (60 s, walk guidance): main thread 534 ms, of which app logic is small (`AppModel.tick` 23 ms, `refreshGuidanceState` 9 ms, `CompassScreen.body` ~11 ms); the audio IO thread took 186 ms (a cue).

| build / case | runs (mean CPU %) | main thread % |
|---|---|---|
| after tilt-write fix, audio on | 1.35, 1.81, 1.46 | 0.65 - 0.97 |
| same build, **audio cues off** | 0.66, 1.01, 1.01 | 0.61 - 0.95 |
| after replacing the per-cue audio engine with pre-built players + trip-long session | 1.45, 1.55, 1.24 | 0.70 - 0.86 |

Reading: audio cues cost ~0.5 points in this simulator and the player swap did not move it, so most of that cost is the simulator's audio path (host CoreAudio emulation), not our code; unverifiable without a device. With cues off we sit at 0.66 - 1.01 %: two of three runs are at 1.01, i.e. on the line, not under it. Per-second spikes (p95 3 - 8 %, max 8 - 16 %) remain; they coincide with location fixes + whole-screen redraws.
Where the rest is: the compass screen is one big body that re-evaluates (~20 ms) on every published change; ~0.3 evaluations/s x 20 ms ~ 0.6 % of the main thread. **Next structural step:** split `CompassScreen` into small views that each observe only what they show (distance text, dial, cards), so a GPS fix redraws a few views instead of the whole screen. Expected: main thread 0.6 - 0.9 % -> ~0.3 %.
Status against the limit: **not yet met in every run** (audio off: borderline; audio on: ~1.2 - 1.5 % in the simulator).

## Round 3 — dead reckoning (2-minute A/B, SE-2nd-gen simulator, Release, walking track at 1.4 m/s)

| Case | CPU mean | compass redraws/s | dial redraws/s | route publishes/s |
|---|---|---|---|---|
| dead reckoning on (default) | 1.89 % | 0.88 | 0.78 | 1.00 |
| dead reckoning off (`-TW_OFF deadreckon`) | 2.44 % | 0.44 | 0.28 | 0.57 |

The readout now moves every second instead of every fix (fixes are ~5 s apart at walking pace), which is
what roughly doubles redraws. CPU did not get worse in this pair (the "off" run was the noisier one), but
one run each is inside the run-to-run noise (±0.5 point), so this shows "not measurably costly", not "free".
The 1 % limit is still not met in the simulator.
