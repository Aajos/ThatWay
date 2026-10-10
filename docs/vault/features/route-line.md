---
id: route-line
title: Route line (last stretch)
area: guidance-ui
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-09-19
build: 0.5
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/GuidanceLineView.swift
  - ThatWay/Managers/RouteDataGenerator.swift
tests:
manual_checks:
  - Approach a destination: line appears at the reveal distance and follows the road
depends_on: [route-data-generator, travel-modes, route-progress]
tags: [feature, area/guidance-ui, status/shipped, risk/medium]
---

# Route line (last stretch)

> Inside the mode's reveal distance of the destination the real route line is drawn with look-ahead, side-branch markers and a ribbon, from data baked once for just that stretch.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** medium

## What it covers
- Reveal distance per mode (50-500 m)
- Bake once when due, cleared on reroute/mode change
- Speed-based look-ahead
- Node spacing throttle per mode
- Ribbon colour by mode

## Depends on
- [[route-data-generator]] — Guidance line data (bake)
- [[travel-modes]] — Travel modes and tuning
- [[route-progress]] — Route progress tracking

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RL-1 | Heavy canvas redraw cost near the destination | perf: last-450 m scenario measured 0.91 % CPU |
| RL-2 | Line drawn from a coarse position (poll cadence) | by design: reads the polled snapshot |

## Tests
- none yet

## Manual checks
- Approach a destination: line appears at the reveal distance and follows the road

## Open items
- No automated test; geometry is large (911 lines).

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-mode-change]] — Switching travel mode mid-route
