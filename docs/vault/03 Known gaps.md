---
id: known-gaps
title: Known gaps
tags: [index]
---
# Known gaps

Hand-kept list of things that are known to be missing, unwired or unproven. The checker adds computed gaps (features with no tests, `none` failure points, unmapped files) in `_generated/Gaps`.

> Launch blockers and decisions are collected in `docs/launch-readiness-report.md` (2026-11-02). This note is the long-running list.

## Unwired or dead (the app promises, the code does not deliver)
- Fixed 2026-11-02: "Voice of directions", "Haptics on turns" and "Share destination" were stored and read by nothing, so they were removed from Settings until the feature exists. See [[settings-profile]], [[haptics-ios]].
- Visibility, close-by radius, achievements, avatar photo options: decorative. See [[avatars-social-decor]].
- Friends and tracing: server verified against the real tables and AWS (`grants_integration.sh`); friends, requests, consent, push and background sharing have run between real phones, but **UWB and the camera-assisted arrow have never run on real radios**. See [[friends]], [[trace-grants]], [[nearby-proximity]].

## Not persisted
- Fixed 2026-11-02: theme, skin, tilt and units are remembered ([[persistence-defaults]]). Still reset: default mode, visibility.

## Unproven (needs a real device or real walks)
- Heading on a real phone/watch, background running over a long locked walk, battery over 30+ minutes, Airplane Mode mid-route: see [[background-guidance]], [[flow-phone-locked]], [[flow-offline-midroute]].
- Watch wrist-down sessions, heading blender error, haptic discrimination: see [[watch-session]], [[heading-blender]], [[watch-haptics]].
- Walk/run/cycle tuning values are first guesses: see [[travel-modes]].
- Compass-health tolerance and cadence: see [[compass-health]].

## Watch (new)
- Drive guard needs the paired phone: an unpaired watch is not blocked, and a cold launch learns about Drive about 3 s late. See [[watch-drive-guard]], [[phone-watch-link]].
- The guard closes the app with `exit(0)` (watchOS has no quit): fine for the spike, risky for App Review.
- Embedding the watch app means every iPhone device build needs a signed watch profile: Xcode must have the account signed in. See [[phone-watch-link]].
- Voice search needs one tap after the swipe (watchOS cannot start dictation by itself). See [[watch-voice-search]].

## Structural
- `AppModel` (about 1,100 lines) owns the whole lifecycle: see [[guidance-mode]].
- Two copies of the progress maths: [[route-progress]], [[route-tracker]].
- Persisted trips have no schema version: [[route-models]], [[route-persistence]].
- No UI or snapshot tests: [[compass-screen-layout]], [[guidance-cards]].
- Demo OSRM hosts: [[routing-provider-seam]].
- Sign-up and password emails go through Cognito's default sender (capped at 50 a day, often lands in spam) and SES is still in sandbox, so a launch with real users will lose sign-up codes. Needs SES production access and a verified sender (needs a domain): [[auth]], [[backend-config]], [[P10 Backend and proximity runbook]]. The app recovers meanwhile: resend code, unconfirmed sign-in goes back to the code step.
- The API is on the `Dev` stage and the app points at it; there is no separate production stage.
- No production routing host: the public OSRM demo servers are used (non-commercial, no uptime promise): [[routing-provider-seam]].

## Tracing friends
- Remote push is built and verified (APNs key in Parameter Store): the server pushes requests, "still tracing you" and "nearby". Delivery has been seen on a real phone; iOS notification settings still decide whether a banner stays on the lock screen. See [[trace-grants]].
- Battery cost of sharing in the background (uploads on 25 m of movement, every 2 minutes, and when looked at) is not measured.
- The watch does not show friends (deliberate for now).
- No walkie talkie yet; the design and the safety questions are in [[walkie-talkie]].
- Background sharing lasts only while iOS keeps the app alive (a force-quit app stops sharing, which is the safe failure, and the consent says so).
- Reports reach the owner by email (2026-11-02, topic `thatway-alerts`; the address must confirm the subscription) and are read and acted on with `backend/scripts/reports.sh`. Nobody else can review them yet.

## Proximity
- UWB needs two UWB phones; the iPhone SE (the test phone) and the simulator cannot range. Logic and backend are tested; the radio is not. See [[nearby-proximity]].
- There is no Bluetooth fallback, so the plan's "Bluetooth on the SE 2nd gen" is not met: the SE gets the GPS arrow and distance only.

## Accessibility (new, measured 2026-10-09)
- Text on the accent colour fails contrast on Paper (2.6:1), Ember (3.1:1) and Arcade (3.5:1); VoiceOver cannot read the dial or cards; Reduce Motion is honoured only by the carousel. See [[P5 Accessibility testing]].
