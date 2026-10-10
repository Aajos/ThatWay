---
id: persistence-defaults
title: Persisted preferences
area: app-shell
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-09-19
build: 0.5
tier: free
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/AppModel.swift
  - ThatWay/Managers/RoutePersistence.swift
  - ThatWay/Managers/KeychainStore.swift
tests:
  - ThatWayTests/TravelModeTests.swift
manual_checks:
  - Change mode, audio style, quit, relaunch
depends_on: []
tags: [feature, area/app-shell, status/shipped, risk/low]
---

# Persisted preferences

> What survives a relaunch: travel mode, audio style, recent searches, test-logging switch, the watch's theme/skin, the active trip (separate file) and Keychain tokens.

**Area:** [[area-app-shell]] · **Status:** shipped · **Risk:** low

## What it covers
- UserDefaults keys: `travelMode.v1`, `audioStyle.v1`, `recentSearches.v1`, `testLogging.v1`, watch `watchTheme`/`watchSkin`
- Active trip file (Application Support)
- Auth refresh token in Keychain
- NOT persisted: NavOptions (tilt, units, voice, haptics, share), theme and skin on the iPhone, default mode, visibility

## Depends on
- (nothing: a leaf)

## Used by
- [[audio-manager]] — Audio manager (tones and voice)
- [[destination-search]] — Destination search and recents
- [[settings-profile]] — Settings and Profile screen
- [[travel-modes]] — Travel modes and tuning
- [[trip-log]] — On-device trip log
- [[watch-travel-modes]] — Watch travel modes (walk, run, cycle)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| PD-1 | A key renamed without migration silently resets users' choices | none |
| PD-2 | Theme and skin choice reset on relaunch (iPhone) | none: known gap |

## Tests
- `ThatWayTests/TravelModeTests.swift`

## Manual checks
- Change mode, audio style, quit, relaunch

## Open items
- Persist theme, skin and NavOptions.

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
- [[flow-mode-change]] — Switching travel mode mid-route
