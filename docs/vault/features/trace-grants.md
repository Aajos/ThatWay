---
id: trace-grants
title: Standing trace permissions, passes, blocking
area: accounts-backend
status: spike
risk: high
last_verified: 2026-10-17
introduced: 2026-10-17
build: unreleased
tier: paid
value: 5
release: v1.1
cpu: "not measured (polls every 5 to 30 s while the app is in front, never in the background)"
memory: "not measured"
battery: "not measured (needs a device trace; uploads at most every 30 s to 2 min, only while someone may trace you and the app is open)"
files:
  - backend/lambda/grants/core.mjs
  - backend/lambda/grants/index.mjs
  - backend/lambda/friends/core.mjs
  - backend/lambda/nearby/core.mjs
  - ThatWay/Managers/TraceManager.swift
  - ThatWay/Managers/TraceNotifier.swift
  - ThatWay/Compass/TraceCopy.swift
  - ThatWay/Compass/TraceSheets.swift
  - ThatWay/Compass/TracePill.swift
  - ThatWay/Compass/TracedByYouSection.swift
  - ThatWay/Compass/StatusBanners.swift
  - ThatWay/Compass/FriendsStrip.swift
  - ThatWayCore/Sources/ThatWayCore/Grants.swift
tests:
  - backend/lambda/grants/test.mjs
  - backend/lambda/friends/test.mjs
  - backend/lambda/nearby/test.mjs
  - backend/scripts/grants_integration.sh
  - ThatWayTests/TraceManagerTests.swift
  - ThatWayTests/TraceCopyTests.swift
  - ThatWayCore/Tests/ThatWayCoreTests/GrantsTests.swift
manual_checks:
  - Two phones, two friends: ask (once, then keep tracing), see the banner and the request card on the other, allow with Face ID, see Accepted and a direction with its age
  - A stranger is granted 3 hours, then cannot see the person at hour 3 and a minute, or the next day
  - Removing the friend or blocking ends every grant at once, with no hint to the other person which it was
  - The traced person can see who may trace them, until when, when they last looked and how far, and stop it in one tap
  - Opening the compass during an active window runs every safety check on the server first
  - On a phone with no Face ID, passcode or app passcode, allowing a trace is blocked until an app passcode is set up with an email code
depends_on: [friends, auth, nearby-proximity, owner-authentication, safety-and-account, plans-and-billing]
tags: [feature, area/accounts-backend, status/spike, risk/high]
---

# Standing trace permissions, passes, blocking

> **Status spike: built end to end on 2026-10-17, not yet proven on two real phones.** Server (`grants`, `account`, `plan`, friends and nearby changes) is **deployed and verified against the real API** with throwaway accounts (`backend/scripts/grants_integration.sh`, 44 checks). The app side is built and unit tested (264 app tests, 103 grants checks); it has **not** been used on two real phones yet, and UWB has never run on real radios. The server's plan check is OFF until real purchases exist (see [[plans-and-billing]]). Remote push is not set up (needs your APNs key).

**Area:** [[area-accounts-backend]] · **Status:** spike · **Risk:** high

## Plans (named by the big feature)
**trace3** (3 hours, about $0.99), **trace24** (24 hours, about $2.99), **trace+** (monthly, $7.99), **lifetrace** ($499, kept: it also covers a very long-lived user). Apple is the seller; refunds are Apple's process (see blind spot 11).

