---
id: guidance-mode
title: Guidance mode lifecycle
area: navigation-core
status: shipped
risk: high
last_verified: 2026-10-05
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Managers/LocationCheckScheduler.swift
  - ThatWay/Managers/RoutePersistence.swift
tests:
  - ThatWayTests/TravelModeTests.swift
  - ThatWayTests/CompassHealthTests.swift::theCompassCheckOnlyAppliesWhileGuidingATripThatHasNotEnded
manual_checks:
  - Start a trip, END it mid-way: audio stops, screen may lock, no background location indicator
  - Start a trip with no GPS fix: waits, then routes from the real position
depends_on: [route-progress, routing-governor, background-guidance, audio-manager, trip-log, route-persistence, location-issues, compass-health]
tags: [feature, area/navigation-core, status/shipped, risk/high]
---

# Guidance mode lifecycle

> Start/end of a guided trip: flipping the mode, fetching the route, starting the corridor poll and audio, and tearing everything down on END or arrival. Almost every other feature hangs off this lifecycle.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** high

## What it covers
- `startGuidance` / `endGuidance` / `flipMode`
- Route fetch with retries (never routes from a guessed position)
- Location check scheduler start/stop
- Background location + screen-awake switched on/off with the mode
- Trip log begin/end
- Persisted trip saved on route arrival, cleared on end

## Depends on
- [[route-progress]] — Route progress tracking
- [[routing-governor]] — Routing governor
- [[background-guidance]] — Background guidance, scene phases, screen awake
- [[audio-manager]] — Audio manager (tones and voice)
- [[trip-log]] — On-device trip log
- [[route-persistence]] — Trip persistence and restore
- [[location-issues]] — Permission, precision and waiting-for-fix handling
- [[compass-health]] — Compass health, ghost overlay, GPS direction

## Used by
- [[map-tab]] — Map tab and map-tap routing
- [[mode-change-reroute]] — Mid-route mode change
- [[off-route-reroute]] — Off-route detection and reroute

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| GM-1 | END leaves the retry loop or scheduler running (battery drain, phantom reroutes) | manual: END during an offline retry |
| GM-2 | Guidance started before the first real fix routes from the wrong place | manual: cold start; guarded in `fetchRouteAndWait` |
| GM-3 | A fetch outliving an arrival restarts the scheduler | guarded by `!arrived` checks; no automated test |

## Tests
- `ThatWayTests/TravelModeTests.swift`
- `ThatWayTests/CompassHealthTests.swift::theCompassCheckOnlyAppliesWhileGuidingATripThatHasNotEnded`

## Manual checks
- Start a trip, END it mid-way: audio stops, screen may lock, no background location indicator
- Start a trip with no GPS fix: waits, then routes from the real position

## Open items
- `AppModel` is 1,100 lines and owns the whole lifecycle; a candidate for splitting before the app grows.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-arrival]] — Arriving
- [[flow-relaunch-restore]] — Relaunch with a trip in progress
