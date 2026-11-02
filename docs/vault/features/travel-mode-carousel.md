---
id: travel-mode-carousel
title: Travel-mode carousel
area: guidance-ui
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/TravelModeCarousel.swift
tests:
manual_checks:
  - Drag and tap each tile; VoiceOver swipe up/down
depends_on: [travel-modes, theme-system]
tags: [feature, area/guidance-ui, status/shipped, risk/low]
---

# Travel-mode carousel

> Arc carousel in the activity pill: drag or tap to choose Walk/Run/Cycle/Drive, with haptic ticks, a mode-name flash and VoiceOver support.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** low

## What it covers
- Single drag gesture handling tap and drag
- Selection ticks and confirm haptic
- Mode name flash in the speed slot
- VoiceOver adjustable action, Reduce Motion
- Still tile white when stationary

## Depends on
- [[travel-modes]] — Travel modes and tuning
- [[theme-system]] — Themes and shared look

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| TC-1 | Tap swallowed by a child gesture | manual: fixed once |

## Tests
- none yet

## Manual checks
- Drag and tap each tile; VoiceOver swipe up/down

## Open items
- none

## Scenarios that pass through it
- [[flow-mode-change]] — Switching travel mode mid-route
