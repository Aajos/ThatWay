---
id: p11-apple-developer
title: Getting the Apple Developer Program
type: process
tags: [process, money]
---
# Getting the Apple Developer Program

Needed for: TestFlight, the App Store, **push notifications** (trace requests), Sign in with Apple, a signed watch app on a real watch, and App Store Connect. Your plan puts enrolment at **15 November 2026** (milestone c01); identity checks can take days, so start earlier than you think.

## Status (checked 2026-10-17)
- Enrolled as an **Individual** (team *Aadit Joshi*, ID `K5N4HVV7VG`, a paid team, not a free one); Xcode has the account and the project already points at the team with automatic signing.
- The SE 2nd gen is visible to the Mac as a paired, available device, so the app can be installed on it now.
- Still to do, in order: install on the phone (and the watch); create the App Store Connect record and upload to TestFlight; build real push (APNs key, device tokens, a sender); Paid Applications agreement, banking and tax; Small Business Program.

## Before you start (10 minutes)
- [ ] An **Apple ID** you will keep long-term (the app, the money and the review history are tied to it). Turn on two-factor authentication.
- [ ] Decide **Individual or Organization**:
  - *Individual*: fastest (usually same day to 48 hours); the App Store shows **your personal legal name** as the seller.
  - *Organization* (a company or sole trader with an ABN is not enough on its own: Apple wants a legal entity and a **D-U-N-S number**, which is free but can take a week or two): the seller shows the company name. Choose this only if you want that.
  - You can start as an Individual and move later, but it is a process: the app transfers cleanly, the name does not change without it.
- [ ] A **photo ID** (passport or driver licence) for the identity check.
- [ ] A card for the fee: **US$99 a year** (about **A$149 to A$150**; Apple shows the exact local price at checkout). Fee waivers exist only for non-profits, education and government.

## Enrol
1. On your iPhone open the **Apple Developer** app (free in the App Store), sign in, go to **Account → Enroll**. (Or on the web: developer.apple.com/programs/enroll.)
2. Confirm your legal name and address (they must match your ID), accept the agreement, pay.
3. Complete the **identity verification** (scan the ID with the phone, take a selfie).
4. Wait for the email: **"Welcome to the Apple Developer Program"**. Status shows at developer.apple.com/account.

## After approval (the part that unblocks the app)
- [x] **Bundle ID chosen (2026-10-17): `com.thatway.app`** (watch: `com.thatway.app.watchkitapp`). It cannot change after the first App Store submission without becoming a different app. If Apple refuses it as already taken when Xcode registers it, pick another before any App Store Connect record exists.
- [ ] Xcode, **Settings → Accounts**: add the Apple ID. On both targets (ThatWay, ThatWayWatch) choose the new **Team** under Signing & Capabilities. This is the step that lets the watch app install on a real watch.
- [ ] Add capabilities: **Push Notifications**, **Sign in with Apple** (re-add `CODE_SIGN_ENTITLEMENTS = ThatWay/ThatWay.entitlements`, set `Config.appleSignInEnabled = true`), and background modes you already use.
- [ ] Create an **APNs key**: developer.apple.com → Certificates, Identifiers & Profiles → Keys → + → Apple Push Notifications service. Download the `.p8` once (it cannot be downloaded again), keep it **out of the repo**; it is what the backend will use to send "Sam wants to trace you".
- [ ] **App Store Connect**: create the app record (name, bundle ID, SKU); then **Agreements, Tax, and Banking**: accept the Paid Applications agreement, add your Australian bank account and tax details (needed before any paid tier or in-app purchase).
- [ ] Apply for the **App Store Small Business Program** (15% commission instead of 30% while under US$1M a year). Your plan assumes this; it is a separate application in App Store Connect after enrolment.
- [ ] Upload a first build to TestFlight (internal testers need no review; external testers need a short Beta App Review).

## Costs and dates to put in the calendar
| What | When |
|---|---|
| Enrol | Start by early November (plan: 15 Nov 2026) |
| Renewal | Every year on the enrolment date (it auto-renews: check the card) |
| AWS Free Plan ends | 24 March 2027 (separate, see [[P3 Costs]]) |

## What it unlocks, in the order you will use it
1. Install the watch app on your real watch: closes [[watch-app]] WA-1.
2. Remote push for trace requests: replaces the local-notification seam in [[trace-friends]].
3. TestFlight: [[P6 Live testing]] stages S3 and S4 in [[P1 Stages and the MVP line]].
4. The paid tier and purchase and restore (v1.1).

Related: [[P3 Costs]], [[P10 Backend and proximity runbook]].
