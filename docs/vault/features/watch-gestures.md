---
id: watch-gestures
title: Watch gestures and controls
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.10
tier: free
value: 2
release: later
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWayWatch/MainView.swift
  - ThatWayWatch/ToolsView.swift
  - ThatWayWatch/WatchModel.swift
tests:
manual_checks:
  - Try each swipe and the long-press on a real wrist
depends_on: [watch-travel-modes, watch-voice-search, theme-system]
tags: [feature, area/watch, status/spike, risk/medium]
---

# Watch gestures and controls

> The main watch screen is gesture-driven: swipe left = next theme, swipe right = voice destination search, swipe up/down = travel mode, long-press the compass = needle skin, the ellipsis button = test tools. The test pages moved behind that button.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** medium

## What it covers
- One drag gesture classified by dominant direction (minimum 22 pt)
- Left: theme cycle (persisted), right: search sheet, up/down: mode
- Long-press: needle skin; ellipsis: test tools sheet
- Mode icon in the top row and a mode flash over the dial

## Depends on
- [[watch-travel-modes]]
- [[watch-voice-search]]
- [[theme-system]]

## Used by
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WG-1 | Swipes fight system gestures at the screen edge | manual on a real wrist |
| WG-2 | A swipe starting on a button triggers the button instead | manual |

## Tests
- none yet

## Manual checks
- Try each swipe and the long-press on a real wrist

## Open items
- Real-wrist ergonomics of the gesture set.
