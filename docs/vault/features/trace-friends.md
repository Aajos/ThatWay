---
id: trace-friends
title: Trace a friend (consent, any range)
area: accounts-backend
status: spike
risk: high
last_verified: 2026-10-12
introduced: 2026-10-12
build: unreleased
tier: paid
value: 5
release: v1.1
cpu: "not measured (polls every 3 s while a trace is active, every 10 s otherwise, only while the app is in front)"
memory: "not measured"
battery: "not measured (needs a device trace; uploads a position every 3 to 15 s while active)"
files:
  - ThatWay/Managers/TraceManager.swift
  - ThatWay/Managers/TraceNotifier.swift
  - ThatWay/Compass/TracePill.swift
  - ThatWay/Compass/FriendsStrip.swift
  - ThatWayCore/Sources/ThatWayCore/Trace.swift
  - backend/lambda/trace/index.mjs
  - backend/lambda/trace/core.mjs
tests:
  - ThatWayTests/TraceManagerTests.swift
  - ThatWayTests/FollowFriendTests.swift
  - ThatWayCore/Tests/ThatWayCoreTests/TraceTests.swift
  - backend/lambda/trace/test.mjs
manual_checks:
  - Two phones, two accounts that are friends: ask, see the pending pill on one and Accept / Decline on the other, accept, see the arrow and distance on both
  - Walk apart, then together: the arrow turns with the phone; under about 40 m on UWB phones the source changes to UWB
  - Either side stops: the other side is told within a few seconds, and positions stop flowing
  - Decline: the asker sees "declined" and cannot ask again for a minute
  - Kill the app mid-trace and reopen: it resumes if the server still has the session
  - Confirm no map, coordinate or place name appears anywhere on the screen or in logs
  - Accept a trace, lock the phone and drive: the other side keeps seeing you for the whole trip
  - Tap Guide me while the friend is moving: the route keeps up with them without flicker
depends_on: [friends, auth, nearby-proximity, core-package, location-manager, heading]
tags: [feature, area/accounts-backend, status/spike, risk/high]
---

# Trace a friend (consent, any range)

> Tap a friend, they accept, and a temporary pill points at them with the distance: GPS at any range, anywhere in the world, with Ultra Wideband taking over for the last stretch. Direction and distance only: never a map, never a coordinate on screen.

**Area:** [[area-accounts-backend]] · **Status:** spike · **Risk:** high

## What it covers
- **Consent, enforced by the server:** a request creates a pending row on both sides; a position is relayed only after the other person accepts; either side can end at any time; requests expire in 10 min; an active session is kept alive by use (each person's row expires 60 minutes after their last position upload, so a tunnel or dead zone does not end it) and ends at 24 hours at the latest
- **The pill** replaces the friends row (and sits above the instruction while guiding): *asking* (you, request pending, them), *incoming* (them, Accept or Decline, you), *active* (you, arrow and distance, them)
- **Any range:** the distance and bearing come from the two GPS positions (great circle, so intercontinental works); `TraceReading.distanceText` formats "12 m", "3.4 km", "8,240 km"
- **UWB handoff:** inside 40 m of GPS distance the phone starts a UWB session ([[nearby-proximity]]); a UWB reading younger than 3 s wins, otherwise GPS; released beyond 60 m
- **Notification:** a *local* notification when a request arrives while the app is not in front. There is no remote push (no push entitlement on a free Apple team): requests are seen when the app is running
- **Point and Guide at a friend, however far, however they move:** the active pill's *Point me* aims the needle at them at any range (a great-circle bearing, no road route needed); *Guide me* starts turn-by-turn to their live position. The destination follows them: the road route is re-fetched only when they have moved more than max(40 m, 10% of the remaining distance) and at most once every 20 s. Over distances with no road route (another continent) the compass stays on straight-line pointing
- **Always on once accepted:** an accepted trace keeps background location running (`UIBackgroundModes: location`), so it does not stop when the screen locks mid-trip; before acceptance, and after it ends, nothing is shared or running
- **Safety:** positions held in memory only; never logged, persisted or sent to the watch; the server serves a position only to the partner of an ACTIVE session, only under 90 s old, only while the friendship stands (checked in both directions)

## Depends on
- [[friends]] — Friends
- [[auth]] — Authentication
- [[nearby-proximity]] — Ultra Wideband last stretch
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI)
- [[location-manager]] — LocationManager (fixes and permission)
- [[heading]] — Heading pipeline

