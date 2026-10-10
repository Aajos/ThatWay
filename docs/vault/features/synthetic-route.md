---
id: synthetic-route
title: Synthetic test route
area: watch
status: spike
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.10
tier: internal
value: 2
release: v1.0
cpu: "n/a (tests only)"
memory: "n/a"
battery: "n/a"
files:
  - ThatWayCore/Sources/ThatWayCore/SyntheticRoute.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::syntheticRouteHasTheRightShape
manual_checks:
depends_on: [route-models]
tags: [feature, area/watch, status/spike, risk/low]
---

# Synthetic test route

> Builds a straight-leg route with turns relative to where the wearer stands, so tests need no stored coordinates and no network.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** low

## What it covers
- Legs and turns to a real `Route` shape
- 20 m geometry sampling

## Depends on
- [[route-models]] — Route models

## Used by
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| SR-1 | Flat-earth offsets drift for legs over a few kilometres | by design: test aid |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::syntheticRouteHasTheRightShape`

## Manual checks
- none recorded

## Open items
- none

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
