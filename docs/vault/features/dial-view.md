---
id: dial-view
title: Compass dial and needle
area: guidance-ui
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Compass/DialView.swift
  - ThatWayCore/Sources/ThatWayUI/DialSkins.swift
  - ThatWayCore/Sources/ThatWayCore/ContinuousAngle.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift::wraparoundSmoothingNeverSwingsTheLongWay
  - ThatWayTests/CompassHealthTests.swift::continuousAngleTakesTheShortWayAcrossTheWrapPoint
manual_checks:
  - Turn through every direction: no whirl at the wrap point
  - Idle: needle follows north
  - Cycle skins/themes
depends_on: [heading, continuous-angle, compass-tilt, theme-system, redraw-model]
tags: [feature, area/guidance-ui, status/shipped, risk/medium]
---

# Compass dial and needle

> The dial: static face (gradient, glass rim, ticks, cardinals) flattened into one bitmap, a rotating cardinal ring, the needle rendered once to an image and swayed natively, tilt/lean perspective, and the distance/arrow readout.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** medium

## What it covers
- Value-driven `DialState` (Equatable): redraws only when something it shows changes
- `DialHost` observes the location manager so a heading change redraws only the dial
- Continuous angles so the ring/needle never spin the long way at the wrap point
- Needle skins (needle, wheel, clock) from ThatWayUI
- Native Core Animation sway (zero CPU)
- Idle emphasis (north-up, cardinals)
- Compass-health overlay hosted on top

## Depends on
- [[heading]] — Heading pipeline
- [[continuous-angle]] — Continuous angles
- [[compass-tilt]] — Compass tilt algorithm
- [[theme-system]] — Themes and shared look
- [[redraw-model]] — Redraw and publish model

## Used by
- [[compass-health]] — Compass health, ghost overlay, GPS direction
- [[compass-screen-layout]] — Compass screen layout and small screens
- [[point-mode]] — Point mode (straight-line pointing)
- [[store-skins]] — Store (skins, themes, donate)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| DV-1 | Animating a wrapped angle spins the dial at one heading (was a real bug) | test: continuousAngle tests; manual |
| DV-2 | Repeating SwiftUI animations cost 6-10 % CPU | perf harness; sway is native for this reason |
| DV-3 | Needle image stale after theme/skin change | manual |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift::wraparoundSmoothingNeverSwingsTheLongWay`
- `ThatWayTests/CompassHealthTests.swift::continuousAngleTakesTheShortWayAcrossTheWrapPoint`

## Manual checks
- Turn through every direction: no whirl at the wrap point
- Idle: needle follows north
- Cycle skins/themes

## Open items
- none

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-compass-wrong]] — The compass goes wrong