## The model (decided 2026-10-17)
- **One target at a time.** A tracer can switch between friends without the first connection expiring. Each friend's permission is separate.
- **Two kinds of permission, chosen by the traced person:** a **one-off** (ends when the tracer switches to someone else or stops) or an **always-trace window** with a slider from 30 minutes to a **hard maximum of 24 hours**. Past 24 hours a new request and a new yes are always required, however long the friendship has lasted. No exceptions.
- **Granting needs a second confirmation, a disclaimer, and device-owner authentication** (Face ID, Touch ID or the passcode), so someone holding an unlocked phone cannot approve a trace. A phone with no passcode cannot grant at all.
- **Auto accept covers adding friends only.** Tracing always needs its own request and its own grant. A per-friend control: who may ask to trace me (ask / never).
- **The tracer sees only:** "Accepted" when granted, how long their *own plan* has left, and "User cannot be traced" at any end or error (expiry, removal and block look the same). They never see how long a grant has left.
- **The traced person sees** a persistent banner ("1 person can trace you", or the number), which opens the You page: a horizontal row of who may trace them, until when, and a Stop button. A grant ends at its time whether or not they are watching.
- **"Request new location"** by the tracer: at most once every 2 minutes (enforced on the server). Each fetch inside the grant and the plan returns a position and sends the traced person "X is still tracing you. Stop?", at most once every 30 minutes.
- **Every use is authorised on the server**, every time: friendship both ways, no block either way, grant live inside its window, the tracer's plan (the server's clock), the account still exists. The nearby (UWB) relay uses the same check.
- **Not continuous.** Positions move only while a client is active, or on a best-effort wake-up (blind spot 4). A person who opens the app once a month does not cause a thousand requests: the app syncs everything routine in **one periodic request**; safety actions (block, unfriend, stop tracing, stop) are always sent immediately and are never throttled for the person doing them.
- **Plan expiry** needs no server ping: the server compares timestamps when a request arrives, and the app schedules a local "your trace3 ends in 30 minutes" notification when the plan starts.
- **Profile pictures are never shared** between users (avatars stay on the device).

## Safety, report, block, delete
- **Block, report, complaint** are in the app, one tap from anywhere a person appears. Blocking and reporting are not throttled for the person using them. A severity control that opens the phone's dialler to the local emergency number (000, 911, 112 by region): it only opens the dialler, the person presses call, and the screen says plainly that ThatWay is not an emergency service.
- **Account deletion deletes everything**: Cognito, Users, Friends, grants, blocks, requests. The person is told exactly what goes. A separate, clearly named, opt-in choice ("deactivate and keep my plan") keeps only the purchase record tied to the Apple ID, never friends, locations or grants, for a stated period.
- **Biometric check** before granting any trace and before changing a grant.

## Blind spots (each needs an answer before launch)
1. Today's trace is two-way: the tracer's position also reaches the traced person's phone (hidden in the app, not blocked by the server). Grants must be one-way, enforced by the server.
2. Stalking and coercion is the real risk: nothing starts without the traced person's active, authenticated yes; persistent banner; the system location indicator; reminders; one-tap stop; a "last looked at" time.
3. Auto accept plus tracing was a harassment path: closed by "auto accept is for adding only" and the per-friend ask/never control.
4. Waking a phone in a pocket is limited by iOS: silent pushes are throttled (a few an hour), not delivered if the app was force-quit, and a one-shot fix from the background needs **Always** location. Honest design: last known position with its age, a best-effort "request new location", live only while the traced phone's app is active.
5. Apple requires a report and block mechanism and a complaints contact for apps with user-to-user content (Guideline 1.2) and real in-app account deletion (5.1.1(v)).
6. Privacy: App Store privacy label (precise location shared with other users), a matching privacy policy, a minimum age (17+ or an age gate), and a record of consent (when, which wording). Have a lawyer review the terms and policy; "legal proof" is not something to settle by design alone.
7. "Paid" must be checked on the server, not only in the app.
8. Time: server clock only; a plan starts when activated and stacks when bought again.
9. Offline traced phone: the grant simply runs out on the server; they can revoke later and the server refuses at once.
10. Show the *granted* time to the traced person, never the maximum asked for.
11. **"No refunds" cannot be promised in Australia.** Australian Consumer Law guarantees cannot be excluded by a notice. Apple, as the seller, decides refunds. Say "purchases are processed by Apple; refund requests go to Apple" instead.
12. **Showing the traced person "how far" the tracer is** means the tracer's position is shared back with them, which the tracer did not agree to. Options: coarse bands only ("within 100 m / 1 km / farther"), disclosed to the tracer at request time; or only "last looked at". Needs a decision.
13. Keeping data on deletion "in case they return" conflicts with deletion duties unless it is explicit, opt-in, time-limited and limited to the purchase record. Hence "deactivate" and "delete" as two different things.

