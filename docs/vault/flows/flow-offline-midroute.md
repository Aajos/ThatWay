---
id: flow-offline-midroute
title: Losing the connection mid-trip
type: flow
features: [guidance-cards, off-route-reroute, route-failure, route-progress, routing-governor, trip-log]
tags: [flow]
---

# Losing the connection mid-trip

**Trigger:** Airplane Mode or no signal while guiding.

## Steps
1. Existing route and cards keep working (no network needed to progress) — [[route-progress]] [[guidance-cards]]
2. A reroute or mode change fails: governor retries with backoff — [[routing-governor]] [[off-route-reroute]]
3. A card names the cause and counts down to the retry — [[route-failure]]
4. Connectivity returns: Retry now or automatic recovery — [[routing-governor]]
5. The failure is counted in the trip log — [[trip-log]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Offline vs server trouble | Both look like a network error without the connectivity monitor | test: RoutingErrorMappingTests |
| Travelling off route while offline | No new route is possible; the user relies on the compass and old cards | manual: Airplane Mode test still to do |

## Features touched
- [[guidance-cards]] — Guidance cards (risk medium)
- [[off-route-reroute]] — Off-route detection and reroute (risk high)
- [[route-failure]] — Failure diagnosis and connectivity (risk medium)
- [[route-progress]] — Route progress tracking (risk high)
- [[routing-governor]] — Routing governor (risk high)
- [[trip-log]] — On-device trip log (risk low)
