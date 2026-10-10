---
id: p6-live-testing
title: Live testing
type: process
tags: [process, testing]
---
# Live testing

The simulator cannot tell you whether the compass lies, whether the phone survives a locked 30-minute walk, how much battery a trip costs, or whether UWB works. Only the phone, outdoors, can. This note is the protocol, so every outing produces comparable evidence instead of anecdotes.

**Test devices:** iPhone SE 2nd generation (battery health 73 %, so battery figures are *pessimistic*: say so in every result) and, for the watch, the paired Apple Watch. UWB needs two U1/U2 phones; the SE has none ([[nearby-proximity]]).

## 0. Preparation (5 minutes, every outing)
- [ ] Build the **installed** version you mean to test; write down the git commit and build number in the result.
- [ ] `Config.backendEnabled` is `true` and `apiBaseURL` is the real address, **or** you deliberately use a gate-off test build (then say so). Never test a build you cannot name.
- [ ] Phone: charge to 100 % (or note the start %), brightness **auto**, Low Power Mode off unless it is the thing being tested, Wi-Fi and cellular on, Location *While Using* **and** Precise on, Bluetooth on (headphones are part of real use).
- [ ] Profile, Test logs, **Record test logs** is on. Clear old logs first so the folder holds only this outing.
- [ ] Note the weather and where the phone rides (hand, pocket, car mount, bike mount): the compass behaves differently in each.
- [ ] Do **not** write down places or routes in the vault. Describe the *kind* of route ("urban walk, 3 km, 6 turns, one roundabout").

## 1. The test routes (plan milestone t01)
Three routes cover most of what breaks. Keep them the same so results compare.
| Route | Mode | What it exercises | Pass criteria |
|---|---|---|---|
| Drive, mixed urban and arterial, about 10 km | Drive | Rerouting, speed-based look-ahead, audio cues, arrival, a mid-route wrong turn | Every instruction arrives before the turn; no phantom turns; ETA within 10 %; arrival fires within 5 m |
| Walk, footpaths and a park, about 3 km | Walk | Heading accuracy at low speed, compass health, dead reckoning | The needle points the way you walk within about 20 degrees; no 180-degree flips |
| **Roundabout**, any approach | Walk or drive | Exit count and exit bearing | The card says the right exit; no double advance ([[route-progress]]) |
After each, ask the polyline question: **does the drawn line sit on the actual road?** (milestone m01/t01, due 14 Oct 2026).

## 2. The situations to deliberately cause
Each maps to a flow in the vault; a failure is a new failure point. Do these on at least one outing each.
| Situation | How | What should happen | Flow |
|---|---|---|---|
| Phone locked | Start guidance, lock the screen, walk 10 minutes | Audio keeps guiding; the lock-screen icon shows location in use; the trip is intact on unlock | [[flow-phone-locked]] |
| Airplane Mode mid-route | Toggle it on at the half-way point, wait a minute, toggle off | A diagnosis card; the old route stays; it recovers by itself | [[flow-offline-midroute]] |
| Off route | Take a wrong turn on purpose | Reroute within a few seconds; one clear message | [[flow-off-route]] |
| Compass wrong | Stand near a car or a steel structure, then walk | The compass-health card appears; "Use GPS direction" works | [[flow-compass-wrong]] |
| Relaunch | Force-quit mid-route, reopen | The trip is restored | [[flow-relaunch-restore]] |
| Mode change | Walk to Drive or Cycle mid-route | "Switching to ... route" then a new route; no loss of the old one on failure | [[flow-mode-change]] |
| Low Power Mode | Switch it on mid-trip | Guidance continues, update rate adapts | [[background-guidance]] |
| Weak GPS | Walk a street between tall buildings, then through a tunnel | The location card explains; no routing from a wrong position | [[location-issues]] |
| Phone call or notification | Receive one | Audio ducks and resumes | [[audio-manager]] |
| Headphones | Wired or Bluetooth | Cues route to them; the stereo panning cue makes sense | [[audio-cue-plan]] |
| Finish | Arrive | One arrival card; DONE returns to idle (not to the last destination) | [[flow-arrival]] |
| Watch | Drive mode on the phone | The watch refuses and closes | [[flow-watch-drive-guard]] |

