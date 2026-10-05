---
id: location-profile
title: Location accuracy profile
area: location-sensors
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/LocationProfile.swift
  - ThatWay/Managers/LocationManager.swift
tests:
  - ThatWayTests/LocationProfileTests.swift
manual_checks:
  - Battery over a long walk vs the baseline in perf-weekly.md
depends_on: [travel-modes]
tags: [feature, area/location-sensors, status/shipped, risk/medium]
---

# Location accuracy profile

> A pure function choosing accuracy, distance filter and heading filter from what the app is doing: mode, guiding, distance to the next turn, stationary, Low Power Mode.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** medium

## What it covers
- Coarser GPS far from a turn, full accuracy inside the mode's precision radius
- Point/idle never need better than 10 m / 100 m
- Stationary (no fix for 20 s) drops accuracy
- Low Power Mode widens filters and coarsens heading
- Applied only when changed

## Depends on
- [[travel-modes]] — Travel modes and tuning

## Used by
- [[dead-reckoning]] — Dead reckoning
- [[location-manager]] — LocationManager (fixes and permission)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| LP-1 | Filter too wide for the mode and turns are announced late | manual: real walks; dead reckoning bounds depend on it |
| LP-2 | Stationary drop never recovers promptly | test: LocationProfileTests |

## Tests
- `ThatWayTests/LocationProfileTests.swift`

## Manual checks
- Battery over a long walk vs the baseline in perf-weekly.md

## Open items
- none

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-mode-change]] — Switching travel mode mid-route
- [[flow-phone-locked]] — Phone locked mid-trip
