---
id: area-location-sensors
title: Location and sensors
type: area
tags: [area]
---

# Location and sensors

Where the traveller is and which way they face: fixes, accuracy, heading, compass health, background running, permission states.

| Feature | Status | Risk | Tests |
|---|---|---|---|
| [[location-manager]] | shipped | high | 1 |
| [[location-profile]] | shipped | medium | 1 |
| [[heading]] | shipped | medium | 0 |
| [[compass-health]] | shipped | medium | 1 |
| [[continuous-angle]] | shipped | low | 2 |
| [[background-guidance]] | shipped | high | 0 |
| [[location-issues]] | shipped | medium | 0 |

## Reaches into other areas
- [[audio-manager]] (audio-haptics)
- [[core-package]] (shared-modules)
- [[dial-view]] (guidance-ui)
- [[travel-modes]] (navigation-core)
- [[trip-log]] (power-performance)

## Used from other areas
- [[dead-reckoning]] (navigation-core)
- [[destination-search]] (navigation-core)
- [[dial-view]] (guidance-ui)
- [[guidance-mode]] (navigation-core)
- [[heading-blender]] (watch)
- [[point-mode]] (navigation-core)

Back to [[00 Start here]].
