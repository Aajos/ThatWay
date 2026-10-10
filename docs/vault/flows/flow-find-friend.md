---
id: flow-find-friend
title: Find a friend nearby
type: flow
features: [auth, friends, nearby-proximity, phone-watch-link]
tags: [flow]
---

# Find a friend nearby

**Trigger:** Two friends are close (a festival, a trailhead, a car park) and one taps the other's picture on the compass screen.

## Steps
1. Both are signed in and accepted friends — [[auth]] [[friends]]
2. One taps the friend's picture: the Find sheet opens, the phone checks it can range (UWB), makes a session and publishes its token — [[nearby-proximity]]
3. The other opens Find on their phone; each polls for the other's token every 2 s — [[nearby-proximity]]
4. Tokens meet; the phones range each other directly; the sheet shows distance, a band and (if supported) an arrow, with a haptic tick per band — [[nearby-proximity]]
5. The phone tells the watch the friend's name, band and metres; the watch shows it and taps the wrist closer — [[phone-watch-link]]
6. Closing the sheet stops the session and deletes both offers — [[nearby-proximity]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Hardware | The phone has no UWB (every iPhone SE, the simulator) | test: NearbyManagerTests::aPhoneWithoutUWBNeverTouchesTheBackend |
| Backend address | Placeholder URL, so nothing connects | test: AuthManagerTests::friendsAndNearbyNeedTheServiceAddress; manual: smoke test |
| Trust | A non-friend gets a token | test: backend/lambda/nearby/test.mjs |
| Timing | One side waits forever because the other never opened Find | manual: two phones |
| Link to the watch | Proximity overwrites the travel mode in the context | test: ProximityTests::watchPayloadRoundTripsAndCanEnd |
| Real radio | Range, interference and suspension behave differently outdoors | manual: needs two UWB phones |

## Features touched
- [[auth]] — Authentication (risk high)
- [[friends]] — Friends (risk low)
- [[nearby-proximity]] — Find a friend nearby (UWB) (risk high)
- [[phone-watch-link]] — iPhone-to-watch link (travel mode) (risk medium)