## UWB (the last stretch)
Starts automatically inside about 40 m of GPS distance when both phones have the app open and a trace is live. No physical tap is needed to start it, because the discovery tokens are exchanged through the server; physical closeness is only needed to *range*. Candidate additions: an explicit "Find precisely" button at close range, and offering it only inside a grant. A phone-to-phone tap is not available to apps (Core NFC cannot do phone to phone; NameDrop is system-only), and an accelerometer "bump" is unreliable.

## Build order (suggested)
1. Server: blocks, one-way grants (one-off and windowed, 24 h hard cap), the single `authorise()` check, the 2-minute location-request limit, the 30-minute notice cap, one consolidated sync endpoint, tests.
2. App: consent screen (disclaimer, second confirmation, slider, device-owner authentication), the traced person's banner and "Who can trace me" row, switching between friends, block, report, emergency control.
3. Plans (StoreKit) and server-side entitlement.
4. Wake-ups and the 30-minute notices (needs push).
5. Account deletion and deactivation.

## Decided 2026-10-17 (later)
- **How far the tracer is** is computed on the tracer's phone and sent with their own location requests (no extra calls). The server converts it to a **band** ("under 200 m", "about 2 km") and stores only the band, never the number, shown to the traced person for at most 10 minutes. A distance is not zero information (repeated distances can narrow down a position), which is why bands, and why the tracer is told at request time.
- Refund wording: "purchases are processed by Apple; refund requests go to Apple". Two different account choices: **Delete everything** and **Deactivate and keep my plan**. The emergency control only opens the dialler.
- **The promise rule:** nothing user-facing may promise what is not delivered; every risk is stated in plain words; every acceptance is an explicit action (nothing pre-ticked); consent is recorded with the wording version.

## Decided 2026-10-17 (final round)
- **Every trace has a timer**, one-off or keep-tracing: the traced person allows from **15 minutes to 24 hours**, never more than was asked. It ends when the allowed time is up **or the tracer's plan ends, whichever is first**, and renewing a plan never revives it.
- **Requests**: a trace request waits **30 minutes**; a **friend request waits 2 hours**. A tracer can have 5 requests waiting and **hold 10 permissions** at once, looking at one at a time.
- **Owner check before allowing**: Face ID or Touch ID, then the phone passcode, then an **app passcode** (six digits) which on a phone with neither needs an **email code** to set up. A persistent, non-blocking banner says the phone has no lock until it has one. See [[owner-authentication]].
- A request to someone who blocked you is **stored as a phantom** and expires like an unanswered one, so nothing reveals a block. Checking a trace never deletes a request, for the same reason.

