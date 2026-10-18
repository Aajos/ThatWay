---
id: eta
title: ETA
area: navigation-core
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-09-23
build: 0.6
tier: free
value: 3
release: v1.0
cpu: "not measured (removed two DateFormatter builds per read)"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/ETAManager.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
manual_checks:
  - Compare ETA with a known route over a 10-minute walk
depends_on: [route-progress, travel-modes]
tags: [feature, area/navigation-core, status/shipped, risk/low]
---

# ETA

> Arrival time from road-class speeds (driving) or 1.4 m/s (on foot) from the traveller's position to the end, scaled by a smoothed ratio of actual to expected pace.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** low

## What it covers
- Per-segment duration sum from OSRM annotations
- Pace factor learned only while moving (> 1.5 m/s), clamped 0.7-1.8
- Cached date formatters
- Arrival clock under the dial, minutes-left in the ETA pill

## Depends on
- [[route-progress]] — Route progress tracking
- [[travel-modes]] — Travel modes and tuning

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| ETA-1 | A red light or stop inflates the pace factor and the ETA jumps | partly: smoothing 0.97/0.03; manual |
| ETA-2 | Walking ETA used for cycling/running | known: only driving uses road data |

## Tests
- none yet

## Manual checks
- Compare ETA with a known route over a 10-minute walk

## Open items
- No unit tests for `ETAManager`.

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
