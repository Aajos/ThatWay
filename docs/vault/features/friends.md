---
id: friends
title: Friends
area: accounts-backend
status: dormant
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/FriendsManager.swift
  - ThatWay/Compass/FriendsStrip.swift
  - ThatWay/Managers/Entitlements.swift
  - ThatWay/Compass/PaywallSheet.swift
  - backend/lambda/friends/core.mjs
  - backend/scripts/friends_integration.sh
tests:
  - ThatWayTests/AuthManagerTests.swift::friendsAndNearbyNeedTheServiceAddress
  - backend/lambda/friends/test.mjs
  - ThatWayTests/EntitlementsTests.swift
manual_checks:
depends_on: [auth, backend-config]
tags: [feature, area/accounts-backend, status/dormant, risk/low]
---

# Friends

> Search users, send/accept/remove requests and list friends via API Gateway. Dormant while the API base URL is a placeholder; friends carry no location.

**Area:** [[area-accounts-backend]] · **Status:** dormant · **Risk:** low

## What it covers
- Search, request, respond, list, remove
- Token refresh on 401
- Tracing, pointing at and guiding to a friend are **paid** behind one switch (`Entitlements.canTraceFriends`, with `Entitlements.friendTracingRequiresPayment` to turn the paywall off for everyone); adding friends is always free. Today the purchase is a dummy (no money moves)
- The friends bar: a labelled **Find** button comes first, then the friends; swipe left to reveal a round search icon; it opens a search over your friends and, after 0.75 s of no typing with no friend matching, looks up the exact username and offers **+ Add** (a lower-case retry covers a stray capital)
- Backend rewrite: one tested core behind the five Lambdas; a friendship is written and removed in one transaction; a duplicate request loses cleanly; open requests are capped; search returns `{id, username}` only (it used to return every user's email)

## Depends on
- [[auth]] — Authentication
- [[backend-config]] — Backend and routing configuration

## Used by
- [[avatars-social-decor]] — Avatars, visibility and friends row
- [[nearby-proximity]] — Ultra Wideband last stretch (nearby)
- [[trace-friends]] — Trace a friend (consent, any range)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| FR-2 | Search leaked every user's email address to any signed-in searcher (was a real bug) | test: backend/lambda/friends/test.mjs (search never returns an email) |
| FR-3 | A failure between the two writes leaves half a friendship | test: backend/lambda/friends/test.mjs (a failure leaves neither row) |
| FR-4 | Two simultaneous requests overwrite each other | test: backend/lambda/friends/test.mjs (a race loses with a 409) |
| FR-5 | One account spams requests | test: backend/lambda/friends/test.mjs (too many open requests) |
| FR-1 | Every call fails while `apiBaseURL` is the placeholder | test: AuthManagerTests::friendsAndNearbyNeedTheServiceAddress (now fails with a plain message instead of a network error); the real address is still to be set |

## Tests
- none yet

## Manual checks
- none recorded

## Open items
- Provision the API and set the URL.
