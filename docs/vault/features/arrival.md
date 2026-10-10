---
id: arrival
title: Arrival detection and completion
area: navigation-core
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
  - ThatWayTests/DeadReckoningTests.swift::estimateNeverReachesArrival
manual_checks:
  - Walk to a destination: completion appears once, audio stops, screen can lock
depends_on: [route-progress, travel-modes, audio-manager, trip-log, route-persistence]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Arrival detection and completion

> Within the mode's arrival radius of the real destination (checked on the path travelled since the last check, so a fast traveller cannot step over the circle) guidance ends in a completion state that stays on screen until DONE.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- Per-mode arrival radius (5-10 m)
- Path-segment check between consecutive positions
- Real fix only (never the dead-reckoned position)
- Audio finish, scheduler stop, persisted trip cleared, trip log summary written
- Arrived layout with DONE

## Depends on
- [[route-progress]] — Route progress tracking
- [[travel-modes]] — Travel modes and tuning
- [[audio-manager]] — Audio manager (tones and voice)
- [[trip-log]] — On-device trip log
- [[route-persistence]] — Trip persistence and restore

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| AR-1 | Arrival never fires because the radius is smaller than GPS error | manual: real arrival |
| AR-2 | Early arrival from a projected position | test: estimateNeverReachesArrival (arrival uses real fixes only) |

## Tests
- `ThatWayTests/DeadReckoningTests.swift::estimateNeverReachesArrival`

## Manual checks
- Walk to a destination: completion appears once, audio stops, screen can lock

## Open items
- No automated end-to-end arrival test.

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-mode-change]] — Switching travel mode mid-route
- [[flow-arrival]] — Arriving
