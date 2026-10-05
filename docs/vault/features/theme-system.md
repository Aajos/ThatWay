---
id: theme-system
title: Themes and shared look
area: guidance-ui
status: shipped
risk: low
last_verified: 2026-10-05
files:
  - ThatWayCore/Sources/ThatWayUI/AppTheme.swift
  - ThatWayCore/Sources/ThatWayUI/NunitoFont.swift
  - ThatWayCore/Sources/ThatWayUI/ColorTools.swift
  - ThatWay/ThatWayApp.swift
tests:
manual_checks:
  - Cycle all four themes on iPhone and watch; Nunito glyphs present (not system font)
depends_on: [core-package]
tags: [feature, area/guidance-ui, status/shipped, risk/low]
---

# Themes and shared look

> Four palettes (Ember, Tide, Paper, Arcade) plus glow/lift/tint/surface helpers, the Nunito font and the needle skins, all in the shared ThatWayUI module so iPhone and watch look the same.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** low

## What it covers
- Palettes and mode colours
- Light-theme rules (paler glows, stronger tints, bold outlines)
- Nunito registered from the package at launch
- `Color(hex:)` and HSB read through `resolve` (no UIKit)
- Theme persisted on the watch (`watchTheme`)

## Depends on
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)

## Used by
- [[compass-screen-layout]] — Compass screen layout and small screens
- [[dial-view]] — Compass dial and needle
- [[guidance-cards]] — Guidance cards
- [[settings-profile]] — Settings and Profile screen
- [[store-skins]] — Store (skins, themes, donate)
- [[tab-bar]] — Tab bar
- [[travel-mode-carousel]] — Travel-mode carousel
- [[watch-app]] — Watch app UI
- [[watch-gestures]] — Watch gestures and controls

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| TS-1 | Font not registered before first use falls back silently to the system font | manual: visual; `ThatWayFonts.register()` runs in App.init |
| TS-2 | Dark-glow regressions on light themes | manual: Paper |

## Tests
- none yet

## Manual checks
- Cycle all four themes on iPhone and watch; Nunito glyphs present (not system font)

## Open items
- No automated colour/contrast checks.

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-watch-guidance]] — Guidance on the watch
