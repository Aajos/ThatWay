---
id: compass-screen-layout
title: Compass screen layout and small screens
area: guidance-ui
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Compass/CompassScreen.swift
  - ThatWay/Compass/RootView.swift
  - ThatWay/ContentView.swift
tests:
manual_checks:
  - iPhone SE: open search, rotate through text sizes
  - iPad / wide screens stay a 480 pt column
depends_on: [theme-system, guidance-cards, dial-view, search-ui, tab-bar]
tags: [feature, area/guidance-ui, status/shipped, risk/medium]
---

# Compass screen layout and small screens

> The main screen's responsive layout: density scaling for short screens, a flexible dial slot, ETA row wrapping, Dynamic Type caps on chrome, the location-issue card, and the keyboard-proof pinned layout.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** medium

## What it covers
- Density scaling (iPhone SE)
- Flexible dial slot while guiding
- Top bar and tab bar Dynamic Type caps
- Whole-screen ignores the keyboard (fixes the drop-down bug)
- Content pinned top, full-screen frame
- Tab bar lifted 6 pt on Home-button phones

## Depends on
- [[theme-system]] — Themes and shared look
- [[guidance-cards]] — Guidance cards
- [[dial-view]] — Compass dial and needle
- [[search-ui]] — Search UI
- [[tab-bar]] — Tab bar

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| CL-1 | Keyboard shrinks the layout area and shifts everything down (was a real bug) | manual on device; fixed |
| CL-2 | New chrome added without checking SE height | manual |

## Tests
- none yet

## Manual checks
- iPhone SE: open search, rotate through text sizes
- iPad / wide screens stay a 480 pt column

## Open items
- No snapshot/UI tests of layout.

## Scenarios that pass through it
- [[flow-arrival]] — Arriving
