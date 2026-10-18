---
id: flow-arrival
title: Arriving
type: flow
features: [arrival, audio-manager, background-guidance, compass-screen-layout, guidance-mode, route-persistence, trip-log]
tags: [flow]
---

# Arriving

**Trigger:** The traveller reaches the destination.

## Steps
1. Arrival is detected on the real path within the mode's radius — [[arrival]]
2. Audio session is released, scheduler stopped, persisted trip cleared — [[audio-manager]] [[route-persistence]] [[guidance-mode]]
3. The trip log writes its summary — [[trip-log]]
4. The arrived layout shows until DONE; screen may lock again — [[compass-screen-layout]] [[background-guidance]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Radius vs GPS error | Never fires if the radius is below GPS accuracy | manual: real arrival |
| Late fetch | A fetch finishing after arrival restarts the scheduler | guarded by `!arrived` |

## Features touched
- [[arrival]] — Arrival detection and completion (risk medium)
- [[audio-manager]] — Audio manager (tones and voice) (risk high)
- [[background-guidance]] — Background guidance, scene phases, screen awake (risk high)
- [[compass-screen-layout]] — Compass screen layout and small screens (risk medium)
- [[guidance-mode]] — Guidance mode lifecycle (risk high)
- [[route-persistence]] — Trip persistence and restore (risk medium)
- [[trip-log]] — On-device trip log (risk low)
