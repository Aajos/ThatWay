---
id: routing-governor
title: Routing governor
area: routing
status: shipped
risk: high
last_verified: 2026-10-05
files:
  - ThatWay/Managers/RoutingGovernor.swift
  - ThatWay/Managers/ConnectivityMonitoring.swift
tests:
  - ThatWayTests/RoutingGovernorPolicyTests.swift
manual_checks:
  - Airplane Mode mid-route, then back on: recovers by itself
depends_on: [routing-provider-seam, route-failure]
tags: [feature, area/routing, status/shipped, risk/high]
---

# Routing governor

> Rate limiting, one request in flight, capped exponential backoff with jitter (2, 4, 8, 16, 30 s), reroute cooldown and rolling cap, 'Retry now', and retry for as long as guidance is alive.

**Area:** [[area-routing]] · **Status:** shipped · **Risk:** high

## What it covers
- Minimum 1.1 s between requests, one in flight
- Backoff schedule and Retry-After
- Reroute cooldown 15 s and a rolling cap of 4 per 5 minutes (initial requests exempt)
- Connectivity-aware diagnosis
- `retryNow()` skips the wait

## Depends on
- [[routing-provider-seam]] — Routing provider seam (OSRM + fallback)
- [[route-failure]] — Failure diagnosis and connectivity

## Used by
- [[guidance-mode]] — Guidance mode lifecycle
- [[mode-change-reroute]] — Mid-route mode change
- [[off-route-reroute]] — Off-route detection and reroute

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RG-1 | Persistent off-route reading hammers the API | partly: cooldown and cap tested |
| RG-2 | Retry loop outlives guidance | manual: END during retries |

## Tests
- `ThatWayTests/RoutingGovernorPolicyTests.swift`

## Manual checks
- Airplane Mode mid-route, then back on: recovers by itself

## Open items
- Airplane Mode device test still to do before release.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-off-route]] — Wrong turn and reroute
- [[flow-mode-change]] — Switching travel mode mid-route
- [[flow-offline-midroute]] — Losing the connection mid-trip
