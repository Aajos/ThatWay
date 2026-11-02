---
id: p8-gate
title: Before you push or commit
type: process
tags: [process, checklist]
---
# Before you push or commit

The gate. Nothing is committed until section A is green; nothing is pushed until B is green; nothing is uploaded to TestFlight until D is green; nothing is submitted until E is green. Each box has the command or the place to look. If a box does not apply, write *n/a and why* in the commit message rather than skipping it silently.

Commit only when you decide to: committing is deliberate, not automatic.

## A. Every commit (about 10 minutes)

### A1. The change is what you meant
- [ ] `git status` and `git diff --stat`: every changed file is one you meant to change. Files you are keeping out of the repo stay untracked (for example scratch images and the planning HTML).
- [ ] You can state the change in one sentence. If it needs "and", it may be two commits.
- [ ] No leftover temporary code: preview launch flags, forced states, debug prints, `TODO remove`. Search: `git diff | grep -nE "^\+.*(TODO|FIXME|tw-preview|XXX)"`.

### A2. Tests pass (all of them, on fresh builds)
```bash
cd ThatWayCore && swift test && cd ..                                  # shared package, on the Mac
xcodebuild test -project ThatWay.xcodeproj -scheme ThatWay \
  -destination 'id=<simulator id>' -derivedDataPath /tmp/tw_dd_test \
  -only-testing:ThatWayTests                                           # iOS unit tests
/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m backend/lambda/nearby/test.mjs   # backend logic (if touched)
```
- [ ] 0 failures. A flaky test is a bug: fix the wait, do not re-run until green.
- [ ] You wrote or updated a test for the behaviour you changed. A bug fix without a test that fails first is a guess.
- [ ] Use a fresh `-derivedDataPath`; the default goes stale after package changes ("cannot find type" for symbols that moved).

### A3. Everything builds
- [ ] iOS: built by the test run above.
- [ ] Watch: `xcodebuild -project ThatWay.xcodeproj -scheme ThatWayWatch -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/tw_dd_watch build`
- [ ] After changing `ThatWayCore/Package.swift` or public API: build **all** schemes (ThatWay, ThatWayWatch, ThatWayCore, ThatWayUI). New shared types need `public` and an initialiser ([[core-package]]).
- [ ] Device builds need the Xcode account signed in (the watch is embedded): see [[phone-watch-link]].

### A4. The map still matches the code
```bash
python3 scripts/vault/check_vault.py --fix --write
```
- [ ] 0 errors and 0 warnings (an unmapped new source file is a warning: claim it in a feature note).
- [ ] A new feature has a note with `files`, `tests`, `manual_checks`, `depends_on`, **`introduced`, `build`, `release`, `tier`, `value`** and honest `status` and `risk`.
- [ ] A changed feature: its **Failure points** are still true; **Used by** was regenerated (`--fix`); `last_verified` updated.
- [ ] A bug you found that was not on the map is now a failure point with "what would have caught it".
- [ ] New or changed performance cost: the `cpu`, `memory`, `battery` fields say `predicted` or `measured` (never blank-as-implied-zero) ([[P7 Optimisation checks]]).
- [ ] The **blast radius** ([[Blast radius]]) of what you changed: you ran the listed tests and manual checks for everything downstream.

### A5. Privacy and safety (these are rules, not preferences)
- [ ] **No location data is logged, stored in a file, or put in a commit:** no coordinates, routes, place names or tokens in logs, perf output, test fixtures or the vault. Quick scan:
  ```bash
  grep -rnE "(print|NSLog|os_log|Logger|debugPrint)\(.*(latitude|longitude|coordinate|placeName|token|password)" ThatWay ThatWayWatch ThatWayCore/Sources --include='*.swift'   # must print nothing
  ```
- [ ] No secrets: AWS keys, passwords, tokens, signing certificates. `git diff --cached | grep -niE "secret|password|AKIA|BEGIN .*PRIVATE"` prints nothing worth worrying about. (Cognito pool and client ids and the API URL are not secrets.)
- [ ] No new third-party packages in the app.
- [ ] The backend is changed only on purpose; a Lambda change updates its test.
- [ ] No dark glows added; animations are not permanently removed to save CPU.

