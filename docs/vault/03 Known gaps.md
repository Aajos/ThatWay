---
id: known-gaps
title: Known gaps
tags: [index]
---
# Known gaps

Hand-kept list of things that are known to be missing, unwired or unproven. The checker adds computed gaps (features with no tests, `none` failure points, unmapped files) in `_generated/Gaps`.

## Unwired or dead (the app promises, the code does not deliver)
- "Voice of directions", "Haptics on turns", "Share destination" settings: stored, read by nothing. See [[settings-profile]], [[haptics-ios]].
- Visibility, close-by radius, achievements, avatar photo options: decorative. See [[avatars-social-decor]].
- Friends and the API: dormant behind a placeholder URL (the app now says so plainly). See [[friends]], [[backend-config]], [[P10 Backend and proximity runbook]].

## Not persisted
- iPhone theme, skin, tilt, units, default mode, visibility reset on every launch. See [[persistence-defaults]].

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
- Sign-up confirmation email not arriving (AWS side, unresolved); the app now recovers: resend code, unconfirmed sign-in goes back to the code step. Test builds run with the gate off: [[auth]], [[backend-config]], [[P10 Backend and proximity runbook]].

## Proximity (new)
- UWB needs two UWB phones; the iPhone SE (the test phone) and the simulator cannot range. Logic and backend are tested; the radio is not. See [[nearby-proximity]].
- The `nearby` Lambda, table and routes are written but not created in AWS. See [[P10 Backend and proximity runbook]].
- No Bluetooth fallback and no push yet.

## Accessibility (new, measured 2026-10-09)
- Text on the accent colour fails contrast on Paper (2.6:1), Ember (3.1:1) and Arcade (3.5:1); VoiceOver cannot read the dial or cards; Reduce Motion is honoured only by the carousel. See [[P5 Accessibility testing]].
