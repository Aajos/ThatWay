---
id: location-issues
title: Permission, precision and waiting-for-fix handling
area: location-sensors
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 4
release: v1.0
cpu: "predicted: 0"
memory: "predicted: under +0.05 MB"
battery: "predicted: 0"
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Compass/CompassScreen.swift
  - ThatWay/Managers/LocationManager.swift
tests:
manual_checks:
  - Fresh install: allow, deny and Precise-off paths each show the right card
depends_on: [location-manager]
tags: [feature, area/location-sensors, status/shipped, risk/medium]
---

# Permission, precision and waiting-for-fix handling

> Says so on screen when location is denied, Precise is off, or guidance is waiting for its first fix, and never routes from a guessed position on a real phone.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** medium

## What it covers
- `locationIssue` (denied, reducedAccuracy, searching)
- Settings button on the card
- Route fetch waits for the first real fix (simulator keeps a placeholder)
- Republish on authorisation / precision change

## Depends on
- [[location-manager]] — LocationManager (fixes and permission)

## Used by
- [[guidance-mode]] — Guidance mode lifecycle

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| LI-1 | Routes from the placeholder address when no fix exists (was a real bug) | manual: fixed for devices |
| LI-2 | Wait loop never ends if permission is denied | ends when guidance ends or destination changes; manual |

## Tests
- none yet

## Manual checks
- Fresh install: allow, deny and Precise-off paths each show the right card

## Open items
- No unit test: needs an injectable location source.

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-start-guidance]] — Search, pick, start guidance
