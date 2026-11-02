---
id: flow-relaunch-restore
title: Relaunch with a trip in progress
type: flow
features: [guidance-mode, off-route-reroute, route-persistence, route-progress, trip-log]
tags: [flow]
---

# Relaunch with a trip in progress

**Trigger:** The app is killed or relaunched mid-trip.

## Steps
1. The saved route, destination and profile load without network — [[route-persistence]]
2. Guidance resumes; the trip log notes it was restored — [[guidance-mode]] [[trip-log]]
3. Location checks start; the corridor poll fixes progress — [[off-route-reroute]] [[route-progress]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Saved trip vs reality | The user is far from the saved route | partly: corridor reroute |
| Schema change | An old saved trip fails to decode | none |

## Features touched
- [[guidance-mode]] — Guidance mode lifecycle (risk high)
- [[off-route-reroute]] — Off-route detection and reroute (risk high)
- [[route-persistence]] — Trip persistence and restore (risk medium)
- [[route-progress]] — Route progress tracking (risk high)
- [[trip-log]] — On-device trip log (risk low)