### A6. Config in the repo is the shipping config
- [ ] `grep -n "backendEnabled" ThatWay/Config.swift` says **true**. Test builds flip it with `sed` and restore it; confirm.
- [ ] `grep -n apiBaseURL ThatWay/Config.swift`: the real address once it exists, never an old one. While it is still `REPLACE_WITH_API_ID`, friends say so plainly (a test covers it) and the checklist for [[P10 Backend and proximity runbook]] is open.
- [ ] `appleSignInEnabled` stays false until the paid team and capability exist.

### A7. If it touched UI (5 minutes, see [[P5 Accessibility testing]])
- [ ] Looked at it at the default text size **and** at `accessibility-extra-extra-extra-large`; nothing clipped, **END** reachable.
- [ ] iPhone SE size: no overlap.
- [ ] All four themes if it uses colour (Paper especially).
- [ ] Every new control has an accessibility label.

### A8. If it touched guidance, location or routing
- [ ] The matching flow in `flows/` still reads true; run its manual check.
- [ ] A simulated or real walk: start, a turn, off-route, arrive. END returns smoothly; clearing the destination returns to idle.
- [ ] Performance: redraw counts a second did not rise ([[redraw-model]]).

### A9. The message
- [ ] A short subject in the imperative ("Add resend-code flow to sign-up"), a body that says *why*, and the numbers if you measured something.
- [ ] The attribution trailer the project uses is on the end.

## B. Before you push
- [ ] Your branch is rebased or merged with `main` and the tests pass **after** that (a merge can break a green branch).
- [ ] If `backend/lambda/**` changed and the branch will reach `main`: the **deploy workflow** deploys every Lambda in its `FUNCTIONS` list on push, and `update-function-code` **fails if a function does not exist yet**. Create a new Lambda in the console first ([[P10 Backend and proximity runbook]]).
- [ ] You are not about to push a build that only works with a flag you flipped locally.
- [ ] The PR (if you use one) says what to look at and what you did *not* test.

## C. Backend changes
- [ ] Logic changed ⇒ its test changed (`backend/lambda/*/test.mjs`, run with `jsc -m` or `node`).
- [ ] No token, request body or user id is logged (log the error *name*).
- [ ] IAM: the role has exactly the actions the code uses, on exactly the tables it uses (`SETUP.md` section 3).
- [ ] After deploy: `CLIENT_ID=... API=... backend/scripts/smoke.sh <confirmed username>` exits 0.
- [ ] A new route has the JWT authorizer attached (unless it is deliberately public, and then it is rate-limited and validated).

## D. Before a TestFlight build
- [ ] All of A and B.
- [ ] **Version and build number** raised (Xcode, target, General). Internal dev builds are tracked in `scripts/vault/versions.json`: add a row for this one.
- [ ] Release configuration builds (`-configuration Release`); no `PERF` flag; the harness is not compiled in.
- [ ] Gate on, real API address, a **real sign-up email arrives** and confirms on a clean install.
- [ ] Full accessibility smoke ([[P5 Accessibility testing]]) and one 30-minute device trip with logs ([[P6 Live testing]]).
- [ ] Release notes say what to test and what to ignore.

## E. Before App Store submission (milestone m04, 15 Jan 2027)
- [ ] The stage gates S1 to S4 in [[P1 Stages and the MVP line]] are all ticked with evidence.
- [ ] Privacy labels match reality (location while using, account identifiers, no tracking); the privacy-policy URL is live (c02).
- [ ] The location purpose strings explain *why* and match the behaviour (background location only while guiding).
- [ ] Review notes: how to sign in (a demo account), how to see guidance without walking (explain the simulated route), that the sign-in is required for friends only if that is true.
- [ ] No mention of the website in the app (the plan's dry-run rule); the in-app unlock exists.
- [ ] Screenshots from the current build, in the themes you want shown; the watch app is either complete or not embedded.
- [ ] Open the app on a **clean install**, with no account, no permissions, no network, and walk the first-launch flow ([[flow-first-launch]]).
- [ ] Crash-free sessions in TestFlight above 99.5 %; no open P1 failure point in the [[Failure catalogue]].

## F. What a good commit leaves behind
A reader a year from now can answer: what changed, why, how it was verified, what it could break (the blast radius), and what was deliberately left. If the commit message plus the vault diff cannot answer those, the commit is not finished.

## G. Never in the repo
Real coordinates or routes; account credentials; AWS keys; signing certificates; logs from a phone; screenshots with a visible location or friend names you did not get permission for.

Related: [[04 Changing the app]], [[02 How this vault works]], [[P7 Optimisation checks]].
