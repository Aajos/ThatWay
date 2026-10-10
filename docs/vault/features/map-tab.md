---
id: map-tab
title: Map tab and map-tap routing
area: navigation-core
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/MapScreen.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Open Map, return to Way: memory returns (no lingering map view)
depends_on: [route-progress, guidance-mode]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Map tab and map-tap routing

> A MapKit view showing the destination and route preview; tapping a place offers 'Route there?'. The MKMapView exists only while the tab is visible.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- Route preview polyline
- Map-tap confirmation to start guidance
- Map view created/destroyed with the tab (memory)
- Recentre on first fix

## Depends on
- [[route-progress]] — Route progress tracking
- [[guidance-mode]] — Guidance mode lifecycle

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| MT-1 | Map view lingers after leaving the tab (memory) | manual: heap check done once in Phase 3 |

## Tests
- none yet

## Manual checks
- Open Map, return to Way: memory returns (no lingering map view)

## Open items
- none
