---
id: continuous-angle
title: Continuous angles
area: location-sensors
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.8
tier: internal
value: 3
release: v1.0
cpu: "predicted: 0 (two Double updates per redraw)"
memory: "predicted: 0"
battery: "predicted: 0"
files:
  - ThatWayCore/Sources/ThatWayCore/ContinuousAngle.swift
  - ThatWayCore/Sources/ThatWayCore/AngleMath.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift::AngleMathTests
  - ThatWayTests/CompassHealthTests.swift::continuousAngleIsIdempotentAndHandlesNorth
manual_checks:
depends_on: [core-package]
tags: [feature, area/location-sensors, status/shipped, risk/low]
---

# Continuous angles

> A running unbounded angle that always moves by the shortest turn, so animating between two compass readings never goes the long way round at the 359/0 wrap point.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** low

## What it covers
- `ContinuousAngle.update(to:)` idempotent
- `AngleMath` shortest-arc maths shared by blender, health check and dial

## Depends on
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)

## Used by
- [[compass-health]] — Compass health, ghost overlay, GPS direction
- [[dial-view]] — Compass dial and needle
- [[heading-blender]] — Heading blender (watch)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| CA-1 | Angle value grows without bound over a very long session | none: Double precision is ample |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift::AngleMathTests`
- `ThatWayTests/CompassHealthTests.swift::continuousAngleIsIdempotentAndHandlesNorth`

## Manual checks
- none recorded

## Open items
- none
