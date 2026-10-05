---
id: watch-session
title: Watch wrist-down session (A/B)
area: watch
status: spike
risk: high
last_verified: 2026-10-05
files:
  - ThatWayWatch/SessionController.swift
  - ThatWayWatch/Info.plist
  - ThatWayWatch/ThatWayWatch.entitlements
  - ThatWayWatch/SessionView.swift
tests:
manual_checks:
  - 30 minutes wrist-down per option; battery drop per 30 min
depends_on: [watch-spike-log]
tags: [feature, area/watch, status/spike, risk/high]
---

# Watch wrist-down session (A/B)

> Keeps the app running with the wrist down: A = background location session (`allowsBackgroundLocationUpdates` + CLBackgroundActivitySession), B = HKWorkoutSession (no builder, never saved to Health). Logs a tick every 30 s.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** high

## What it covers
- Both modes behind a switch
- Both `UIBackgroundModes` and `WKBackgroundModes` declared
- Guard against CoreLocation's assertion
- 30 s ticks, scene-phase log, optional minute heartbeat
- Refuses to start while the drive guard is active

## Depends on
- [[watch-spike-log]] — Watch spike log and analysis

## Used by
- [[watch-app]] — Watch app UI
- [[watch-drive-guard]] — Watch drive guard

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WS-1 | CoreLocation asserts if `location` is missing from `UIBackgroundModes` (found and guarded) | found in the simulator |
| WS-2 | HealthKit capability refused on a free team | manual: Xcode signing |
| WS-3 | Workout without a builder may not keep the app alive | manual: first thing to check |

## Tests
- none yet

## Manual checks
- 30 minutes wrist-down per option; battery drop per 30 min

## Open items
- All three on-wrist measurements.

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
