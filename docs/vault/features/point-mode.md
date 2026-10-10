---
id: point-mode
title: Point mode (straight-line pointing)
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
  - ThatWay/Compass/DialView.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
  - ThatWayTests/LocationProfileTests.swift
manual_checks:
  - Pick a destination, do not start guidance, turn on the spot: needle tracks the destination
depends_on: [location-manager, heading, dial-view, bearing-math, destination-search]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Point mode (straight-line pointing)

> With a destination chosen but no trip started, the needle points along the straight line to it and the dial shows the distance. No route is fetched, so it is the cheap mode.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- Needle bearing to the destination from the current fix
- Straight-line distance readout in the dial
- Gentler tilt than guidance (60 %)
- Default mode for a newly picked destination (`defaultNavMode`)
- Location profile for 'has destination, not guiding' (10 m accuracy, 10 m filter)

## Depends on
- [[location-manager]] — LocationManager (fixes and permission)
- [[heading]] — Heading pipeline
- [[dial-view]] — Compass dial and needle
- [[bearing-math]] — Bearing and distance maths
- [[destination-search]] — Destination search and recents

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| PM-1 | No GPS fix yet: needle points from the placeholder position (simulator only; on a phone `locationIssue` shows 'Finding your location') | manual: first launch on a phone |
| PM-2 | Needle frozen while idle because nothing republished on a heading change (was a real bug) | manual: turn the phone in idle; guarded by DialHost observing LocationManager |
| PM-3 | Location denied or Precise off: bearing wrong with no explanation | manual: location-issues card |

## Tests
- `ThatWayTests/LocationProfileTests.swift`

## Manual checks
- Pick a destination, do not start guidance, turn on the spot: needle tracks the destination

## Open items
- No automated test of the needle maths in point mode (it lives in `AppModel.needleDeg`).

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-start-guidance]] — Search, pick, start guidance
