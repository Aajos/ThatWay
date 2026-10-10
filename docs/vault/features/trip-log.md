---
id: trip-log
title: On-device trip log
area: power-performance
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.9
tier: internal
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/TripLog.swift
  - ThatWay/Compass/ProfileScreen.swift
  - docs/test-logs.md
tests:
  - ThatWayTests/TripLogTests.swift
manual_checks:
  - Walk with the phone locked, share the log
depends_on: [persistence-defaults]
tags: [feature, area/power-performance, status/shipped, risk/low]
---

# On-device trip log

> Numbers-only JSON-lines log of every guided trip (CPU, memory, battery, thermal, network, counters, events) with a summary, shareable from Profile or copied over a cable.

**Area:** [[area-power-performance]] · **Status:** shipped · **Risk:** low

## What it covers
- Sample every 10 s incl. screen locked
- Events: reroute, mode change, screen on/off, failures, compass warnings
- Never coordinates, places or route shapes
- Keeps the newest 60 trips; Share / Clear
- Visible in the Files app

## Depends on
- [[persistence-defaults]] — Persisted preferences

## Used by
- [[arrival]] — Arrival detection and completion
- [[compass-health]] — Compass health, ghost overlay, GPS direction
- [[guidance-mode]] — Guidance mode lifecycle
- [[settings-profile]] — Settings and Profile screen

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| TL-1 | A log line accidentally includes a location or name | test: logsNeverContainCoordinatesOrNames |
| TL-2 | Device-wide network bytes misread as the app's own | documented caveat |

## Tests
- `ThatWayTests/TripLogTests.swift`

## Manual checks
- Walk with the phone locked, share the log

## Open items
- MetricKit daily report not collected.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-offline-midroute]] — Losing the connection mid-trip
- [[flow-arrival]] — Arriving
- [[flow-compass-wrong]] — The compass goes wrong
- [[flow-relaunch-restore]] — Relaunch with a trip in progress
