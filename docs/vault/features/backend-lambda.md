---
id: backend-lambda
title: AWS Lambda backend and CI deploy
area: accounts-backend
status: external
risk: medium
last_verified: 2026-10-05
files:
  - backend/lambda/README.md
  - .github/workflows/deploy-backend.yml
  - backend/SETUP.md
tests:
manual_checks:
depends_on: []
tags: [feature, area/accounts-backend, status/external, risk/medium]
---

# AWS Lambda backend and CI deploy

> Node.js Lambdas for post-confirmation, the friends API and the (not live) Sign in with Apple functions, deployed by a GitHub Action over OIDC on pushes to main.

**Area:** [[area-accounts-backend]] · **Status:** external · **Risk:** medium

## What it covers
- Six deployed functions
- Sign in with Apple functions written but not live
- OIDC role, no stored keys

## Depends on
- (nothing: a leaf)

## Used by
- [[auth]] — Authentication

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| BL-1 | Email delivery for sign-up confirmation (SES) not working | manual |

## Tests
- none yet

## Manual checks
- none recorded

## Open items
- Not modified by the app work; verify end to end.
