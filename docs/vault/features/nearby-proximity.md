---
id: nearby-proximity
title: Find a friend nearby (UWB)
area: accounts-backend
status: spike
risk: high
last_verified: 2026-10-09
introduced: 2026-10-09
build: unreleased
tier: paid
value: 4
release: v1.1
cpu: "not measured (ranging runs only while the Find sheet is open)"
memory: "not measured"
battery: "not measured (needs two UWB phones)"
files:
  - ThatWay/Managers/NearbyManager.swift
  - ThatWay/Managers/NearbySession.swift
  - ThatWay/Compass/NearbySheet.swift
  - ThatWayCore/Sources/ThatWayCore/Proximity.swift
  - backend/lambda/nearby/index.mjs
  - backend/lambda/nearby/core.mjs
  - backend/scripts/smoke.sh
tests:
  - ThatWayTests/NearbyManagerTests.swift
  - ThatWayCore/Tests/ThatWayCoreTests/ProximityTests.swift
  - backend/lambda/nearby/test.mjs
manual_checks:
  - Two UWB phones (iPhone 11 or later, not the SE): both open Find on each other, distance and arrow appear within a few seconds
  - iPhone SE or simulator: Find says it is not available on this iPhone and never calls the backend
  - Walk apart to 50 m and back: the band labels and the haptic tick change once per band, without flicker
  - Backend smoke test passes (backend/scripts/smoke.sh)
depends_on: [friends, auth, core-package, phone-watch-link]
tags: [feature, area/accounts-backend, status/spike, risk/high]
---

# Find a friend nearby (UWB)

> Two friends' phones measure the distance (and direction) between themselves with Ultra Wideband. The backend only relays each phone's one-off discovery token to the other, between accepted friends, for two minutes. No location is sent or stored.

**Area:** [[area-accounts-backend]] · **Status:** spike · **Risk:** high

## What it covers
- Tap a friend on the compass screen: `NearbySheet` opens and `NearbyManager` starts a session
- Token exchange: `PUT /nearby/offers` (ours), poll `GET /nearby/offers` every 2 s for theirs, `DELETE` on stop
- `NearbySession` wraps `NISession`; capability gate (`unsupported` on simulator, iPhone SE and older phones)
- `ProximitySmoother` and bands (right here, very close, close, nearby, farther away) with hysteresis
- Phone to watch: friend name, band and whole metres via the application context (`WatchSync.proximity`)
- Backend: one Lambda `nearby` (logic in `core.mjs`, tested under macOS `jsc`), DynamoDB `NearbyOffers` with a 120 s TTL
- Setup and smoke test: `backend/SETUP.md` sections 12 and 14

## Hardware reality
- Ultra Wideband needs the U1 or U2 chip: iPhone 11 and later, **except every iPhone SE**. The test phone (SE 2nd gen) cannot range, and neither can the simulator.
- A Bluetooth distance fallback for those phones is planned for v1.1 (RSSI is rough: metres, not centimetres). Not built.
- Until two UWB phones are available, only the logic and the backend are verified.

## Depends on
- [[friends]] — Friends
- [[auth]] — Authentication
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)
- [[phone-watch-link]] — iPhone-to-watch link (travel mode)

## Used by
- (nothing else depends on it)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| NB-1 | A phone without UWB tries to start a session | test: NearbyManagerTests::aPhoneWithoutUWBNeverTouchesTheBackend |
| NB-2 | Ranging starts with the wrong friend's token | test: NearbyManagerTests::anotherFriendsOfferIsIgnored |
| NB-3 | A stranger (not an accepted friend) gets a token relayed | test: backend/lambda/nearby/test.mjs (non-friend refused) |
| NB-4 | Offers linger after the session or the friendship ends | test: backend/lambda/nearby/test.mjs (expired, unfriended and cleared offers) |
| NB-5 | The distance readout or band flickers at an edge | test: ProximityTests::smootherDoesNotFlapAtAnEdge |
| NB-6 | A token, id or body ends up in a server log | test: backend/lambda/nearby/test.mjs (log has the error name only) |
| NB-7 | The real NISession misbehaves (token never arrives, session suspended, range drops) | manual: needs two UWB phones |
| NB-8 | The route is not created in AWS, so the deploy workflow fails on its last step | manual: SETUP.md section 12 |

## Tests
- `ThatWayTests/NearbyManagerTests.swift`
- `ThatWayCore/Tests/ThatWayCoreTests/ProximityTests.swift`
- `backend/lambda/nearby/test.mjs` (run with `jsc -m`)

## Manual checks
- Two UWB phones: both open Find on each other
- iPhone SE or simulator shows the not-available message
- Smoke test passes

## Open items
- Create the table, function and three routes in AWS (SETUP.md section 12), then fill in `Config.apiBaseURL`.
- Push notification instead of polling ("Sam wants to find you") belongs to the v1.1 push work.
- Bluetooth fallback for phones without UWB.
- Camera-assisted direction (needs a camera permission) is not enabled.
