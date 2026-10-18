---
id: flow-mode-change
title: Switching travel mode mid-route
type: flow
features: [arrival, audio-cue-plan, location-profile, mode-change-reroute, persistence-defaults, route-failure, route-line, routing-governor, travel-mode-carousel, travel-modes]
tags: [flow]
---

# Switching travel mode mid-route

**Trigger:** The user changes Walk/Run/Cycle/Drive while guiding.

## Steps
1. The carousel commits and persists the mode — [[travel-mode-carousel]] [[travel-modes]] [[persistence-defaults]]
2. After 600 ms one initial-request fetch for the new profile — [[mode-change-reroute]] [[routing-governor]]
3. Tunings (corridor, filters, reveal, arrival, cue points) switch immediately — [[location-profile]] [[audio-cue-plan]] [[arrival]] [[route-line]]
4. A 'Switching to ...' card shows until the route lands — [[route-failure]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Tuning change vs old route | Thresholds for the new mode apply to a route fetched for the old one for up to a few seconds | manual |
| Rapid changes | Several fetches queue | test: debounce in TravelModeTests |

## Features touched
- [[arrival]] — Arrival detection and completion (risk medium)
- [[audio-cue-plan]] — Audio cue plan, panning, voice script (risk medium)
- [[location-profile]] — Location accuracy profile (risk medium)
- [[mode-change-reroute]] — Mid-route mode change (risk medium)
- [[persistence-defaults]] — Persisted preferences (risk low)
- [[route-failure]] — Failure diagnosis and connectivity (risk medium)
- [[route-line]] — Route line (last stretch) (risk medium)
- [[routing-governor]] — Routing governor (risk high)
- [[travel-mode-carousel]] — Travel-mode carousel (risk low)
- [[travel-modes]] — Travel modes and tuning (risk medium)
