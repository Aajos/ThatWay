---
id: watch-drive-guard
title: Watch drive guard
area: watch
status: spike
risk: high
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.10
tier: free
value: 4
release: later
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWayWatch/DriveNoticeView.swift
  - ThatWayWatch/PhoneLink.swift
  - ThatWayWatch/WatchModel.swift
  - ThatWayWatch/SessionController.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchSyncTests
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchModeTests
manual_checks:
  - Phone in Drive mode: the watch shows the notice and closes
  - Phone back to Walk: the watch app works again
depends_on: [phone-watch-link, watch-session, watch-travel-modes]
tags: [feature, area/watch, status/spike, risk/high]
---

# Watch drive guard

> If the iPhone is in Drive mode the watch refuses to guide: it stops location, heading, any session and route, shows why, and closes itself six seconds later. The safety rule behind it: glancing at a wrist while driving is unsafe.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** high

## What it covers
- Triggered by the phone’s travel mode (live message or stored context)
- Stops sessions, location, heading and the route
- "Not while driving" notice with a countdown and a notification haptic
- `exit(0)` after 6 s (watchOS has no quit: caveat for App Review)
- Session start refused while blocked
- Verified in the simulator, standalone and between paired simulators

## Depends on
- [[phone-watch-link]]
- [[watch-session]]
- [[watch-travel-modes]]

## Used by
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WDG-1 | The guard depends on a connection to the phone: an unpaired or out-of-range watch is not blocked | by design: documented |
| WDG-2 | About 3 s between launching the watch app and learning the phone is driving | manual: seen in the simulator |
| WDG-3 | Self-termination via exit() may be rejected in App Review | none: revisit before shipping |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchSyncTests`
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchModeTests`

## Manual checks
- Phone in Drive mode: the watch shows the notice and closes
- Phone back to Walk: the watch app works again

## Open items
- Persist the phone mode so a cold launch while driving blocks immediately.
