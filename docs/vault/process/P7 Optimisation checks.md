---
id: p7-optimisation
title: Optimisation checks
type: process
tags: [process, testing, performance]
---
# Optimisation checks

How to find out what a feature costs on the SE 2nd gen in **CPU, memory and battery**, how to write that down so it lands in the [[Feature ledger]], and what counts as a regression. The founding rule from `docs/perf-weekly.md`: **write the prediction before you measure**, so it can be wrong in public.

## What "measured" means here (three levels of evidence)
| Level | Source | Trust | Written in the note as |
|---|---|---|---|
| Prediction | Reasoning, a rule of thumb (one extra compass redraw a second costs about 0.5 to 1 CPU point in the simulator) | Low | `predicted: ...` |
| Simulator | The SE 2nd-gen **simulator**, Release build, `PERF`, 2-minute run | Good for trends and *work counts* (redraws a second); not for energy | `measured (sim): ...` |
| Device | The real SE 2nd gen: trip logs, Xcode Energy gauge, Instruments | The only trusted number for battery | `measured (device): ...` |
Battery can **only** be measured on a device. Do not write `measured` for battery from the simulator.

## Targets (from `docs/perf-links.md`, deliberately unrealistic and to be negotiated with data)
| Metric | Target |
|---|---|
| App CPU while guiding, screen on | 1.5 % of one core at most (the stretch goal is 1 %) |
| Screen off (backgrounded) | 0.3 % at most |
| Main-thread wakeups | 5 a second at most |
| Compass screen redraws | 3 a second at most |
| Needle update gap, 95th percentile | 100 ms at most; shown-position age 1.5 s at most |
| Memory growth over 30 minutes | none (a flat line) |
| Battery, 30-minute screen-on walk | 4 to 8 % (a guess to replace with the first real number); screen locked, audio only: 2 to 4 % |

## A. The simulator harness (CPU, memory, work counts)
Setup, once per session:
1. Use the **iPhone SE (2nd generation)** simulator, one at a time, nothing else heavy running (`sysctl -n vm.loadavg` under about 14).
2. Build **Release** with the `PERF` flag, with the backend gate off so the app opens straight to the compass. **Flip the gate with sed and always restore it** (the repo must keep `backendEnabled = true`):
   ```bash
   sed -i '' 's/static let backendEnabled = true/static let backendEnabled = false/' ThatWay/Config.swift
   xcodebuild -project ThatWay.xcodeproj -scheme ThatWay -configuration Release \
     -destination 'id=<SE2 sim id>' -derivedDataPath /tmp/tw_dd_perf \
     SWIFT_ACTIVE_COMPILATION_CONDITIONS='PERF' build
   sed -i '' 's/static let backendEnabled = false/static let backendEnabled = true/' ThatWay/Config.swift
   grep -n "backendEnabled" ThatWay/Config.swift     # must say true
   ```
3. Use a fresh `-derivedDataPath` every time: the default DerivedData goes stale after package changes.

Link-by-link A/B (2 minutes per case; switch individual features off with `-TW_OFF <link>` and compare):
```bash
python3 scripts/perf/link_test.py --app /tmp/tw_dd_perf/Build/Products/Release-iphonesimulator/ThatWay.app \
    --trip trip.json --out /tmp/links --only dial,cards,deadreckon
python3 scripts/perf/links_report.py /tmp/links docs/perf-links.html     # writes the charts page
```
Links: `loc locprofile tick refresh sched advance arrival eta tilt audio persist deadreckon topbar cards dial dialfx aura anim etarow`. Each result gives `mean.cpu_pct`, `cpu_p95`, `cpu_max` and the redraw counters (`body.compass`, `body.dial`, `routingPublish`, `appPublish` a second).

Long session (memory growth, background):
```bash
python3 scripts/perf/perf_run.py --app <ThatWay.app> --trip trip.json --out /tmp/perf \
    --minutes 30 --fg 10 --modes walk,run,cycle,drive,idle
python3 scripts/perf/summarize.py /tmp/perf
```
It records physical footprint and CPU every interval, snapshots `heap` at start and end (so growth can be traced to a class), runs one simulator per mode, and writes numbers only.
To start a run inside the route-line phase: `scripts/perf/make_tail_trip.py` trims a trip to its last N metres.

