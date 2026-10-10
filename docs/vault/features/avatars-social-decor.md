---
id: avatars-social-decor
title: Avatars, visibility and friends row
area: app-shell
status: setting-only
risk: low
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 1
release: later
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Compass/Sheets.swift
  - ThatWay/Compass/ProfileScreen.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
manual_checks:
depends_on: [friends, settings-profile]
tags: [feature, area/app-shell, status/setting-only, risk/low]
---

# Avatars, visibility and friends row

> Avatar picker sheet, visibility choices and the friends row on the compass screen. Friends have no location data, so tapping one does nothing navigational.

**Area:** [[area-app-shell]] · **Status:** setting-only · **Risk:** low

## What it covers
- Avatar sheet (camera/library options are UI only)
- Visibility: friends / close ones / ... (no effect on anything)
- Friends row from the friends manager (empty when the backend is off)

## Depends on
- [[friends]] — Friends
- [[settings-profile]] — Settings and Profile screen

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| AV-1 | Avatar photo options do nothing | none: known gap |

## Tests
- none yet

## Manual checks
- none recorded

## Open items
- Decide whether the social layer ships.
