---
id: route-tracker
title: Route tracker (shared progress maths)
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
files:
  - ThatWayCore/Sources/ThatWayCore/RouteTracker.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift
manual_checks:
depends_on: [route-models, bearing-math, travel-modes]
tags: [feature, area/watch, status/spike, risk/medium]
---

# Route tracker (shared progress maths)

> A UI-free copy of the route-progress maths in the shared package, used by the watch for distance and turn to the next waypoint. Duplicates logic in `RoutingManager`.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** medium

## What it covers
- Along-route progress, never backward
- Next turn, distance, bearing to next waypoint
- Off-route (mode corridor) and arrival (mode radius)
- Skips pass-through steps ("new name", "continue") so the arrow always refers to a real turn; roundabouts and arrival always count
- Used by the watch for real OSRM routes from voice search

## Depends on
- [[route-models]] — Route models
- [[bearing-math]] — Bearing and distance maths
- [[travel-modes]] — Travel modes and tuning

## Used by
- [[watch-app]] — Watch app UI
- [[watch-travel-modes]] — Watch travel modes (walk, run, cycle)
- [[watch-voice-search]] — Watch voice destination search

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RT-1 | Diverges from `RoutingManager`'s copy | none: known duplicate |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift`

## Manual checks
- none recorded

## Open items
- Make `RoutingManager` use it.

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
