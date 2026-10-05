---
id: bearing-math
title: Bearing and distance maths
area: shared-modules
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWayCore/Sources/ThatWayCore/CompassManager.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift
manual_checks:
depends_on: [core-package]
tags: [feature, area/shared-modules, status/shipped, risk/medium]
---

# Bearing and distance maths

> Great-circle bearing and distance, nearest point on a polyline, relative bearing, point-along-route. Used by every feature that points or measures.

**Area:** [[area-shared-modules]] · **Status:** shipped · **Risk:** medium

## What it covers
- Bearing normalised to 0-360
- Distance via CLLocation
- Nearest point with segment index (flat-earth projection)
- Relative bearing in (-180, 180]
- Compass-point labels, distance formatting

## Depends on
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)

## Used by
- [[point-mode]] — Point mode (straight-line pointing)
- [[route-progress]] — Route progress tracking
- [[route-tracker]] — Route tracker (shared progress maths)
- [[watch-voice-search]] — Watch voice destination search

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| BM-1 | Flat-earth projection is wrong over very long segments | partly: routes are finely sampled |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift`

## Manual checks
- none recorded

## Open items
- No direct unit tests for bearing/nearestPoint (covered indirectly).
