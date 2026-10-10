---
id: flow-watch-guidance
title: Guidance on the watch
type: flow
features: [heading-blender, route-tracker, routing-provider-seam, theme-system, watch-app, watch-gestures, watch-haptics, watch-session, watch-spike-log, watch-travel-modes, watch-voice-search]
tags: [flow]
---

# Guidance on the watch

**Trigger:** Open the watch app, pick a destination by voice and walk, run or cycle with the wrist down.

## Steps
1. Swipe right, tap the mic button and say where to; MapKit finds it near the wearer — [[watch-gestures]] [[watch-voice-search]]
2. A tap sets the destination; the shared OSRM provider fetches a route for the current mode (Point mode if it fails) — [[routing-provider-seam]] [[watch-travel-modes]]
3. Swipe up or down to switch walk / run / cycle; cycling refetches the route — [[watch-travel-modes]] [[watch-gestures]]
4. The session keeps the app alive (A location or B workout) — [[watch-session]]
5. Fixes and compass readings arrive; the blender picks GPS course or the magnetometer — [[heading-blender]] [[watch-app]]
6. The tracker computes the next real turn, distance and off-route — [[route-tracker]]
7. The needle and readouts update in the shared look; swipe left changes theme — [[watch-app]] [[theme-system]]
8. Haptics announce turns, arrival and off-route — [[watch-haptics]]
9. The spike log records numbers only — [[watch-spike-log]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Dictation vs gestures | Dictation can only be started by a tap, so voice search is swipe + tap, not swipe alone | by design (watchOS) |
| Search vs route | A found place with no route leaves the wearer in Point mode with a message | manual: offline and no-road cases |
| Mode change vs route | A cycling refetch fails and the walking route stays on screen | manual |
| Wrist-down suspension | No updates arrive while the wrist is down | manual: Test 1 |
| Blender thresholds | The 0.8-1.5 m/s band flaps or lags | manual: Test 2; unit tests cover flapping |
| Haptic patterns | Left and right indistinguishable while moving | manual: Test 3 |

## Features touched
- [[heading-blender]]
- [[route-tracker]]
- [[routing-provider-seam]]
- [[theme-system]]
- [[watch-app]]
- [[watch-gestures]]
- [[watch-haptics]]
- [[watch-session]]
- [[watch-spike-log]]
- [[watch-travel-modes]]
- [[watch-voice-search]]
