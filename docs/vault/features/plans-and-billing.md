---
id: plans-and-billing
title: Trace plans: StoreKit purchase, server verification, expiry
area: accounts-backend
status: spike
risk: high
last_verified: 2026-10-17
introduced: 2026-10-17
build: unreleased
tier: paid
value: 5
release: v1.1
cpu: "not measured (idle unless a prompt is on screen)"
memory: "not measured"
battery: "not measured (no background work)"
files:
  - ThatWay/Managers/PlanStore.swift
  - ThatWay/Managers/Entitlements.swift
  - ThatWay/Managers/TraceNotifier.swift
  - ThatWay/Compass/PaywallSheet.swift
  - backend/lambda/plan/core.mjs
  - backend/lambda/plan/appleJws.mjs
  - backend/lambda/plan/index.mjs
  - StoreKit/Plans.storekit
tests:
  - ThatWayTests/PlanStoreTests.swift
  - ThatWayTests/EntitlementsTests.swift
  - backend/lambda/plan/test.mjs
  - backend/scripts/grants_integration.sh
manual_checks:
  - In Xcode, set the scheme StoreKit configuration to StoreKit/Plans.storekit and buy trace3: the paywall shows the price, the purchase is sent to the server, and the plan shows ends in 3 h
  - A subscription renewal arrives while the app is open and extends the plan
  - Restore purchases on a second phone brings back a lifetrace
  - A plan ending 30 minutes away shows a local notification
  - Once PLAN_CHECK=on, a tracer with no plan gets 402 and the paywall
depends_on: [auth]
tags: [feature, area/accounts-backend, status/spike, risk/high]
---

# Trace plans: StoreKit purchase, server verification, expiry

> trace3 (3 hours), trace24 (24 hours), trace+ (monthly), lifetrace (once). StoreKit 2 sells them; the **server** checks Apple's signature and decides what the plan is. The phone believes the server, not itself.

**Area:** [[area-accounts-backend]] · **Status:** spike · **Risk:** high

## How it works
- The app buys with StoreKit 2, then sends Apple's **signed transaction (JWS)** to `POST /plan/sync`. `appleJws.mjs` accepts it only if the certificate chain (leaf, intermediate, root) is valid, every link is signed by the next, the root is **Apple Root CA - G3 pinned by fingerprint**, the leaf and intermediate carry Apple's App Store marker extensions (so an ordinary developer certificate under the same root cannot forge a purchase), and the signature verifies. Checked on 2026-10-17 with a synthetic chain on Node 24 in Lambda (13 cases: tampered payload, no marker, wrong root, two certificates, bad algorithm, expired, swapped leaf and more); a real Apple-signed transaction has **not** been seen yet.
- `plan/core.mjs` credits it: a pass starts when claimed and **stacks**; a subscription lasts to Apple's renewal date; lifetrace is year 2100. A transaction counts once and for one account; a subscription or lifetime purchase belongs to one account at a time (claiming it elsewhere moves it). Refunded, other-app, unknown-product and (optionally) sandbox purchases are refused.
- A purchase is **finished** with Apple only after the server has recorded it, so a failure retries and never loses it. "Restore" re-sends Apple's current transactions.
- **Expiry**: tracing ends the moment the plan does, on the phone (`Entitlements.planHasEnded`) and on the server (`authorise` checks `planUntil`). A local notification fires 30 minutes before the end. Renewing does not revive a trace that already ended.

## Switching the server check on
`grants` and `nearby` read `Entitlements` only when `PLAN_CHECK=on` is set in their environment; until then every tracer counts as having a plan, so the flow can be tested with the dummy unlock. Flip it (and `Entitlements.serverIsAuthoritative` in the app) when products exist in App Store Connect. Set `ALLOW_SANDBOX=off` on the `plan` function once the app is live.

## Needs from you
App Store Connect: the Paid Apps agreement and banking, the four products with these exact ids (`com.thatway.trace3`, `.trace24`, `.traceplus`, `.lifetrace`) and a subscription group, a terms and a privacy-policy URL. Apple's 15% Small Business Program applies after enrolment.

## Used by
- [[trace-grants]] — Standing trace permissions, passes, blocking

