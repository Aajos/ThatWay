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
tests:
  - ThatWayTests/AuthManagerTests.swift::friendsAndNearbyNeedTheServiceAddress
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

## Depends on
- [[auth]] — Authentication
- [[backend-config]] — Backend and routing configuration

## Used by
- [[avatars-social-decor]] — Avatars, visibility and friends row
- [[nearby-proximity]] — Find a friend nearby (UWB)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| FR-1 | Every call fails while `apiBaseURL` is the placeholder | test: AuthManagerTests::friendsAndNearbyNeedTheServiceAddress (now fails with a plain message instead of a network error); the real address is still to be set |

## Tests
- none yet

## Manual checks
- none recorded

## Open items
- Provision the API and set the URL.
