---
id: flow-off-route
title: Wrong turn and reroute
type: flow
features: [off-route-reroute, route-data-generator, route-failure, route-persistence, route-progress, routing-governor, travel-modes]
tags: [flow]
---

# Wrong turn and reroute

**Trigger:** The traveller leaves the corridor.

## Steps
1. The corridor poll flags off-route from the real fix — [[off-route-reroute]] [[travel-modes]]
2. A reroute is requested through the cooldown and cap — [[routing-governor]]
3. On success the new route replaces the old atomically; the line is re-baked — [[route-progress]] [[route-data-generator]] [[route-persistence]]
4. On failure the old route stays and a diagnosis card shows — [[route-failure]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Poll cadence vs speed | At driving speed a slow poll reroutes late | manual: drive |
| Cooldown vs a persistent deviation | No reroute for 15 s: the user is lost with stale cards | test: RoutingGovernorPolicyTests (policy only) |
| Replace vs audio | Cue state reset per card id repeats a cue after reroute | test: crossedPoint fired set |

## Features touched
- [[off-route-reroute]] — Off-route detection and reroute (risk high)
- [[route-data-generator]] — Guidance line data (bake) (risk medium)
- [[route-failure]] — Failure diagnosis and connectivity (risk medium)
- [[route-persistence]] — Trip persistence and restore (risk medium)
- [[route-progress]] — Route progress tracking (risk high)
- [[routing-governor]] — Routing governor (risk high)
- [[travel-modes]] — Travel modes and tuning (risk medium)
