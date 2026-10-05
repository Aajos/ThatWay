---
id: store-skins
title: Store (skins, themes, donate)
area: app-shell
status: shipped
risk: low
last_verified: 2026-10-05
files:
  - ThatWay/Compass/StoreScreen.swift
  - ThatWay/Compass/AppModel.swift
tests:
manual_checks:
  - Pick each skin: dial updates
depends_on: [theme-system, dial-view]
tags: [feature, area/app-shell, status/shipped, risk/low]
---

# Store (skins, themes, donate)

> The Store tab shows themes and compass skins and a donate section. Skins and themes are all unlocked; there is no purchase flow.

**Area:** [[area-app-shell]] · **Status:** shipped · **Risk:** low

## What it covers
- Skin and theme pickers
- Owned sets
- Donate/tip banner (`goDonate`)

## Depends on
- [[theme-system]] — Themes and shared look
- [[dial-view]] — Compass dial and needle

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| SS-1 | Donate action has no real destination yet | manual |

## Tests
- none yet

## Manual checks
- Pick each skin: dial updates

## Open items
- No in-app purchase wiring.
