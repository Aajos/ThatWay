---
id: watch-voice-search
title: Watch voice destination search
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
files:
  - ThatWayWatch/SearchView.swift
  - ThatWayWatch/DestinationSearch.swift
  - ThatWayWatch/WatchModel.swift
tests:
manual_checks:
  - Say a nearby shop: result list, pick one, guidance starts
  - Airplane Mode: search says it needs a connection
depends_on: [routing-provider-seam, route-tracker, watch-travel-modes, bearing-math]
tags: [feature, area/watch, status/spike, risk/medium]
---

# Watch voice destination search

> Swipe right on the watch, tap the big button to dictate a place (watchOS lets the wearer start dictation only with a tap), MapKit finds it near them, a tap sets it as the destination and fetches a real route for the current mode, with Point mode as the fallback.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** medium

## What it covers
- Dictation via `TextFieldLink`
- MapKit local search near the fix (8 km), nearest first, max 8 results
- Tap sets the destination, fetches the OSRM route through the shared provider
- Route failure falls back to Point mode with a message
- Destination name and coordinates are memory only: never stored or logged

## Depends on
- [[routing-provider-seam]]
- [[route-tracker]]
- [[watch-travel-modes]]
- [[bearing-math]]

## Used by
- [[watch-gestures]] — Watch gestures and controls

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WVS-1 | Dictation cannot be started programmatically: one extra tap after the swipe | by design (watchOS) |
| WVS-2 | Query or place name ends up in a log | none: no test on the watch side |
| WVS-3 | Search or route fails offline | manual |

## Tests
- none yet

## Manual checks
- Say a nearby shop: result list, pick one, guidance starts
- Airplane Mode: search says it needs a connection

## Open items
- Add a no-places-in-logs test for the watch.
