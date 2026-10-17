---
id: flow-phone-locked
title: Phone locked mid-trip
type: flow
features: [audio-manager, background-guidance, compass-health, heading, location-manager, location-profile, redraw-model, route-progress, trip-log]
tags: [flow]
---

# Phone locked mid-trip

**Trigger:** The screen turns off while guidance is running.

## Steps
1. The scene goes inactive: tick and heading pause, compass-health state resets — [[background-guidance]] [[compass-health]]
2. Background location keeps delivering fixes — [[location-manager]] [[location-profile]]
3. Each fix refreshes progress; cues still play through the trip-long audio session — [[route-progress]] [[audio-manager]]
4. The trip log keeps sampling — [[trip-log]]
5. On unlock the tick and heading restart and the screen is current — [[redraw-model]] [[heading]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Suspension | iOS suspends the app and cues stop | manual: 10-minute locked walk; trip-log samples show gaps |
| Audio session | A call or headphone unplug ends cues | manual; observers in AudioManager |
| Battery | Background GPS at high accuracy drains faster than expected | manual: weekly battery test |

## Features touched
- [[audio-manager]] — Audio manager (tones and voice) (risk high)
- [[background-guidance]] — Background guidance, scene phases, screen awake (risk high)
- [[compass-health]] — Compass health, ghost overlay, GPS direction (risk medium)
- [[heading]] — Heading pipeline (risk medium)
- [[location-manager]] — LocationManager (fixes and permission) (risk high)
- [[location-profile]] — Location accuracy profile (risk medium)
- [[redraw-model]] — Redraw and publish model (risk high)
- [[route-progress]] — Route progress tracking (risk high)
- [[trip-log]] — On-device trip log (risk low)
