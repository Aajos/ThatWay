---
id: route-failure
title: Failure diagnosis and connectivity
area: routing
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/RouteFailure.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
  - ThatWayTests/RoutingErrorMappingTests.swift
manual_checks:
depends_on: [routing-provider-seam]
tags: [feature, area/routing, status/shipped, risk/medium]
---

# Failure diagnosis and connectivity

> Turns a routing error plus connectivity into a plain-language card with a retry countdown, never replacing the active instruction and never clearing the existing route.

**Area:** [[area-routing]] · **Status:** shipped · **Risk:** medium

## What it covers
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