## Used by
- [[walkie-talkie]] — Walkie talkie (push to talk in a trace)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| TR-1 | A position is shared before the other person accepts | test: TraceManagerTests::nothingIsSharedUntilTheyAccept; test: backend/lambda/trace/test.mjs (no position before consent) |
| TR-2 | A position reaches someone who is not the partner of an active session | test: backend/lambda/trace/test.mjs (a third friend sees nothing; an outsider cannot post) |
| TR-3 | A stale position is shown as live | test: backend/lambda/trace/test.mjs (stale position withheld); test: TraceTests::staleFriendIsFlagged |
| TR-4 | A poll in flight brings back a trace the person just ended | test: TraceManagerTests::aPollThatWasInFlightCannotBringBackAnEndedTrace |
| TR-5 | A dropped connection ends a trace | test: TraceManagerTests::aDroppedConnectionDoesNotEndATrace |
| TR-6 | A request is spammed after a decline | test: backend/lambda/trace/test.mjs (cannot re-ask during the cool-off; open requests are capped) |
| TR-7 | A position, id or body appears in a server log | test: backend/lambda/trace/test.mjs (log has the error name only) |
| TR-8 | Unfriending leaves a live session | test: backend/lambda/trace/test.mjs (unfriended session hidden and cleaned up) |
| TR-9 | UWB runs far away or never hands back to GPS | test: TraceManagerTests::theRadioStartsOnlyWhenClose; test: TraceTests::uwbEngagementHasHysteresis |
| TR-10 | The arrow points the wrong way when the compass is wrong | manual: depends on [[compass-health]]; the arrow is dimmed when the heading is not reliable |
| TR-11 | An incoming request is never seen because the app is suspended (no push) | manual: known gap until the Apple Developer Program is enrolled |
| TR-13 | The trace stops partway through a long trip | test: backend/lambda/trace/test.mjs (a long trip does not drop the trace; a 40 minute dead zone does not end it) |
| TR-14 | Chasing a moving friend hammers the routing service | test: FollowFriendTests::guidingFetchesOnceAndThenChasesOnlyWhenTheyMoveEnough |
| TR-15 | A route to a friend is saved and resurrected on relaunch as a stale place | test: FollowFriendTests::aRouteToAMovingFriendIsNeverSavedForRelaunch |
| TR-16 | A hard cap is missing, so a forgotten trace shares for days | test: backend/lambda/trace/test.mjs (the 24 hour cap) |
| TR-12 | Remote battery cost of 3 s polling and uploads | none: not measured; see [[P7 Optimisation checks]] |

## Tests
- `ThatWayTests/TraceManagerTests.swift` (the flow, with a fake server and fake radio)
- `ThatWayCore/Tests/ThatWayCoreTests/TraceTests.swift` (fusion, range, formatting)
- `backend/lambda/trace/test.mjs` (the server rules, 39 checks, `jsc -m`)

## Manual checks
- Two phones, two friend accounts: the whole flow
- Walk apart and together; confirm UWB takeover on two UWB phones
- No map, coordinate or place name anywhere

## Open items
- Create the table, function and five routes in AWS (`backend/scripts/aws.sh trace --apply`), then run the smoke test.
- Remote push (APNs) once the Apple Developer Program is enrolled; the notifier is a seam.
- Walkie talkie in a trace chain: see [[walkie-talkie]].
- Watch integration: deliberately not done (friends are on the phone's main screen only for now).
- Battery cost of polling every 3 s: measure on the device; consider adaptive intervals and a server-sent signal.
