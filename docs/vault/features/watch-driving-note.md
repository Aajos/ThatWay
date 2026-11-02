---
id: watch-driving-note
title: Watch driving note
area: watch
status: spike
risk: low
last_verified: 2026-11-02
introduced: 2026-10-05
build: 0.10
tier: free
value: 3
release: v1.0
cpu: "n/a"
memory: "n/a"
battery: "n/a"
files:
  - ThatWayWatch/MainView.swift
  - ThatWayWatch/WatchModel.swift
  - ThatWayWatch/ThatWayWatchApp.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchModeTests
manual_checks:
  - The watch main screen shows "Not safe to use while driving" under the compass, at every watch size
  - Phone in Drive mode: the watch does nothing different (keeps its own walk, run or cycle mode), and never closes
depends_on: [phone-watch-link, watch-travel-modes]
tags: [feature, area/watch, status/spike, risk/low]
---

# Watch driving note

> The watch says, on its main screen, that it is not safe to use while driving. That is all. It does not detect driving, block anything, show a countdown or close itself. (Decided 2026-11-02; the earlier "drive guard" that stopped everything and quit with `exit(0)` was removed, partly because App Review frowns on apps that terminate themselves.)

**Area:** [[area-watch]] · **Status:** spike · **Risk:** low

## What it covers
- One static line under the compass: "Not safe to use while driving"
- The watch offers walk, run and cycle only; a Drive mode sent by the phone is ignored and the watch keeps its own mode
- Removed: `DriveNoticeView`, `blockedByDriving`, `WatchPolicy`, `TravelMode.isSafeOnWatch`, the session refusal, the 6-second close

## Depends on
- [[phone-watch-link]]
- [[watch-travel-modes]]

## Used by
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| WDG-1 | Someone uses the watch while driving: nothing stops them, only the note | by design: the note is the whole rule (decided 2026-11-02) |
| WDG-2 | The note crowds the compass on a small watch | manual: check the 40 mm and 42 mm sizes |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchModeTests`
