---
id: phone-watch-link
title: iPhone-to-watch link (travel mode)
area: watch
status: spike
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Managers/WatchLink.swift
  - ThatWayWatch/PhoneLink.swift
  - ThatWayCore/Sources/ThatWayCore/WatchSync.swift
  - ThatWay.xcodeproj/project.pbxproj
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchSyncTests
manual_checks:
  - Paired simulators: set the phone to Drive, watch receives it (done once)
  - Real devices: change the phone mode, watch reacts
depends_on: [travel-modes, core-package]
tags: [feature, area/watch, status/spike, risk/medium]
---

# iPhone-to-watch link (travel mode)

> The iPhone tells the paired watch its travel mode over WatchConnectivity (latest value kept as the application context, plus an immediate message when reachable). Only the mode is sent. The watch app is embedded in the iPhone app as its companion so the link can exist.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** medium

## What it covers
- `WatchLink` (iPhone) sends on every mode change and on activation
- `PhoneLink` (watch) reads the stored context at launch and live messages
- `WatchSync` payload shared in ThatWayCore
- Watch target embedded in the iPhone app (`Embed Watch Content`), companion bundle id `...ThatWay.watchkitapp`
- Verified between paired simulators

## Depends on
- [[travel-modes]]
- [[core-package]]

## Used by
- [[watch-drive-guard]] — Watch drive guard

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| PWL-1 | Embedding the watch app makes every iPhone device build need a signed watch profile: builds fail until Xcode has the account signed in | manual: this will bite command-line device builds |
| PWL-2 | Watch app not installed or phone not paired: no mode arrives, nothing is blocked | manual |
| PWL-3 | The stored context takes about 3 s to reach a cold-launched watch app | manual: seen in the simulator |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift::WatchSyncTests`

## Manual checks
- Paired simulators: set the phone to Drive, watch receives it (done once)
- Real devices: change the phone mode, watch reacts

## Open items
- Persist the last phone mode on the watch to close the 3 s window.