## 3. Collecting the evidence
The app writes numbers only (never coordinates, place names or routes; this is enforced by a test).
1. **Cable:** plug in and run
   ```bash
   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
     --domain-identifier com.aadittesting.ThatWay.ThatWay --source Documents/TripLogs --destination ./triplogs
   ```
   (`xcrun devicectl list devices` shows the id.)
2. **Share button:** Profile, Test logs, **Share logs**, AirDrop to the Mac.
3. **Files app:** On My iPhone, ThatWay, TripLogs.
The format is in `docs/test-logs.md` (JSON lines: `session`, `route`, `sample` every 10 s, `event`, `summary`). The summary gives CPU mean, p95 and max, memory start, peak and end, battery drop per hour, thermal state, screen-on fraction, GPS fixes and event counts.

For the watch use `scripts/watch/analyze_spike_log.py` and fill in the table in `docs/watch-spike.md`.

## 4. Write the result down (template)
Add it to the **Manual checks** of the feature(s) tested. If you want a longer record, create `docs/field-tests/` (it does not exist yet). No locations.
```
Date: 2026-MM-DD    Build: <commit hash>, installed via <Xcode | TestFlight>
Device: iPhone SE 2nd gen, iOS <x>, battery health 73 %, started at <n> %
Mode: <walk|run|cycle|drive>    Phone carried: <hand|pocket|mount>    Weather: <...>
Route kind: <urban walk, 3 km, 6 turns>    Duration: <min>    Screen: <on|locked>
Result: <pass | fail>    Battery used: <n> %    CPU mean/p95: <a>/<b> %    Memory peak: <m> MB
Situations covered: <list>
What felt wrong: <one line each>    Log file(s): <names only>
Follow-up: <new failure point id | test to write | none>
```

## 5. After the outing
- [ ] Every "felt wrong" becomes a failure point in the relevant feature note, with what would have caught it. A bug that was not on the map is a gap in the map ([[04 Changing the app]]).
- [ ] Update the battery and CPU fields in the feature notes from *predicted* to *measured (device)*; rerun the checker; [[Performance evidence]] shows the progress.
- [ ] Tick the stage gate it satisfies ([[P1 Stages and the MVP line]]).

## 6. TestFlight stages (S3 and S4 in the plan)
| Stage | When | Who | Entry | Exit |
|---|---|---|---|---|
| Internal | 1 Dec 2026 | You and 2 friends | Apple Developer enrolled (15 Nov); a build uploaded from Xcode (Product, Archive, Distribute, App Store Connect); [[P8 Before you push or commit]] release gate green | A full drive and a full walk with no crash; logs from every tester |
| External beta | Recruit by 20 Dec, finish by 10 Jan 2027 | 20 to 50 people (hiking, camping and festival groups) | Beta App Review passed; feedback form ready (add a battery question) | Crash-free sessions above 99.5 %; no open "wrong direction" report; App Review dry run done |
What to ask testers: where did it lie to you; did the battery worry you; did the email arrive and how long did it take; was anything hard to read outdoors. Offer them the sharing instructions above so they can send logs.

## 7. Things that look like bugs but are not
- Distances jump a metre or two between fixes: dead reckoning estimates between GPS fixes ([[dead-reckoning]]).
- The simulator shows no heading: heading is device-only.
- Network bytes in the trip log are device-wide, not the app's.
- A 30-minute trip moves battery by only a few percent: judge across several trips, not one.

Related: [[P5 Accessibility testing]], [[P7 Optimisation checks]], [[trip-log]], `docs/test-logs.md`.
