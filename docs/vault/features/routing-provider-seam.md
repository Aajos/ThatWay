---
id: routing-provider-seam
title: Routing provider seam (OSRM + fallback)
area: routing
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: internal
value: 5
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWayCore/Sources/ThatWayCore/RoutingProvider.swift
  - ThatWayCore/Sources/ThatWayCore/OSRMRoutingProvider.swift
  - ThatWay/Managers/RoutingProvider.swift
  - ThatWay/Managers/FallbackRoutingProvider.swift
  - ThatWay/Config.swift
tests:
  - ThatWayTests/OSRMParsingTests.swift
  - ThatWayTests/RoutingErrorMappingTests.swift
  - ThatWayTests/FallbackRoutingProviderTests.swift
manual_checks:
  - Route in each profile: walking and driving give different routes
depends_on: [route-models, backend-config, core-package]
tags: [feature, area/routing, status/shipped, risk/high]
---

# Routing provider seam (OSRM + fallback)

> One protocol the whole routing stack sits behind, an OSRM implementation that parses geojson geometry, steps, intersections and annotations into the app's own models, and a fallback chain that moves on only when a host looks unhealthy.

**Area:** [[area-routing]] · **Status:** shipped · **Risk:** high

## What it covers
- Provider, errors and OSRM parsing live in ThatWayCore (shared with the watch); the app injects its `Config` hosts and user agent
- Per-profile OSRM hosts (car/foot/bike): one table, `OSRMHosts`, in the shared package
- Parsing, roundabout merge, destination extension
- Error mapping (no route vs no road vs server vs rate limit)
- Fallback chain (one provider today)
- 5 s request timeout, cancellation mapped to cancellation

## Depends on
- [[route-models]] — Route models
- [[backend-config]] — Backend and routing configuration

## Used by
- [[route-failure]] — Failure diagnosis and connectivity
- [[routing-governor]] — Routing governor
- [[watch-voice-search]] — Watch voice destination search

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RS-1 | The public OSRM demo hosts are not production-grade (rate limits, no uptime promise) | none: replace before release |
| RS-2 | An engine change breaks parsing of a field the UI relies on | tests: OSRMParsingTests fixtures |

## Tests
- `ThatWayTests/OSRMParsingTests.swift`
- `ThatWayTests/RoutingErrorMappingTests.swift`
- `ThatWayTests/FallbackRoutingProviderTests.swift`

## Manual checks
- Route in each profile: walking and driving give different routes

## Open items
- Choose and configure a production routing host.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
