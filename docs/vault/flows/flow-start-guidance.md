---
id: flow-start-guidance
title: Search, pick, start guidance
type: flow
features: [audio-manager, background-guidance, destination-search, guidance-cards, guidance-mode, location-issues, location-profile, point-mode, route-persistence, route-progress, routing-governor, routing-provider-seam, search-ui, trip-log]
tags: [flow]
---

# Search, pick, start guidance

**Trigger:** The user searches for a place and starts a trip.

## Steps
1. Search results come from MapKit near the traveller — [[destination-search]] [[search-ui]]
2. Picking a place sets the destination and (default) enters Point mode — [[point-mode]]
3. Starting guidance begins the trip log, scheduler and background modes — [[guidance-mode]] [[trip-log]] [[background-guidance]]
4. The route fetch waits for a real fix, then goes through the governor — [[location-issues]] [[routing-governor]] [[routing-provider-seam]]
5. The route lands: persisted, cards built, first instruction shown — [[route-persistence]] [[route-progress]] [[guidance-cards]]
6. Audio and location profile switch to guidance settings — [[audio-manager]] [[location-profile]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Governor vs UI | Long retry shows no card (no feedback) | test: RoutingErrorMappingTests; manual offline |
| Route vs persistence | A saved route from an old app version fails to decode | none |
| Trip log vs lifecycle | Log begins twice or never ends on END | test: TripLogTests (file lifecycle) |

## Features touched
- [[audio-manager]] — Audio manager (tones and voice) (risk high)
- [[background-guidance]] — Background guidance, scene phases, screen awake (risk high)
- [[destination-search]] — Destination search and recents (risk medium)
- [[guidance-cards]] — Guidance cards (risk medium)
- [[guidance-mode]] — Guidance mode lifecycle (risk high)
- [[location-issues]] — Permission, precision and waiting-for-fix handling (risk medium)
- [[location-profile]] — Location accuracy profile (risk medium)
- [[point-mode]] — Point mode (straight-line pointing) (risk medium)
- [[route-persistence]] — Trip persistence and restore (risk medium)
- [[route-progress]] — Route progress tracking (risk high)
- [[routing-governor]] — Routing governor (risk high)
- [[routing-provider-seam]] — Routing provider seam (OSRM + fallback) (risk high)
- [[search-ui]] — Search UI (risk low)
- [[trip-log]] — On-device trip log (risk low)
