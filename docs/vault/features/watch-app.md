---
id: watch-app
title: Watch app UI
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
files:
  - ThatWayWatch/ThatWayWatchApp.swift
  - ThatWayWatch/MainView.swift
  - ThatWayWatch/WatchModel.swift
  - ThatWayWatch/DebugView.swift
tests:
manual_checks:
  - Run on a real watch (signing in Xcode needed once)
depends_on: [theme-system, heading-blender, route-tracker, synthetic-route, watch-haptics, watch-session, core-package, watch-gestures, watch-drive-guard]
tags: [feature, area/watch, status/spike, risk/medium]
---

# Watch app UI

> watchOS app in the iPhone's look, embedded as the iPhone app's companion: Point/Guide toggle, themed dial with the real needle skins, guidance arrow and distance, speed. Gesture-driven (see watch-gestures); test pages behind the ellipsis button.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** medium

## What it covers
- Shared themes, Nunito and needle skins
- One gesture-driven screen plus a test-tools sheet (debug overlay, session, haptics)
- Debug launch flags: `-spike-autoroute`, `-spike-autostart`, `-spike-kind`, `-spike-phone-mode`, `-spike-searchtext`
- Test route built from the current fix

## Depends on
- [[theme-system]] — Themes and shared look
- [[heading-blender]] — Heading blender (watch)
- [[route-tracker]] — Route tracker (shared progress maths)
- [[synthetic-route]] — Synthetic test route
- [[watch-haptics]] — Watch haptic patterns
- [[watch-session]] — Watch wrist-down session (A/B)
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WA-1 | Not yet signed or run on a real watch | manual: blocked on signing |
| WA-2 | Simulator has no magnetometer or wrist: blender cannot be exercised there | manual |

## Tests
- none yet

## Manual checks
- Run on a real watch (signing in Xcode needed once)

## Open items
- On-wrist results outstanding (docs/watch-spike.md).

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
