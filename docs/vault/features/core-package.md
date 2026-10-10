---
id: core-package
title: Shared packages (ThatWayCore, ThatWayUI)
area: shared-modules
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.10
tier: internal
value: 3
release: v1.0
cpu: "n/a (code layout)"
memory: "n/a"
battery: "n/a"
files:
  - ThatWayCore/Package.swift
  - ThatWayCore/Sources/ThatWayCore/WatchSync.swift
  - ThatWay.xcodeproj/project.pbxproj
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift
  - ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift
manual_checks:
  - "`cd ThatWayCore && swift test`; build all three schemes after changing Package.swift"
depends_on: []
tags: [feature, area/shared-modules, status/shipped, risk/high]
---

# Shared packages (ThatWayCore, ThatWayUI)

> Local Swift package with two products: ThatWayCore (pure logic, Foundation + CoreLocation) and ThatWayUI (SwiftUI look). Linked into the iPhone app, its tests and the watch app by hand-edited project entries.

**Area:** [[area-shared-modules]] · **Status:** shipped · **Risk:** high

## What it covers
- `ThatWayCore` and `ThatWayUI` products, iOS 17 / watchOS 10 / macOS 14
- `swift test` runs the core tests on the Mac
- Public API surface (new members need `public`)
- Nunito.ttf bundled as a package resource
- Also home to the routing seam (`RoutingProvider`, `RoutingError`, `OSRMRoutingProvider`), the OSRM host table and the phone-to-watch payload (`WatchSync`)

## Depends on
- (nothing: a leaf)

## Used by
- [[bearing-math]] — Bearing and distance maths
- [[continuous-angle]] — Continuous angles
- [[nearby-proximity]] — Find a friend nearby (UWB)
- [[phone-watch-link]] — iPhone-to-watch link (travel mode)
- [[route-models]] — Route models
- [[routing-provider-seam]] — Routing provider seam (OSRM + fallback)
- [[theme-system]] — Themes and shared look
- [[watch-app]] — Watch app UI

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| CP-1 | A type is made public for the watch and its initialiser is forgotten: iPhone code stops compiling | build |
| CP-2 | UIKit slips into a shared target: macOS/watch build breaks | swift build on macOS (good canary) |
| CP-3 | pbxproj edited by hand: a wrong ID breaks Xcode's project load | xcodebuild -list |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/HeadingBlenderTests.swift`
- `ThatWayCore/Tests/ThatWayCoreTests/RouteAndHapticTests.swift`

## Manual checks
- `cd ThatWayCore && swift test`; build all three schemes after changing Package.swift

## Open items
- Fold `RoutingManager` onto the shared `RouteTracker`.

## Scenarios that pass through it
- [[flow-first-launch]] — First launch and permissions
