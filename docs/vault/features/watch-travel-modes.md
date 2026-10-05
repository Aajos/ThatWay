---
id: watch-travel-modes
title: Watch travel modes (walk, run, cycle)
area: watch
status: spike
risk: low
last_verified: 2026-10-05
files:
  - ThatWayCore/Sources/ThatWayCore/TravelMode.swift
  - ThatWayWatch/WatchModel.swift
  - ThatWayWatch/MainView.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchModeTests
manual_checks:
  - Swipe up and down on the watch: Walk, Run, Cycle, wrapping, flash appears
depends_on: [travel-modes, route-tracker, persistence-defaults]
tags: [feature, area/watch, status/spike, risk/low]
---

# Watch travel modes (walk, run, cycle)

> The watch offers Walk, Run and Cycle only: swipe up for the next mode, down for the previous, wrapping. Driving is never offered. The choice persists, tunes the route tracker, and refetches the route when the routing profile changes (cycling needs its own).

**Area:** [[area-watch]] · **Status:** spike · **Risk:** low

## What it covers
- `TravelMode.watchModes`, `isSafeOnWatch`, `onWatch(steps:)` in the shared package
- Persisted as `watchMode`; adopts the phone’s mode when it changes (never Drive)
- Walk and run share the walking route; cycle refetches
- Corridor and arrival radius follow the mode
- Mode flash on screen and a click haptic on every change

## Depends on
- [[travel-modes]]
- [[route-tracker]]
- [[persistence-defaults]]

## Used by
- [[watch-drive-guard]] — Watch drive guard
- [[watch-gestures]] — Watch gestures and controls
- [[watch-voice-search]] — Watch voice destination search

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WTM-1 | A mode change mid-route for cycling leaves the old walking route on screen if the refetch fails | manual: change mode with Airplane Mode on |
| WTM-2 | Swipe ambiguity: a vertical swipe read as horizontal | manual on a real wrist |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchModeTests`

## Manual checks
- Swipe up and down on the watch: Walk, Run, Cycle, wrapping, flash appears

## Open items
- Real-wrist feel of the swipe thresholds.
