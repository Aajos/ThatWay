---
id: route-progress
title: Route progress tracking
area: navigation-core
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-09-15
build: 0.3
tier: free
value: 5
release: v1.0
cpu: "measured (sim): route publishes 1.18 to 0.64 /s; last 450 m (drive) 0.91 % mean"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/RoutingManager.swift
  - ThatWayCore/Sources/ThatWayCore/RouteTracker.swift
tests:
  - ThatWayTests/StepAdvanceTests.swift
  - ThatWayTests/DeadReckoningTests.swift
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift
manual_checks:
depends_on: [route-models, bearing-math, travel-modes]
tags: [feature, area/navigation-core, status/shipped, risk/high]
---

# Route progress tracking

> Where along the route the traveller is, measured in metres along the road, which instruction is current and how far away it is. Never goes backward; windowed nearest-point search stops a looping road from yanking progress to the wrong stretch.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** high

## What it covers
- Windowed nearest-point on the polyline
- `progressAlong` (never backward) and `fixedProgress` (last real fix)
- Current card index, distance to the next card, leg fraction
- Dead-reckoned extra metres applied on top (clamped before the next manoeuvre and the arrival radius)
- Quantised publishing (4 m / card change / real fix)

## Depends on
- [[route-models]] — Route models
- [[bearing-math]] — Bearing and distance maths
- [[travel-modes]] — Travel modes and tuning

## Used by
- [[arrival]] — Arrival detection and completion
- [[audio-cue-plan]] — Audio cue plan, panning, voice script
- [[compass-tilt]] — Compass tilt algorithm
- [[dead-reckoning]] — Dead reckoning
- [[eta]] — ETA
- [[guidance-cards]] — Guidance cards
- [[guidance-mode]] — Guidance mode lifecycle
- [[map-tab]] — Map tab and map-tap routing
- [[off-route-reroute]] — Off-route detection and reroute
- [[route-data-generator]] — Guidance line data (bake)
- [[route-line]] — Route line (last stretch)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RP-1 | Progress jumps to a different stretch of a road that loops near itself | partly: windowing; no loop-route test |
| RP-2 | Estimate carries progress past a turn and the card flips forward then back | test: DeadReckoningRouteTests.estimateStopsShortOfTheNextManoeuvre |
| RP-3 | Two copies of the progress maths (`RoutingManager`, `RouteTracker`) drift apart | none: known duplicate |

## Tests
- `ThatWayTests/StepAdvanceTests.swift`
- `ThatWayTests/DeadReckoningTests.swift`
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift`

## Manual checks
- none recorded

## Open items
- Fold `RoutingManager` onto `RouteTracker` so the maths exists once.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-off-route]] — Wrong turn and reroute
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-offline-midroute]] — Losing the connection mid-trip
- [[flow-relaunch-restore]] — Relaunch with a trip in progress
