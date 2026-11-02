---
id: redraw-model
title: Redraw and publish model
area: power-performance
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.8
tier: internal
value: 4
release: v1.0
cpu: "measured (sim): walk 2.74 % to 1.51 % mean after the dial/card split; compass redraws 1.06 to 0.56 /s"
memory: "not measured"
battery: "predicted: -0.5 to -1 %/h while guiding (device, not yet measured)"
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Compass/DialView.swift
  - ThatWay/Compass/GuidanceCardsView.swift
  - ThatWay/Managers/RoutingManager.swift
  - ThatWay/Managers/ETAManager.swift
tests:
  - ThatWayTests/DeadReckoningTests.swift::subMetreEstimateChangesDoNotPublish
manual_checks:
  - perf-weekly.md protocol: compare `body.*` counters before/after any UI change
depends_on: [perf-harness]
tags: [feature, area/power-performance, status/shipped, risk/high]
---

# Redraw and publish model

> How state reaches the screen cheaply: every @Published write re-evaluates whole screens, so writes are guarded, hot views take plain values and are Equatable, heading redraws only the dial, progress publishes by quantum, the tick is 1 s guiding and 3 s idle.

**Area:** [[area-power-performance]] · **Status:** shipped · **Risk:** high

## What it covers
- Guarded published writes
- `DialState` / `GuidanceStackState` / `NextStackState` value types
- `DialHost` observing the location manager
- Progress publishes on a real fix, card change or every 4 m
- ETA values not published
- Tick interval by mode and Low Power Mode

## Depends on
- [[perf-harness]] — Performance harness (PERF build)

## Used by
- [[dial-view]] — Compass dial and needle
- [[guidance-cards]] — Guidance cards

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| RM-A | A new @Published write or a view reading the whole model undoes the savings silently | perf harness only (no unit test) |
| RM-B | An equatable view skips a needed redraw because a shown value was left out of its state | manual |

## Tests
- `ThatWayTests/DeadReckoningTests.swift::subMetreEstimateChangesDoNotPublish`

## Manual checks
- perf-weekly.md protocol: compare `body.*` counters before/after any UI change

## Open items
- Top bar and carousel still observe the whole model.

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-phone-locked]] — Phone locked mid-trip
