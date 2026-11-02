---
id: flow-compass-wrong
title: The compass goes wrong
type: flow
features: [compass-health, dial-view, heading, location-manager, trip-log]
tags: [flow]
---

# The compass goes wrong

**Trigger:** The phone's compass flips 180 degrees or drifts while guiding.

## Steps
1. Clean samples (moving, steady course) compare compass with GPS direction — [[compass-health]] [[heading]]
2. Two disagreements mark it suspect; the ghost compass appears — [[compass-health]] [[dial-view]]
3. Recalibrate restarts the heading service; or Use GPS direction steers the dial by course — [[location-manager]] [[heading]]
4. The trip log counts the warning, the recalibration and GPS-direction use — [[trip-log]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Phone held sideways | A false alarm | manual: first real walks |
| System-level fault | Restarting our heading stream cannot cure it | by design: GPS direction is the fallback |

## Features touched
- [[compass-health]] — Compass health, ghost overlay, GPS direction (risk medium)
- [[dial-view]] — Compass dial and needle (risk medium)
- [[heading]] — Heading pipeline (risk medium)
- [[location-manager]] — LocationManager (fixes and permission) (risk high)
- [[trip-log]] — On-device trip log (risk low)
