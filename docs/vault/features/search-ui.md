---
id: search-ui
title: Search UI
area: guidance-ui
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/CompassScreen.swift
tests:
manual_checks:
  - Open search on SE: at least four rows visible above the keyboard
depends_on: [destination-search]
tags: [feature, area/guidance-ui, status/shipped, risk/low]
---

# Search UI

> The persistent search bar and results panel: pills hide while searching, results scroll above the keyboard, recents when empty.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** low

## What it covers
- Panel pinned under the bar
- Keyboard height tracked for bottom padding
- Scroll with interactive keyboard dismissal
- Recent list, live results, empty and searching states

## Depends on
- [[destination-search]] — Destination search and recents

## Used by
- [[compass-screen-layout]] — Compass screen layout and small screens

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| SU-1 | Panel extends under the keyboard and rows are unreachable | manual: fixed |

## Tests
- none yet

## Manual checks
- Open search on SE: at least four rows visible above the keyboard

## Open items
- none

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
