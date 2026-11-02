---
id: backend-config
title: Backend and routing configuration
area: accounts-backend
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: internal
value: 3
release: v1.0
cpu: "n/a"
memory: "n/a"
battery: "n/a"
files:
  - ThatWay/Config.swift
tests:
manual_checks:
  - Before any build for others: backendEnabled is true and the URLs are real
depends_on: []
tags: [feature, area/accounts-backend, status/shipped, risk/high]
---

# Backend and routing configuration

> `Config.swift`: the backend kill switch, Cognito IDs, API base URL (placeholder), Apple sign-in flag and the three OSRM host URLs. One wrong value changes what every user sees.

**Area:** [[area-accounts-backend]] · **Status:** shipped · **Risk:** high

## What it covers
- `backendEnabled` (true in the repo; false in the test builds installed on the phone)
- Cognito pool/client IDs, API URL placeholder
- OSRM host per profile now comes from `OSRMHosts` in ThatWayCore (shared with the watch); `Config` keeps which profiles are verified

## Depends on
- (nothing: a leaf)

## Used by
- [[auth]] — Authentication
- [[friends]] — Friends
- [[routing-provider-seam]] — Routing provider seam (OSRM + fallback)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| BC-1 | A test build ships with the gate off (or the repo is left with it flipped) | process: restored after every test build; verified by grep |
| BC-2 | Demo OSRM hosts used in production | none |

## Tests
- none yet

## Manual checks
- Before any build for others: backendEnabled is true and the URLs are real

## Open items
- Move environment values out of source (per-build config).
