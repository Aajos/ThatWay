---
id: settings-profile
title: Settings and Profile screen
area: app-shell
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 2
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/ProfileScreen.swift
  - ThatWay/Compass/CompassModels.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Change each row and look for an effect; the three unwired ones have none
depends_on: [compass-tilt, audio-manager, theme-system, trip-log, persistence-defaults]
tags: [feature, area/app-shell, status/shipped, risk/low]
---

# Settings and Profile screen

> The Profile tab: account/friends sections (when the backend is on), default mode, settings rows, test logs, donate banner. Some rows are real settings, some are stored but have no effect.

**Area:** [[area-app-shell]] · **Status:** shipped · **Risk:** low

## What it covers
- WIRED: Compass skin, Theme, Compass tilt (Off/Slight/Hard), Audio guidance (Off/Tone/Voice), Units, Default mode, Record test logs
- Rows open their options in place (inline picker) instead of the system Menu, which scrolled the page to the top and sat detached from its row
- NOT WIRED (stored in memory only, nothing reads them): Voice of directions, Haptics on turns, Share destination
- Decorative: Visibility and close-by radius, achievements

## Depends on
- [[compass-tilt]] — Compass tilt algorithm
- [[audio-manager]] — Audio manager (tones and voice)
- [[theme-system]] — Themes and shared look
- [[trip-log]] — On-device trip log
- [[persistence-defaults]] — Persisted preferences

## Used by
- [[avatars-social-decor]] — Avatars, visibility and friends row
- [[haptics-ios]] — Haptics on the iPhone

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| SP-1 | Settings that do nothing (voice, haptics, share) mislead the user | none: known gap |
| SP-3 | The system Menu scrolled the Profile page to the top and looked detached for a few seconds after a choice | manual: inline picker, verified in the simulator |
| SP-2 | `NavOptions` values are not persisted: tilt/units/voice reset on every launch | none: known gap |

## Tests
- none yet

## Manual checks
- Change each row and look for an effect; the three unwired ones have none

## Open items
- Persist `NavOptions`; wire or remove the three dead rows.
