---
id: travel-modes
title: Travel modes and tuning
area: navigation-core
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWayCore/Sources/ThatWayCore/TravelMode.swift
  - ThatWay/Compass/AppModel.swift
tests:
  - ThatWayTests/TravelModeTests.swift
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::routeToolingHandlesTravelModeTuning
manual_checks:
  - Switch mode mid-route: switching card then new route
depends_on: [persistence-defaults, route-models]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Travel modes and tuning

> Walk / Run / Cycle / Drive is the user's manual choice. It selects the routing profile and a table of per-mode thresholds (corridor, poll, reveal distance, arrival radius, GPS filters).

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- Manual, authoritative selection persisted across launches
- Walk and run share the walking profile
- ModeTuning table (11 values per mode)
- Activity type for CoreLocation
- Colour family (on foot green, drive blue)
- Watch subset: `watchModes` (walk, run, cycle) and `isSafeOnWatch` (false for drive)

## Depends on
- [[persistence-defaults]] — Persisted preferences
- [[route-models]] — Route models

## Used by
- [[arrival]] — Arrival detection and completion
- [[audio-cue-plan]] — Audio cue plan, panning, voice script
- [[eta]] — ETA
- [[location-profile]] — Location accuracy profile
- [[mode-change-reroute]] — Mid-route mode change
- [[off-route-reroute]] — Off-route detection and reroute
- [[phone-watch-link]] — iPhone-to-watch link (travel mode)
- [[route-data-generator]] — Guidance line data (bake)
- [[route-line]] — Route line (last stretch)
- [[route-progress]] — Route progress tracking
- [[route-tracker]] — Route tracker (shared progress maths)
- [[travel-mode-carousel]] — Travel-mode carousel
- [[watch-travel-modes]] — Watch travel modes (walk, run, cycle)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| TM-1 | A tuning value changed for one mode silently changes another feature (everything reads the table) | test: driving values pinned in TravelModeTests |
| TM-2 | Walk/run values are first guesses, not yet tuned on foot | manual: real walks |

## Tests
- `ThatWayTests/TravelModeTests.swift`
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::routeToolingHandlesTravelModeTuning`

## Manual checks
- Switch mode mid-route: switching card then new route

## Open items
- Tune walk/run/cycle thresholds from real trip logs.

## Scenarios that pass through it
- [[flow-off-route]] — Wrong turn and reroute
- [[flow-mode-change]] — Switching travel mode mid-route
