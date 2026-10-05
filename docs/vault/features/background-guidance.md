---
id: background-guidance
title: Background guidance, scene phases, screen awake
area: location-sensors
status: shipped
risk: high
last_verified: 2026-10-05
files:
  - ThatWay/Info.plist
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Compass/RootView.swift
tests:
manual_checks:
  - Start a trip, lock the phone for 10 minutes: cues still fire, trip log shows samples
  - Unlock mid-trip: screen current, no stale card
depends_on: [location-manager, audio-manager]
tags: [feature, area/location-sensors, status/shipped, risk/high]
---

# Background guidance, scene phases, screen awake

> Guidance keeps running with the screen locked: background location and audio modes, location-driven refresh while the scene is inactive, paused tick and heading, and a screen that stays on while guiding in the foreground.

**Area:** [[area-location-sensors]] · **Status:** shipped · **Risk:** high

## What it covers
- UIBackgroundModes location + audio
- Background location only while guiding and not arrived
- Tick and heading stopped when the scene is inactive
- Location updates drive the refresh in the background
- `isIdleTimerDisabled` while guiding in the foreground
- Compass-health state reset when backgrounded

## Depends on
- [[location-manager]] — LocationManager (fixes and permission)
- [[audio-manager]] — Audio manager (tones and voice)

## Used by
- [[guidance-mode]] — Guidance mode lifecycle

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| BG-1 | App suspended on lock and guidance silently stops | manual: long locked walk (trip log samples show it) |
| BG-2 | Screen-awake drains battery over a long walk (default chosen, not agreed) | manual: weekly battery test |
| BG-3 | iOS shows the blue location indicator after the trip ends | manual |

## Tests
- none yet

## Manual checks
- Start a trip, lock the phone for 10 minutes: cues still fire, trip log shows samples
- Unlock mid-trip: screen current, no stale card

## Open items
- Screen-awake default needs a decision (toggle vs always).

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-arrival]] — Arriving
