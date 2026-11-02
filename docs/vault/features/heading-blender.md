---
id: heading-blender
title: Heading blender (watch)
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.10
tier: internal
value: 2
release: later
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWayCore/Sources/ThatWayCore/HeadingBlender.swift
  - ThatWayWatch/WatchModel.swift
  - ThatWayWatch/DebugView.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift
manual_checks:
  - Jog 10+ minutes; analyse the log's error against GPS course (docs/watch-spike.md)
depends_on: [continuous-angle]
tags: [feature, area/watch, status/spike, risk/medium]
---

# Heading blender (watch)

> Chooses GPS course above 1.5 m/s and the magnetometer below 0.8 m/s with hysteresis, a dwell time and a circular low-pass filter, because a wrist-swung magnetometer is unreliable while running.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** medium

## What it covers
- Enter GPS at 1.5 m/s, leave below 0.8 m/s
- 1 s dwell, single spikes ignored
- Invalid/stale/inaccurate course falls back to the magnetometer
- Shortest-arc filter (tau 0.5 s course, 0.4 s magnetometer), snap above 120 degrees
- Live threshold tuning on the watch

## Depends on
- [[continuous-angle]] — Continuous angles

## Used by
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| HB-1 | Thresholds wrong for brisk walking (0.8-1.5 m/s band) | manual: real jog |
| HB-2 | Magnetometer accuracy field misleading on the wrist | manual |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift`

## Manual checks
- Jog 10+ minutes; analyse the log's error against GPS course (docs/watch-spike.md)

## Open items
- Real-wrist numbers outstanding.

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
