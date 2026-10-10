---
id: watch-haptics
title: Watch haptic patterns
area: watch
status: spike
risk: low
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
  - ThatWayCore/Sources/ThatWayCore/HapticPatterns.swift
  - ThatWayWatch/HapticPlayer.swift
  - ThatWayWatch/HapticTester.swift
  - ThatWayWatch/HapticsView.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::HapticPatternTests
manual_checks:
  - Jog and run the blind test; pass is 9/10 left/right
depends_on: [watch-spike-log]
tags: [feature, area/watch, status/spike, risk/low]
---

# Watch haptic patterns

> Two candidate sets of tap patterns built only from WKHapticType presets (count-based and direction-preset-based) for left, right, arrive and off-route, with a blind identification test.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** low

## What it covers
- Patterns defined platform-neutral in the shared package
- Played via WKInterfaceDevice
- Blind test: L/R x10, all x20, answers and reaction time logged
- Turn haptic fires at 30 m, arrive, off-route (20 s cooldown)

## Depends on
- [[watch-spike-log]] — Watch spike log and analysis

## Used by
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WH-1 | Patterns feel identical on a moving wrist | manual: the point of the test |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::HapticPatternTests`

## Manual checks
- Jog and run the blind test; pass is 9/10 left/right

## Open items
- Choose the final patterns from the results.

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
