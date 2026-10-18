---
id: audio-cue-plan
title: Audio cue plan, panning, voice script
area: audio-haptics
status: shipped
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/AudioManager.swift
  - ThatWay/Compass/AppModel.swift
tests:
  - ThatWayTests/AudioManagerTests.swift
manual_checks:
  - Walk toward a turn: single cue at 15 m, pan on the correct side
depends_on: [route-progress, travel-modes, dead-reckoning]
tags: [feature, area/audio-haptics, status/shipped, risk/medium]
---

# Audio cue plan, panning, voice script

> When and how cues fire: announcement points per mode (drive 100/50/15 m, cycle 50/15, walk/run 15), 1-3 tones by distance, left/right pan by turn side, three-part spoken phrases.

**Area:** [[area-audio-haptics]] · **Status:** shipped · **Risk:** medium

## What it covers
- Fire each point once per instruction; a GPS jump plays only the nearest
- Tone count by distance
- Pan left/right/centre
- Voice: 'In 50 metres, turn left onto ...' style script, imperial option

## Depends on
- [[route-progress]] — Route progress tracking
- [[travel-modes]] — Travel modes and tuning
- [[dead-reckoning]] — Dead reckoning

## Used by
- [[audio-manager]] — Audio manager (tones and voice)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| AC-1 | Cue fires late because progress lags a fix (dead reckoning bounds this) | manual |
| AC-2 | Cue repeats after a reroute resets the card | test: crossedPoint fired set per card id |

## Tests
- `ThatWayTests/AudioManagerTests.swift`

## Manual checks
- Walk toward a turn: single cue at 15 m, pan on the correct side

## Open items
- none

## Scenarios that pass through it
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-mode-change]] — Switching travel mode mid-route