## Server behaviour as built
`POST /grants/request` (kind + hours), `GET /grants` (one sync for both roles, plus the tracer's own plan), `POST /grants/respond` (needs `confirmed` and a consent version), `/grants/revoke`, `/grants/release`, `PUT /grants/position`, `POST /grants/locate` (once per 2 minutes, stores only a distance band), `/blocks`, `/reports`. One `authorise()` runs on every use: not blocked, mutual friends, a live grant (at most 24 h), the tracer's plan live. Nearby (UWB) tokens are only exchanged inside a live grant. Positions are kept 2 hours at most and dropped when nobody may see them. Tables (on-demand, so a safety action is never throttled): `Grants` (+byTracer), `Positions`, `Blocks` (+byBlocked), `Reports`, `Entitlements`. The old two-way `trace` routes were **removed from the API** (the function and table remain, unused).

## What the app does
- The tracer taps a friend: if already allowed, looks at them; otherwise the request sheet (once or keep, up to 15 min to 24 h, plain list of what they will and won't see). The pill shows **Accepted**, the arrow and distance **with the age of their location**, Point me / Guide me, **Request new location** (counting down 2 minutes), Find precisely (UWB phones), and the tracer's own plan end. Anything going wrong, for any reason, shows only "User cannot be traced, error has occurred".
- The traced person sees a **banner on every tab** (who can trace you / who is asking), a **WHO CAN TRACE YOU** strip on the You tab (until when, last looked and how far, STOP, block/report), the consent screen (wording version-pinned, slider starting short, unticked box, a location-settings check, owner check; the separate "Allow?" pop-up was dropped 2026-10-19 because the owner check already confirms), and "X is still tracing you. Want to stop?" at most every 30 minutes.
- **Sharing only while ThatWay is open** on screen (plus one last upload on leaving). It does **not** keep location running in the background, and the consent says so.
- Block, report and the emergency control (opens the dialler only) are one press-and-hold on a friend, with no limits.

## Finding the friend: how the arrow decides (2026-10-18)
- **Far (GPS):** the arrow shows only when the direction is trustworthy: the uncertainty (atan of both accuracies over the distance) must be under ±30°, and the compass must be reliable. Otherwise "Nearby · 40 m, too close for GPS to tell which way", or a hidden arrow while the compass settles. The subtitle always shows the position's age and ±degrees.
- **Fresh positions:** while a permission is live the traced phone keeps location running in the background (blue indicator; consent 2026-10-18.1), uploads on 25 m moves, every 2 minutes, and within ~10 s of a look. The tracer's look is followed by up to 25 s of follow-up reads (not new requests) to collect that fresh fix.
- **Close (UWB):** starts inside 200 m (was 40). Distance needs no camera; "warmer / colder" from the last seconds of distance. iPhone 14 and later give direction only with camera assistance (ARKit tracks the phone's own movement; the camera never looks for the person): "Show direction" turns it on, with coaching from Nearby Interaction's convergence ("move slowly side to side"). Direction maths covers phone flat and held up, and is unit tested.
- A look from under 200 m pushes the traced person: "X is nearby, looking for you. Open ThatWay so they can find you precisely" (at most every 10 minutes), because UWB needs both apps open.
- Press and hold the pill for a live debug readout of every input (no coordinates).
- iOS's own figure-8 calibration screen is no longer requested.

## Location settings before saying yes (2026-10-19)
- iOS never offers "Always" on the first prompt (only Allow Once / While Using / Don't Allow), and **ThatWay does not need it**: during a grant the phone shares in the background on "While Using" with the blue indicator.
- Before the owner check, `SharingReadiness` (ThatWay/Managers/SharingReadiness.swift) must be `.ready`: While Using or Always, **and Precise Location on**. Otherwise one screen explains what to change with one button (iOS's prompt if never asked or an Allow Once lapsed, else Settings); when it's fixed the flow carries on to the owner check by itself.
- While a grant is live and settings stop sharing, a red banner "Sharing paused: …" with FIX shows on every tab. The tracer keeps seeing the last position with its age.
- "Allow Once" looks like While Using until it lapses; the banner catches the lapse.

## Not built / still open
- **Remote push** is built (2026-10-17): the server sends a request or "still tracing you" through APNs using the team key in Parameter Store (`/thatway/apns/*`), to phones registered with `PUT /devices`. Apple accepted our credentials in the real-AWS test; **delivery to a real phone is not yet seen**. A push says only who is asking. Debug builds use the sandbox server, TestFlight and App Store builds production.
- **Who reads reports** and how fast: reports are stored for a year in the `Reports` table; nobody is told when one arrives. Decide this before launch; the app promises no reply time.
- **Terms and a privacy policy** (App Store requires them for the subscription and for user-to-user content) and a lawyer's review of the consent and deletion wording.
- UWB on real hardware; a two-phone test; the age gate (17+ or similar).
- Claim rows for purchases (`tx:` and `orig:` in `Entitlements`) survive an account deletion on purpose (to stop a refund-and-recreate loop); they hold an opaque id only.

## Open items
- Settled: the maximum is 24 hours for everyone, always, with no trusted-friend exception.
- Wording for deactivate versus delete, reviewed by a lawyer.

## Used by
- (nothing else depends on it)

