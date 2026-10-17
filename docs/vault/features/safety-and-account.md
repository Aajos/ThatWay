---
id: safety-and-account
title: Block, report, emergency control, close or deactivate an account
area: accounts-backend
status: spike
risk: high
last_verified: 2026-10-17
introduced: 2026-10-17
build: unreleased
tier: free
value: 5
release: v1.1
cpu: "not measured (idle unless a prompt is on screen)"
memory: "not measured"
battery: "not measured (no background work)"
files:
  - ThatWay/Managers/SafetyManager.swift
  - ThatWay/Compass/SafetySheets.swift
  - ThatWay/Compass/TraceCopy.swift
  - backend/lambda/grants/core.mjs
  - backend/lambda/account/core.mjs
  - backend/lambda/account/index.mjs
  - backend/lambda/friends/core.mjs
  - ThatWayCore/Sources/ThatWayCore/Grants.swift
tests:
  - ThatWayTests/SafetyManagerTests.swift
  - ThatWayTests/TraceCopyTests.swift
  - backend/lambda/account/test.mjs
  - backend/lambda/grants/test.mjs
  - backend/scripts/grants_integration.sh
  - ThatWayCore/Tests/ThatWayCoreTests/GrantsTests.swift
manual_checks:
  - Press and hold a friend: block, report and the emergency control appear; blocking removes them from the friends row and ends any trace both ways
  - A blocked person cannot find you in search, and their request just stays pending then disappears
  - The emergency button opens the dialler with the local number and does not call
  - Deactivate, sign in again: the Welcome back screen offers Reactivate, Delete everything or Sign out
  - Delete everything with a typed DELETE and the owner check: the account is gone from Cognito, Users and every table
depends_on: [friends, auth]
tags: [feature, area/accounts-backend, status/spike, risk/high]
---

# Block, report, emergency control, close or deactivate an account

> The parts of the app that protect a person from another person, or from the app. None of it needs the owner check (except destroying an account), none of it is throttled, and none of it tells the other person anything.

**Area:** [[area-accounts-backend]] · **Status:** spike · **Risk:** high

## What each does
- **Block**: removes the friendship, every permission in both directions, trace rows, UWB offers and any last position, and hides each from the other in search and lists. Not reversible by itself (unblocking does not restore the friendship). A request to someone who blocked you is stored as a phantom and looks like any unanswered request.
- **Report**: five categories and an optional 500-character note, stored in `Reports` for a year, never with a location, never throttled. Reporting offers "also block"; the report is always sent first. **Nobody is notified when a report arrives**: who reads them is an open decision, and the app promises no reply time.
- **Emergency control**: opens the phone's dialler with the regional number (000, 911, 999, 111, 110, 190, else 112). It does not call. The screen says ThatWay is not an emergency service and cannot send help.
- **Delete everything** (`POST /account/delete`, needs `confirmed`): friendships and requests both rows, grants in both roles, position, blocks made and received, old trace rows, offers, the purchase record, the profile, and the Cognito sign-in. Steps are repeatable: a stopped delete is finished by the daily sweep after a day. The app signs out only after the server confirms. **Kept**: reports made by or about the account (a year, no locations) and the purchase claim rows (opaque ids), both stated in the warning or here.
- **Deactivate and keep my plan**: the same clean-out of everything social, but the sign-in and plan stay; hidden from search; **deleted completely after 12 months** by the daily sweep (`rate(1 day)` EventBridge rule on the `account` function). Reactivating brings the profile back, not the friends.

## Wording
The deletion and deactivation text lives in `TraceCopy.swift` and is covered by tests so it keeps saying what actually happens (Apple handles purchases and refunds; a subscription is cancelled in Apple ID settings; reports may be kept).

## Used by
- [[trace-grants]] — Standing trace permissions, passes, blocking

