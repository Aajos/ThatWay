---
id: route-persistence
title: Trip persistence and restore
area: routing
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/RoutePersistence.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Kill the app mid-trip and relaunch: guidance resumes
depends_on: [route-models]
tags: [feature, area/routing, status/shipped, risk/medium]
---

# Trip persistence and restore

> The active route, destination and profile are saved when the route lands and restored on launch, without any network call.

**Area:** [[area-routing]] · **Status:** shipped · **Risk:** medium

## What it covers
- Save after a route fetch
- Restore on launch straight into guidance
- Cleared on END and arrival
- Stored in Application Support, not Documents (not user-visible)

## Depends on
- [[route-models]] — Route models

## Used by
- [[arrival]] — Arrival detection and completion
- [[guidance-mode]] — Guidance mode lifecycle

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RP-A | Restored trip no longer matches where the traveller is | partly: corridor check reroutes |
| RP-B | Schema change breaks old saved trips | none |

## Tests
- none yet

## Manual checks
- Kill the app mid-trip and relaunch: guidance resumes

## Open items
- Add a schema version.

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-off-route]] — Wrong turn and reroute
- [[flow-arrival]] — Arriving
- [[flow-relaunch-restore]] — Relaunch with a trip in progress