**Noise rules.** CPU varies ±0.5 point run to run. Repeat **three times** before believing a difference under 1 point. Trust *work counts* (redraws a second) more than CPU. Do not run two simulators in parallel for CPU numbers.

## B. The device (energy, real heading, real thermals)
1. **Trip logs** (the cheapest and the most realistic): the app samples CPU, memory, battery %, thermal state, screen state, fix and heading counts every 10 s into `Documents/TripLogs`. Retrieve with the commands in [[P6 Live testing]]. Compare trips on the *same route, same start charge, same mode*. One trip is an anecdote.
2. **Xcode Energy gauge:** run from Xcode on the tethered phone (Debug navigator, Energy Impact). Gives a qualitative High/Low and the contribution of CPU, networking and location.
3. **Instruments, Energy Log** (or **Power Profiler**, **Time Profiler**, **Allocations**, **Leaks**): attach to the phone and run 10 minutes of guidance. Time Profiler tells you *where* CPU goes; Allocations plus Leaks proves no growth.
4. **MetricKit:** not collected yet; a candidate for TestFlight (daily battery and hang reports per user).
Battery protocol for a clean number: same route and loop, screen on at auto brightness, start charge noted, no charging, Low Power Mode off, the phone in the same place; compare week to week. The SE's battery health is 73 %, so say it with every figure.

## C. How to measure one feature (the recipe)
1. **Predict** in the weekly log (`docs/perf-weekly.md`): CPU, memory, battery, and why.
2. **Switch it off** with an `-TW_OFF` link, or compare the previous commit, and run the simulator A/B three times each.
3. **Count the work:** did redraws or publishes a second change? That is the most reliable evidence.
4. **Check memory:** footprint at the start and after 2 minutes (`footprint --json <pid>`), and `heap` class counts if it grew.
5. **Device:** include it in the next outing, then compare trip logs against a trip without it.
6. **Write it down:** in the feature note's frontmatter:
   ```yaml
   cpu: "measured (sim): 1.89 % mean on vs 2.44 % off, inside the 0.5 pt noise"
   memory: "measured (sim): +0.0 MB after 2 minutes"
   battery: "measured (device): about 3 % over 30 minutes screen on, 73 % battery health"
   ```
   Allowed prefixes: `measured`, `predicted`, `not measured`, `n/a`. Run `python3 scripts/vault/check_vault.py --fix --write`; the [[Feature ledger]] and [[Performance evidence]] update.

## D. Regression rules (when a change is too expensive)
| Signal | Threshold | Action |
|---|---|---|
| Mean CPU while guiding | up more than 0.5 point (after 3 runs) | Find the link with `link_test.py`; justify or revert |
| Compass redraws a second | up at all without a visible reason | A published write is fanning out ([[redraw-model]]) |
| Resident memory after 2 min | up more than 1 MB | `heap` diff; fix the leak or cap the cache |
| Memory over 30 min | any upward slope | Allocations and Leaks; a leak blocks the release |
| Battery per hour | up more than 1 percentage point (device, same loop) | Remove or gate the feature; add a setting if the user can decide |
| Anything animated | CPU rises while idle | Animations must stop when nothing moves (the aura is already zero in guidance) |
**Never cut an animation permanently to save CPU** without a visual review (the beauty guard in `perf-links.md`); prefer rasterising static layers, throttling, or driving only the dial.

## E. Optimisation hall of fame (what has already worked, so you do not redo it)
- Dial observes the location manager itself: the whole compass screen no longer redraws on every heading change ([[dial-view]], [[redraw-model]]).
- Cards, ETA and the dial take plain `Equatable` values and redraw only when their text changes ([[guidance-cards]]).
- Progress publishes by a 4 m quantum instead of every second ([[route-progress]]).
- The idle tick is 3 s; device orientation notifications are off; two `DateFormatter` builds per read were removed ([[eta]]).
- Heading orientation fixed to portrait ([[heading]]).
The remaining ideas are listed in `docs/perf-weekly.md` under *Candidate optimisations*.

## F. Weekly rhythm
Monday: pick this week's changes, write predictions. Midweek: simulator A/B. Weekend outing: device trip. Sunday: fill *Measured*, update the notes, rerun the checker, commit with the numbers in the message.

Related: [[Performance evidence]], [[perf-harness]], [[trip-log]], [[P8 Before you push or commit]].
