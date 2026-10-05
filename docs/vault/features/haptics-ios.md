---
id: haptics-ios
title: Haptics on the iPhone
area: audio-haptics
status: setting-only
risk: low
last_verified: 2026-10-05
files:
  - ThatWay/Compass/TravelModeCarousel.swift
  - ThatWay/Compass/ProfileScreen.swift
tests:
manual_checks:
  - Change 'Haptics on turns' and walk a turn: nothing happens (current truth)
depends_on: [settings-profile]
tags: [feature, area/audio-haptics, status/setting-only, risk/low]
---

# Haptics on the iPhone

> The carousel gives selection/confirm haptics and tabs give a selection tick. The Profile row 'Haptics on turns' (Off/Light/Strong) is stored in memory but NOT wired to anything: no haptic fires at a turn on the iPhone.

**Area:** [[area-audio-haptics]] · **Status:** setting-only · **Risk:** low

## What it covers
- Carousel haptics (wired)
- Tab and search ticks (wired)
- 'Haptics on turns' (NOT wired)

## Depends on
- [[settings-profile]] — Settings and Profile screen

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| HI-1 | A setting that does nothing erodes trust | none: known gap |

## Tests
- none yet

## Manual checks
- Change 'Haptics on turns' and walk a turn: nothing happens (current truth)

## Open items
- Wire the setting (the watch already has turn haptic patterns) or remove the row.
