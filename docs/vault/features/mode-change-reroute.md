---
id: mode-change-reroute
title: Mid-route mode change
area: navigation-core
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Managers/RoutingGovernor.swift
tests:
  - ThatWayTests/TravelModeTests.swift
manual_checks:
depends_on: [travel-modes, routing-governor, route-failure, guidance-mode]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Mid-route mode change

> Changing mode while guiding debounces 600 ms then refetches for the new profile as an initial request (retries, no cooldown); the old route stays until the new one lands.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- 600 ms debounce, one fetch for rapid changes
- Initial-request path (not a reroute)
- 'Switching to ...' card while pending
- Failed switch keeps the old route and shows a diagnosis
- Cancelled fetch never shown as a failure

## Depends on
- [[travel-modes]] — Travel modes and tuning
- [[routing-governor]] — Routing governor
- [[route-failure]] — Failure diagnosis and connectivity
- [[guidance-mode]] — Guidance mode lifecycle

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| MC-1 | Cancelled request surfaced as 'Routing service isn't responding' | test: CancelledRequestTests |

## Tests
- `ThatWayTests/TravelModeTests.swift`

## Manual checks
- none recorded

## Open items
- none

## Scenarios that pass through it
- [[flow-mode-change]] — Switching travel mode mid-route
