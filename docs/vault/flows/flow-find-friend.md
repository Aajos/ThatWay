---
id: flow-find-friend
title: Trace a friend
type: flow
features: [auth, friends, trace-friends, nearby-proximity, location-manager, heading]
tags: [flow]
---

# Trace a friend

**Trigger:** One person taps a friend on the compass screen and asks to trace them.

## Steps
1. Both are signed in and accepted friends — [[auth]] [[friends]]
2. The asker taps the friend and confirms "Ask Sam to share their direction?"; a pill shows *you, request pending, them* — [[trace-friends]]
3. The other person's app shows *them, Accept or Decline, you* (and, if the app is not in front, a local notification) — [[trace-friends]]
4. They accept: both phones start sharing a position with each other, and keep doing so in the background for the whole trip; each pill shows *you, arrow and distance, them* — [[trace-friends]] [[location-manager]] [[heading]]
5. Far apart, the arrow and distance come from GPS (any range); inside about 40 m the phones try Ultra Wideband and the readout becomes precise — [[nearby-proximity]]
6. Either person can aim the compass at the other (Point me) or get turn-by-turn to their live position (Guide me); the destination moves with them — [[trace-friends]]
7. Either side taps the cross, or 30 minutes pass, or they stop being friends: sharing stops and the other side is told — [[trace-friends]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Consent | A position is relayed before acceptance | test: backend/lambda/trace/test.mjs; TraceManagerTests::nothingIsSharedUntilTheyAccept |
| Visibility | A stranger or a stale position reaches the screen | test: backend/lambda/trace/test.mjs |
| Heading | The arrow points the wrong way when the compass lies | manual: [[flow-compass-wrong]]; the arrow is dimmed when the heading is unreliable |
| Notification | A request is missed because the app is suspended | manual: known gap until push (Apple Developer Program) |
| Hardware | The phone has no UWB (iPhone SE, simulator) | test: TraceManagerTests::aPhoneWithoutUWBStaysOnGpsAtAnyDistance |
| Radio | UWB behaves differently outdoors | manual: needs two UWB phones |

## Features touched
- [[auth]] — Authentication (risk high)
- [[friends]] — Friends (risk low)
- [[trace-friends]] — Trace a friend (consent, any range) (risk high)
- [[nearby-proximity]] — Ultra Wideband last stretch (nearby) (risk high)
- [[location-manager]] — LocationManager (fixes and permission) (risk high)
- [[heading]] — Heading pipeline (risk medium)
