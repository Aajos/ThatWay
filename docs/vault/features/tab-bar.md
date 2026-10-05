---
id: tab-bar
title: Tab bar
area: guidance-ui
status: shipped
risk: low
last_verified: 2026-10-05
files:
  - ThatWay/Compass/RootView.swift
tests:
manual_checks:
  - SE: labels clear of the screen edge
depends_on: [theme-system]
tags: [feature, area/guidance-ui, status/shipped, risk/low]
---

# Tab bar

> Floating WAY / MAP / STORE / YOU bar, hidden while search, the avatar sheet or the card curtain is up.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** low

## What it covers
- Four tabs with selection haptic
- Hidden during search / curtain / avatar sheet
- Bottom leeway on devices without a bottom safe-area inset

## Depends on
- [[theme-system]] — Themes and shared look

## Used by
- [[compass-screen-layout]] — Compass screen layout and small screens

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| TB-1 | Labels touch the screen edge on Home-button phones (was a real bug) | manual: fixed with leeway |

## Tests
- none yet

## Manual checks
- SE: labels clear of the screen edge

## Open items
- none
