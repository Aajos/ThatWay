---
id: route-models
title: Route models
area: shared-modules
status: shipped
risk: high
last_verified: 2026-10-05
files:
  - ThatWayCore/Sources/ThatWayCore/RouteModels.swift
tests:
  - ThatWayTests/OSRMParsingTests.swift
  - ThatWayTests/StepAdvanceTests.swift
manual_checks:
depends_on: [core-package]
tags: [feature, area/shared-modules, status/shipped, risk/high]
---

# Route models

> The app's own route types (Route, RouteStep, TurnShape, intersections) and the Codable coordinate. Nothing outside the OSRM provider knows OSRM exists. Shared with the watch.

**Area:** [[area-shared-modules]] · **Status:** shipped · **Risk:** high

## What it covers
- Route / RouteStep with along-route distances and indices
- TurnShape / TurnDir / ManeuverKind
- Codable CLLocationCoordinate2D
- Public memberwise initialisers

## Depends on
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)

## Used by
- [[route-persistence]] — Trip persistence and restore
- [[route-progress]] — Route progress tracking
- [[route-tracker]] — Route tracker (shared progress maths)
- [[routing-provider-seam]] — Routing provider seam (OSRM + fallback)
- [[synthetic-route]] — Synthetic test route
- [[travel-modes]] — Travel modes and tuning

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RM-1 | A field added without updating the public init, the OSRM parser, persistence and fixtures | build fails (good) or decoding of an old saved trip fails silently |
| RM-2 | Saved trips from an older app version fail to decode | none: no versioned migration |

## Tests
- `ThatWayTests/OSRMParsingTests.swift`
- `ThatWayTests/StepAdvanceTests.swift`

## Manual checks
- none recorded

## Open items
- Persisted trips have no schema version.
