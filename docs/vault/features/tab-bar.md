---
id: tab-bar
title: Tab bar
area: guidance-ui
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-09-14
build: 0.1
tier: free
value: 3
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
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
- A bubble behind the open tab (accent tint and outline) and accent-coloured icon and label for it; the others are dimmed
- A small dot on WAY while navigating or pointing: a separate signal from "this tab is open"
- The selection is passed in from RootView and the bar is rebuilt on each change (it used to keep WAY highlighted while another tab was open)
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
| TB-9 | The bar shows WAY selected while another tab is open (was a real bug) | manual: tap each tab in the simulator and check the bubble follows |
| TB-1 | Labels touch the screen edge on Home-button phones (was a real bug) | manual: fixed with leeway |

## Tests
- none yet

## Manual checks
- SE: labels clear of the screen edge

## Open items
- none
