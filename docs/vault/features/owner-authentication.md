---
id: owner-authentication
title: Owner check, app passcode and the no-lock reminder
area: accounts-backend
status: spike
risk: high
last_verified: 2026-10-17
introduced: 2026-10-17
build: unreleased
tier: free
value: 5
release: v1.1
cpu: "not measured (idle unless a prompt is on screen)"
memory: "not measured"
battery: "not measured (no background work)"
files:
  - ThatWay/Managers/OwnerAuthentication.swift
  - ThatWay/Managers/AppPasscode.swift
  - ThatWay/Compass/OwnerPromptSheet.swift
  - ThatWay/Compass/StatusBanners.swift
  - ThatWay/Managers/AuthManager.swift
tests:
  - ThatWayTests/OwnerAuthenticationTests.swift
  - ThatWayTests/AuthManagerTests.swift
manual_checks:
  - On a phone with Face ID: allowing a trace shows the Face ID prompt naming who; cancelling allows nothing
  - On a phone with a passcode but no biometrics: the phone passcode is asked
  - On a phone with no lock (the simulator): allowing is blocked, the setup explains the three levels, an email code arrives, a six-digit passcode is set, and allowing then asks for it
  - Five wrong app passcodes lock it for five minutes, then ten
  - The no-lock banner shows on every tab and disappears when a phone passcode is turned on
depends_on: [auth]
tags: [feature, area/accounts-backend, status/spike, risk/high]
---

# Owner check, app passcode and the no-lock reminder

> Before anyone can let a friend see where they are, the app checks it is the phone's owner: **Face ID or Touch ID, then the phone passcode, then an app passcode**. The app passcode exists for the phone that has neither, and needs an email code to set up.

**Area:** [[area-accounts-backend]] · **Status:** spike · **Risk:** high

## How it works
- `OwnerAuthCoordinator` picks the strongest check (`method`), asks the system (LocalAuthentication, policy *deviceOwnerAuthentication*, which already falls back from biometrics to the phone passcode) or shows its own prompt for the app passcode. The caller just awaits a result.
- **App passcode**: six digits, refused if repeated or a straight run; stored only as a salted PBKDF2-HMAC-SHA256 hash (150,000 rounds) in the Keychain, per account; five wrong tries lock it for 5 minutes, doubling each time to an hour; a right answer resets the count.
- **Setting it up** on a phone with no lock needs the account's **email verified with a code** (Cognito `GetUserAttributeVerificationCode` / `VerifyUserAttribute`, which works even though the address is already verified: checked against the real pool on 2026-10-17), so a stranger holding an unlocked, lock-less phone cannot set one. The setup state machine refuses to accept a passcode before the email step. "Forgot your passcode?" runs the same email step again.
- **The reminder**: while the phone itself has no lock, a slim banner on every tab says so; tapping explains the three levels. It never blocks anything and stays until a real lock is on.
- **Never gated**: stopping a trace, blocking, reporting and the emergency control. A safety action must work at once for whoever holds the phone. Deleting or deactivating an account IS gated (the owner must do it).
- Needs `NSFaceIDUsageDescription` (added to Info.plist).

## Limits to say out loud
An app passcode only guards ThatWay, not the phone; someone who knows the account's email password can still reset it. It is a weaker lock than a phone lock and the screens say so.

## Used by
- [[trace-grants]] — Standing trace permissions, passes, blocking

