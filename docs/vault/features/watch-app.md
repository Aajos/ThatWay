---
id: watch-app
title: Watch app UI
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.10
tier: free
value: 3
release: later
cpu: "not measured"
memory: "not measured"
battery: "not measured"
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
- Layout rule: the main screen ignores the safe area and positions itself (below the system clock, 9 pt clear of the rounded corners); readouts sit in a strip above the dial, never over its rim
- Simulator demo of the Find chip: `-spike-proximity-demo <friend>` plays a friend approaching from 60 m to right here (the simulator has no Ultra Wideband; testing aid only)
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
| WA-3 | Content squeezed or clipped on the display: the system keeps 40 pt (top) and 19 pt (bottom) free on a 40 mm SE 3 and only 2 pt at the sides, so controls hugged the rounded edge and the compass lost a third of the screen (was a real bug) | manual: screenshot every watch screen on the SE 3 40 mm and 44 mm simulators; the main screen lays itself out on the whole display (root `ignoresSafeArea`, 22 pt under the clock, 9 pt side margin) and the tools pages use `safeAreaPadding` |

## Tests
- none yet

## Manual checks
- Run on a real watch (signing in Xcode needed once)

## Open items
- On-wrist results outstanding (docs/watch-spike.md).

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
