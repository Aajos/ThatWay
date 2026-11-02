---
id: dead-reckoning
title: Dead reckoning
area: navigation-core
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 3
release: v1.0
cpu: "measured (sim): 1.89 % mean on vs 2.44 % off, inside the ±0.5 pt noise; predicted +0 to +0.7 pt"
memory: "predicted: under +0.1 MB"
battery: "predicted: +0 to +1 %/h (device, not yet measured)"
files:
  - ThatWay/Managers/DeadReckoning.swift
  - ThatWay/Managers/RoutingManager.swift
  - ThatWay/Compass/AppModel.swift
tests:
  - ThatWayTests/DeadReckoningTests.swift
manual_checks:
  - Walk with the screen on: the distance counts down between fixes
depends_on: [route-progress, location-manager, location-profile]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Dead reckoning

> Between GPS fixes, progress along the route is advanced at the last measured speed so distances, ETA, needle bearing and audio cues move smoothly. Strictly bounded and display-only.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- Needs speed >= 0.7 m/s and a course within 60 degrees of the route
- At most 6 s of travel and one distance-filter's worth of metres
- Held short of the next manoeuvre and of the arrival radius
- Real fix replaces the estimate
- Lateral offset preserved for the needle bearing
- Off-route and arrival use the real fix only

## Depends on
- [[route-progress]] — Route progress tracking
- [[location-manager]] — LocationManager (fixes and permission)
- [[location-profile]] — Location accuracy profile

## Used by
- [[audio-cue-plan]] — Audio cue plan, panning, voice script

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| DR-1 | Stopped traveller 'walks on' because no fix arrives while still | test: neverMoreThanTheDistanceFilterOrSixSeconds |
| DR-2 | Extra redraws from per-second progress changes | perf: quantised publishing; harness `routingPublish` |

## Tests
- `ThatWayTests/DeadReckoningTests.swift`

## Manual checks
- Walk with the screen on: the distance counts down between fixes

## Open items
- none

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
