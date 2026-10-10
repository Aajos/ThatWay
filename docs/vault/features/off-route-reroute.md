---
id: off-route-reroute
title: Off-route detection and reroute
area: navigation-core
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-09-17
build: 0.4
tier: free
value: 5
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Managers/RoutingManager.swift
  - ThatWay/Managers/LocationCheckScheduler.swift
tests:
  - ThatWayTests/RoutingGovernorPolicyTests.swift
  - ThatWayTests/TravelModeTests.swift
manual_checks:
  - Take a wrong turn on purpose: reroute within one poll, no flicker of cards
depends_on: [route-progress, routing-governor, travel-modes, guidance-mode]
tags: [feature, area/navigation-core, status/shipped, risk/high]
---

# Off-route detection and reroute

> On each corridor poll the traveller's perpendicular distance from the route is compared with the mode's corridor radius; beyond it a fresh route is fetched from where they are, through the governor's cooldown and cap.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** high

## What it covers
- Per-mode corridor radius (15-30 m)
- Poll cadence per mode (3-10 s)
- Start-snap radius so a road-snap gap is not 'off route'
- Reroute through the governor (cooldown, cap)
- Old route stays until the new one lands

## Depends on
- [[route-progress]] — Route progress tracking
- [[routing-governor]] — Routing governor
- [[travel-modes]] — Travel modes and tuning
- [[guidance-mode]] — Guidance mode lifecycle

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| OR-1 | GPS noise next to a road triggers repeated reroutes | partly: governor cooldown |
| OR-2 | Reroute fetch fails and the user is left with no feedback | test: failedModeChangeKeepsTheOldRouteAndShowsDiagnosis; manual offline |
| OR-3 | Dead-reckoned position hides a real deviation | by design: off-route uses the real fix only |

## Tests
- `ThatWayTests/RoutingGovernorPolicyTests.swift`
- `ThatWayTests/TravelModeTests.swift`

## Manual checks
- Take a wrong turn on purpose: reroute within one poll, no flicker of cards

## Open items
- none

## Scenarios that pass through it
- [[flow-off-route]] — Wrong turn and reroute
- [[flow-offline-midroute]] — Losing the connection mid-trip
- [[flow-relaunch-restore]] — Relaunch with a trip in progress
