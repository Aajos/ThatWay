---
id: heading
title: Heading pipeline
area: location-sensors
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/LocationManager.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Turn 360 degrees slowly: needle and ring track, no jumps
depends_on: [location-manager]
tags: [feature, area/location-sensors, status/shipped, risk/medium]
---

# Heading pipeline

> Compass heading from CoreLocation (true north when available), published as plain changes, optionally corrected by GPS direction, turned into dial ring and needle angles.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** medium

## What it covers
- True vs magnetic heading
- Fixed portrait orientation (UI is portrait-only)
- Heading accuracy (negative = invalid, then 0 is used)
- GPS-direction correction while the compass is suspect
- Heading active only while the screen is on

## Depends on
- [[location-manager]] — LocationManager (fixes and permission)

## Used by
- [[compass-health]] — Compass health, ghost overlay, GPS direction
- [[dial-view]] — Compass dial and needle
- [[point-mode]] — Point mode (straight-line pointing)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| HD-1 | The phone's own compass flips 180 degrees or drifts (reproduced in Apple's Compass app, so a sensor/system fault) | compass-health detects it; no code fix possible |
| HD-2 | Heading frozen on screen when nothing republishes | fixed: DialHost observes LocationManager |

## Tests
- none yet

## Manual checks
- Turn 360 degrees slowly: needle and ring track, no jumps

## Open items
- The watch uses `HeadingBlender`; the phone does not (the phone is held, not swung).

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-compass-wrong]] — The compass goes wrong
