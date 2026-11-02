---
id: route-failure
title: Failure diagnosis and connectivity
area: routing
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWayCore/Sources/ThatWayCore/RoutePlausibility.swift
  - ThatWay/Managers/RouteFailure.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RoutePlausibilityTests.swift
  - ThatWayTests/FollowFriendTests.swift::guidingToAnotherContinentNeverCallsTheRouter
  - ThatWayTests/RoutingErrorMappingTests.swift
manual_checks:
depends_on: [routing-provider-seam]
tags: [feature, area/routing, status/shipped, risk/medium]
---

# Failure diagnosis and connectivity

> Turns a routing error plus connectivity into a plain-language card with a retry countdown, never replacing the active instruction and never clearing the existing route.

**Area:** [[area-routing]] · **Status:** shipped · **Risk:** medium

## What it covers
- **Too far to route** (checked before any request): a straight-line limit by mode (walking 200 km, cycling 800 km, driving 4,500 km). Beyond it nothing is sent to the router; guidance shows "Too far to route by walking. Pointing straight there instead." and the needle keeps pointing at the target (Point mode shows nothing and asks nothing). When the gap closes (a moving friend), the first route is fetched automatically. A distance rule only: water or missing roads inside the limit come back from the router as no route / no road nearby, which stop at once
- Offline / timeout / server / rate-limited / no route / no road / waiting for GPS
- Retryable vs non-retryable
- Countdown and Retry now
- Names recorded in the trip log (`failure.<name>`)

## Depends on
- [[routing-provider-seam]] — Routing provider seam (OSRM + fallback)

## Used by
- [[mode-change-reroute]] — Mid-route mode change
- [[routing-governor]] — Routing governor

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RF-9 | A destination on another continent is sent to the router (slow, hammers a shared server, can retry for ever) | test: RoutePlausibilityTests::anotherContinentIsNeverRouted; FollowFriendTests::guidingToAnotherContinentNeverCallsTheRouter |
| RF-10 | A long real drive (Melbourne to Perth) is wrongly refused | test: RoutePlausibilityTests::aLongRealDriveIsStillAllowed |
| RF-11 | A far but in-range route times out and the app retries for ever | none: known; a retry ceiling is the fix |
| RF-1 | Offline vs a struggling server look the same as `network` unless connectivity is consulted | test: RoutingErrorMappingTests |

## Tests
- `ThatWayTests/RoutingErrorMappingTests.swift`

## Manual checks
- none recorded

## Open items
- none

## Scenarios that pass through it
- [[flow-off-route]] — Wrong turn and reroute
- [[flow-mode-change]] — Switching travel mode mid-route
- [[flow-offline-midroute]] — Losing the connection mid-trip
