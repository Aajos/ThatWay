---
id: auth
title: Authentication
area: accounts-backend
status: shipped
risk: high
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
  - ThatWay/Managers/AuthManager.swift
  - ThatWay/Compass/AuthScreen.swift
  - ThatWay/Managers/KeychainStore.swift
  - ThatWay/Compass/RootView.swift
tests:
  - ThatWayTests/AuthManagerTests.swift
manual_checks:
  - Sign up and receive the confirmation email (it did not arrive during Phase 0)
depends_on: [backend-config, backend-lambda]
tags: [feature, area/accounts-backend, status/shipped, risk/high]
---

# Authentication

> Cognito sign-up, confirmation, sign-in, token refresh, sign out, optional Sign in with Apple (disabled), refresh token in the Keychain, and the sign-in gate in RootView.

**Area:** [[area-accounts-backend]] · **Status:** shipped · **Risk:** high

## What it covers
- Sign up / confirm code / sign in / sign out
- Send a new code, start over, and recovery from an unconfirmed account (sign-in or a repeated sign-up goes back to the code step)
- Session restore at launch: the cached id token restores the signed-in state immediately (works offline); the refresh runs in the background and only a server rejection signs the user out; other failures keep the tokens. Requests time out at 10 s
- Gate: `Config.backendEnabled` true shows AuthScreen when signed out
- Apple sign-in code present but disabled (`appleSignInEnabled`, needs a paid team)

## Depends on
- [[backend-config]] — Backend and routing configuration
- [[backend-lambda]] — AWS Lambda backend and CI deploy

## Used by
- [[friends]] — Friends
- [[nearby-proximity]] — Find a friend nearby (UWB)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| AU-1 | Confirmation email never arrives, so no one can get past the gate | manual: still open on the AWS side (SETUP.md section 13); the app now offers Send a new code, and sign-in with an unconfirmed account goes back to the code step |
| AU-4 | A sign-up left unconfirmed becomes a dead end (sign-in error, username taken) | test: AuthManagerTests::signingInBeforeConfirmingSendsANewCodeInsteadOfDeadEnding |
| AU-3 | Launching with no network signed the user out or showed a blank screen (was a real bug) | manual: gate-on build in airplane mode; fixed |
| AU-2 | Gate on while the API URL is a placeholder | manual: see backend-config |

## Tests
- none yet

## Manual checks
- Sign up and receive the confirmation email (it did not arrive during Phase 0)

## Open items
- Fix email delivery; the installed test builds run with the gate off.
