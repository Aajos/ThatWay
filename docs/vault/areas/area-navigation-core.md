---
id: area-navigation-core
title: Navigation core
type: area
tags: [area]
---

# Navigation core

The behaviour of getting somewhere: modes, route progress, off-route, arrival, ETA, dead reckoning, search and the map.

| Feature | Status | Risk | Tests |
|---|---|---|---|
| [[point-mode]] | shipped | medium | 1 |
| [[guidance-mode]] | shipped | high | 2 |
| [[compass-tilt]] | shipped | low | 1 |
| [[route-progress]] | shipped | high | 3 |
| [[arrival]] | shipped | medium | 1 |
| [[off-route-reroute]] | shipped | high | 2 |
| [[eta]] | shipped | low | 0 |
| [[dead-reckoning]] | shipped | medium | 1 |
| [[travel-modes]] | shipped | medium | 2 |
| [[mode-change-reroute]] | shipped | medium | 1 |
| [[destination-search]] | shipped | medium | 0 |
| [[map-tab]] | shipped | medium | 0 |

## Reaches into other areas
- [[audio-manager]] (audio-haptics)
- [[background-guidance]] (location-sensors)
- [[bearing-math]] (shared-modules)
- [[compass-health]] (location-sensors)
- [[dial-view]] (guidance-ui)
- [[heading]] (location-sensors)
- [[location-issues]] (location-sensors)
- [[location-manager]] (location-sensors)
- [[location-profile]] (location-sensors)
- [[persistence-defaults]] (app-shell)
- [[route-failure]] (routing)
- [[route-models]] (shared-modules)
- [[route-persistence]] (routing)
- [[routing-governor]] (routing)
- [[trip-log]] (power-performance)

## Used from other areas
- [[audio-cue-plan]] (audio-haptics)
- [[dial-view]] (guidance-ui)
- [[guidance-cards]] (guidance-ui)
- [[location-profile]] (location-sensors)
- [[route-data-generator]] (routing)
- [[route-line]] (guidance-ui)
- [[route-tracker]] (watch)
- [[search-ui]] (guidance-ui)
- [[settings-profile]] (app-shell)
- [[travel-mode-carousel]] (guidance-ui)

Back to [[00 Start here]].
