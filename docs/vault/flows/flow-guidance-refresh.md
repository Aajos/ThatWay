---
id: flow-guidance-refresh
title: One second of guidance (the refresh chain)
type: flow
features: [arrival, audio-cue-plan, audio-manager, compass-health, compass-tilt, dead-reckoning, dial-view, eta, guidance-cards, location-manager, location-profile, redraw-model, route-data-generator, route-line, route-progress]
tags: [flow]
---

# One second of guidance (the refresh chain)

**Trigger:** The 1 s tick while guiding (or a location update while the screen is off).

## Steps
1. Dead-reckoned extra metres are computed from the last fix — [[dead-reckoning]] [[location-manager]]
2. Compass health compares compass and GPS direction (guiding only) — [[compass-health]]
3. Progress advances; current card and distance update — [[route-progress]]
4. Arrival is checked on the real position — [[arrival]]
5. The route line is baked if it is due — [[route-line]] [[route-data-generator]]
6. ETA recalculates — [[eta]]
7. An audio cue fires if a cue point was crossed — [[audio-cue-plan]] [[audio-manager]]
8. Tilt stages update (held within the leg) — [[compass-tilt]]
9. Published state changes reach the dial and cards only if what they show changed — [[redraw-model]] [[dial-view]] [[guidance-cards]]
10. Location accuracy profile re-evaluated — [[location-profile]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Dead reckoning vs arrival/off-route | An estimate triggers arrival or hides a real deviation | test: estimateNeverReachesArrival; by design real fix only |
| Progress vs publish | Quantised publishing leaves the readout stale by up to the quantum | manual: text lags at most 4 m |
| Publish vs equatable views | A shown value missing from a state struct freezes part of the UI | manual |
| Refresh vs background | The tick is paused when the scene is inactive; only location updates drive it | manual: locked-phone walk |

## Features touched
- [[arrival]] — Arrival detection and completion (risk medium)
- [[audio-cue-plan]] — Audio cue plan, panning, voice script (risk medium)
- [[audio-manager]] — Audio manager (tones and voice) (risk high)
- [[compass-health]] — Compass health, ghost overlay, GPS direction (risk medium)
- [[compass-tilt]] — Compass tilt algorithm (risk low)
- [[dead-reckoning]] — Dead reckoning (risk medium)
- [[dial-view]] — Compass dial and needle (risk medium)
- [[eta]] — ETA (risk low)
- [[guidance-cards]] — Guidance cards (risk medium)
- [[location-manager]] — LocationManager (fixes and permission) (risk high)
- [[location-profile]] — Location accuracy profile (risk medium)
- [[redraw-model]] — Redraw and publish model (risk high)
- [[route-data-generator]] — Guidance line data (bake) (risk medium)
- [[route-line]] — Route line (last stretch) (risk medium)
- [[route-progress]] — Route progress tracking (risk high)
