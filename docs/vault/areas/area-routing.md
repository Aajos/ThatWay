---
id: area-routing
title: Routing
type: area
tags: [area]
---

# Routing

Getting and holding a route: provider seam, governor, failure diagnosis, persistence, line data.

| Feature | Status | Risk | Tests |
|---|---|---|---|
| [[routing-provider-seam]] | shipped | high | 3 |
| [[routing-governor]] | shipped | high | 1 |
| [[route-failure]] | shipped | medium | 1 |
| [[route-persistence]] | shipped | medium | 0 |
| [[route-data-generator]] | shipped | medium | 0 |

## Reaches into other areas
- [[backend-config]] (accounts-backend)
- [[route-models]] (shared-modules)
- [[route-progress]] (navigation-core)
- [[travel-modes]] (navigation-core)

## Used from other areas
- [[arrival]] (navigation-core)
- [[guidance-mode]] (navigation-core)
- [[mode-change-reroute]] (navigation-core)
- [[off-route-reroute]] (navigation-core)
- [[route-line]] (guidance-ui)

Back to [[00 Start here]].
