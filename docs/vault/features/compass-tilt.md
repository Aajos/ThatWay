---
id: compass-tilt
title: Compass tilt algorithm
area: navigation-core
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/CompassTilt.swift
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Compass/DialView.swift
tests:
  - ThatWayTests/CompassTiltTests.swift
manual_checks:
  - Drive/walk a route and watch the lean settle after each turn
depends_on: [route-progress]
tags: [feature, area/navigation-core, status/shipped, risk/low]
---

# Compass tilt algorithm

> The dial leans forward/back in five held steps by how much of the current leg is left, and sideways in two stages (500 m, 200 m) toward the next turn. Stages only ever advance within a leg so GPS jitter cannot flicker the dial.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** low

## What it covers
- 5 front steps (1, .75, .5, .25, 0 of max)
- 2 sideways stages per side; straight/roundabout-straight never lean
- Off / Slight / Hard settings (28/11.5/27 and 45/19/43 degrees)
- Held monotonically per leg (`updateTiltStages`)
- Lean-edge geometry shared with the guide lines

## Depends on
- [[route-progress]] — Route progress tracking

## Used by
- [[dial-view]] — Compass dial and needle
- [[settings-profile]] — Settings and Profile screen

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| CT-1 | A published write per second redraws the whole screen even when unchanged (was the biggest redraw source) | perf harness: `body.compass` counter |
| CT-2 | Stage resets mid-leg and the dial jumps back | test: CompassTiltTests |

## Tests
- `ThatWayTests/CompassTiltTests.swift`

## Manual checks
- Drive/walk a route and watch the lean settle after each turn

## Open items
- none

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
