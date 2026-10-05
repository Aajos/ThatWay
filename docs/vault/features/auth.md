---
id: auth
title: Authentication
area: accounts-backend
status: shipped
risk: high
last_verified: 2026-10-05
files:
  - ThatWay/Managers/AuthManager.swift
  - ThatWay/Compass/AuthScreen.swift
  - ThatWay/Managers/KeychainStore.swift
  - ThatWay/Compass/RootView.swift
tests:
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
- Refresh token restore at launch
- Gate: `Config.backendEnabled` true shows AuthScreen when signed out
- Apple sign-in code present but disabled (`appleSignInEnabled`, needs a paid team)

## Depends on
- [[backend-config]] — Backend and routing configuration
- [[backend-lambda]] — AWS Lambda backend and CI deploy

## Used by
- [[friends]] — Friends

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| AU-1 | Confirmation email never arrives, so no one can get past the gate | manual: currently failing; test builds switch the gate off |
| AU-2 | Gate on while the API URL is a placeholder | manual: see backend-config |

## Tests
- none yet

## Manual checks
- Sign up and receive the confirmation email (it did not arrive during Phase 0)

## Open items
- Fix email delivery; the installed test builds run with the gate off.
