---
id: route-data-generator
title: Guidance line data (bake)
area: routing
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/RouteDataGenerator.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Reroute inside the reveal distance: line redraws for the new route
depends_on: [route-progress, travel-modes]
tags: [feature, area/routing, status/shipped, risk/medium]
---

# Guidance line data (bake)

> Turns just the final stretch of the route into drawable line data (nodes, side branches, spacing) once, when the line is due; cleared on reroute and mode change.

**Area:** [[area-routing]] · **Status:** shipped · **Risk:** medium

## What it covers
- Bake gate by reveal distance
- Per-mode node spacing
- Cleared when the route changes
- Not baked while arrived

## Depends on
- [[route-progress]] — Route progress tracking
- [[travel-modes]] — Travel modes and tuning

## Used by
- [[route-line]] — Route line (last stretch)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RD-1 | Bake runs for a route that is about to be replaced | guard: skipped when arrived/rerouting |

## Tests
- none yet

## Manual checks
- Reroute inside the reveal distance: line redraws for the new route

## Open items
- none

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-off-route]] — Wrong turn and reroute
