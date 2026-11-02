---
id: compass-health
title: Compass health, ghost overlay, GPS direction
area: location-sensors
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.8
tier: free
value: 4
release: v1.0
cpu: "predicted: +0 pt (one comparison a second)"
memory: "predicted: under +0.05 MB"
battery: "predicted: about 0"
files:
  - ThatWay/Managers/CompassHealth.swift
  - ThatWay/Compass/CompassGhostOverlay.swift
  - ThatWay/Compass/AppModel.swift
tests:
  - ThatWayTests/CompassHealthTests.swift
manual_checks:
  - Hold the phone sideways while walking: no false alarm in idle; during guidance see whether it cries wolf
depends_on: [heading, location-manager, dial-view, continuous-angle, trip-log]
tags: [feature, area/location-sensors, status/shipped, risk/medium]
---

# Compass health, ghost overlay, GPS direction

> While guiding, compares the compass with the GPS direction of travel on clean samples; a second disagreement shows a ghost compass with Recalibrate (restart heading) and Use GPS direction.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** medium

## What it covers
- Samples only when moving >= 1 m/s on a steady course for 6 s
- Check cadence 1 min, then 3, then 5 on agreement
- One disagreement is re-checked after 10 s; two mark it suspect
- Poor reported accuracy (> 30 degrees) is suspect at once
- Recovery needs two agreements
- Runs only while guiding a trip that has not ended
- GPS-direction mode re-measures its offset while moving and ends when the compass agrees
- Trip log counts suspects, recalibrations, GPS-direction use

## Depends on
- [[heading]] — Heading pipeline
- [[location-manager]] — LocationManager (fixes and permission)
- [[dial-view]] — Compass dial and needle
- [[continuous-angle]] — Continuous angles
- [[trip-log]] — On-device trip log

## Used by
- [[guidance-mode]] — Guidance mode lifecycle

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| CH-1 | False alarm because the phone is held off the walking direction | manual: first real walks; strict cadence mitigates |
| CH-2 | Ran while idle and showed a meaningless warning (was a real bug) | test: theCompassCheckOnlyAppliesWhileGuiding... |
| CH-3 | Restarting the heading service cannot fix a system-level fault | by design: GPS-direction is the real fallback |

## Tests
- `ThatWayTests/CompassHealthTests.swift`

## Manual checks
- Hold the phone sideways while walking: no false alarm in idle; during guidance see whether it cries wolf

## Open items
- Tolerance (20 degrees) and cadence to be tuned from real trip logs.

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-compass-wrong]] — The compass goes wrong
