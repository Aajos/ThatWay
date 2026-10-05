---
id: destination-search
title: Destination search and recents
area: navigation-core
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/PlaceSearch.swift
  - ThatWay/Compass/CompassScreen.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Search 'coles' near you: results by distance; pick one; pick again from recents
depends_on: [location-manager, persistence-defaults]
tags: [feature, area/navigation-core, status/shipped, risk/medium]
---

# Destination search and recents

> Typed search (MapKit) biased to the traveller, results with distance, recents saved with their real coordinate so re-picking never re-geocodes.

**Area:** [[area-navigation-core]] · **Status:** shipped · **Risk:** medium

## What it covers
- Live search with cancellation
- Recents (5, newest first, with subtitle)
- Typed text geocoded once, superseded searches ignored
- Search never logs queries or coordinates

## Depends on
- [[location-manager]] — LocationManager (fixes and permission)
- [[persistence-defaults]] — Persisted preferences

## Used by
- [[point-mode]] — Point mode (straight-line pointing)
- [[search-ui]] — Search UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| DS-1 | Search region biased to the placeholder when there is no fix | manual |
| DS-2 | Network failure shows 'No matches' rather than an error | none |

## Tests
- none yet

## Manual checks
- Search 'coles' near you: results by distance; pick one; pick again from recents

## Open items
- No search tests; search failure has no distinct message.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
