---
id: location-manager
title: LocationManager (fixes and permission)
area: location-sensors
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 5
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/LocationManager.swift
tests:
  - ThatWayTests/LocationProfileTests.swift
manual_checks:
  - "Deny location: the card says so; allow Precise off: card plus system prompt"
depends_on: [location-profile]
tags: [feature, area/location-sensors, status/shipped, risk/high]
---

# LocationManager (fixes and permission)

> Wraps CoreLocation: authorisation, GPS fixes, compass heading, accuracy authorisation (Precise on/off), background flags, counters for the test log. The single source of 'where am I'.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** high

## What it covers
- When-In-Use authorisation (no Always)
- Fix delivery with only-changed published writes
- Heading with fixed portrait orientation
- `restartHeading()` (stop, dismiss calibration, start)
- Precise Location detection + one temporary full-accuracy request per launch
- Fix and heading counters for the trip log
- Background guidance flags (`allowsBackgroundLocationUpdates`, indicator)

## Depends on
- [[location-profile]] — Location accuracy profile

## Used by
- [[background-guidance]] — Background guidance, scene phases, screen awake
- [[compass-health]] — Compass health, ghost overlay, GPS direction
- [[dead-reckoning]] — Dead reckoning
- [[destination-search]] — Destination search and recents
- [[heading]] — Heading pipeline
- [[location-issues]] — Permission, precision and waiting-for-fix handling
- [[point-mode]] — Point mode (straight-line pointing)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| LM-1 | Every published write redraws the screen even when unchanged | perf harness counters; writes are guarded |
| LM-2 | Heading orientation followed the physical orientation and could flip the compass (was changed to portrait) | manual |
| LM-3 | Approximate location gives kilometre-scale fixes | manual: reduced-accuracy card |

## Tests
- `ThatWayTests/LocationProfileTests.swift`

## Manual checks
- Deny location: the card says so; allow Precise off: card plus system prompt

## Open items
- Only `LocationProfile` is unit-tested; delegate behaviour needs a device.

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-compass-wrong]] — The compass goes wrong
