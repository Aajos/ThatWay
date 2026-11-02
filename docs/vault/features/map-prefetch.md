---
id: map-prefetch
title: Map download planner and trip planner
area: navigation-core
status: spike
risk: medium
last_verified: 2026-11-02
introduced: 2026-11-02
build: unreleased
tier: paid
value: 5
release: later
cpu: "predicted: a plan for a 100 km drive is computed in well under a second on the Mac; device cost not measured"
memory: "not measured"
battery: "predicted: planning is negligible; the radio cost is what the planner exists to limit (not built yet)"
files:
  - ThatWayCore/Sources/ThatWayCore/MapPrefetch/TileMath.swift
  - ThatWayCore/Sources/ThatWayCore/MapPrefetch/NeedModel.swift
  - ThatWayCore/Sources/ThatWayCore/MapPrefetch/PrefetchPlanner.swift
  - ThatWayCore/Sources/ThatWayCore/MapPrefetch/MapStore.swift
  - ThatWayCore/Sources/ThatWayCore/MapPrefetch/TripPlanner.swift
tests:
  - ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift
manual_checks:
  - When a map source exists: plan a real walk on wifi and on cellular and compare the estimated bytes with what actually downloads (feed the sizes to LearnedCostModel)
  - Walk through a known dead zone with the app: the map and guidance stay up
  - Airplane Mode mid-trip after a wifi download: the map still draws along the route
depends_on: [route-models, travel-modes]
tags: [feature, area/navigation-core, status/spike, risk/medium]
---

# Map download planner and trip planner

> The decision algorithm for WHERE and HOW MUCH of a map to download while travelling, what to throw away, and (for exploring) which places to visit in a time budget. Pure and tested in the shared package. **Nothing downloads yet**: there is no offline map source (Apple Maps may not be cached; OpenStreetMap's tile servers forbid prefetching). The whole design, the research behind it and the decisions it needs are in `docs/map-prefetch-design.md`.

**Area:** [[area-navigation-core]] · **Status:** spike · **Risk:** medium

## What it covers
- `TileMath`: Web-Mercator tiles, ground distances, tiles near a point
- `NeedModel`: how likely each tile is wanted and by when; radius(z) = base × 2^(maxZoom − z) from the route, alternatives, stops, attractions and the person
- `PrefetchPlanner`: policy (wifi, cellular, Low Data, roaming, battery, dead zones), value-per-byte selection with parent tiles, deadlines, and an honest lateness check
- `FlatCostModel` and `LearnedCostModel`: bytes per tile, learned from downloads
- `EvictionPlanner` and `PrivacyBlocks`: what to delete, and the privacy cost of asking a server for tiles
- `TripPlanner` and `TourismScorer`: choose and order places in a time budget (exact up to 13 candidates)

## Depends on
- [[route-models]]
- [[travel-modes]]

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| MP-1 | A tight budget is spent on coarse context and leaves no street detail near the person (a first version did exactly this) | ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift::whenBudgetRunsOutTheNearStretchKeepsItsDetail |
| MP-2 | A tile is fetched without its parents, so the map cannot zoom out | ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift::theMapAlwaysZoomsOutCleanly |
| MP-3 | The byte budget is exceeded | ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift::theBudgetIsNeverExceededAndTheOverviewSurvivesWhenDetailIsCut |
| MP-4 | The map runs out in a dead zone because nothing was fetched before it | ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift::aDeadZoneAheadStretchesTheDownloadAndMovesTheDeadlines |
| MP-5 | A phone on roaming or low battery downloads a lot | ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift::lowDataModeAndRoamingAndLowBatteryShrinkItToWhatIsNeededNow |
| MP-6 | The trip planner returns a worse trip than exists, or one that overruns the time | ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift::itMatchesABruteForceSearchOnSmallProblems |
| MP-7 | The placeholder tile sizes are wrong, so "about 7 MB" is wrong | manual: needs real tiles; LearnedCostModel corrects it from the first trip |
| MP-8 | Tile requests reveal where someone is to the tile host | manual: PrivacyBlocks measures the cost of hiding it; the policy and the host's logging need deciding |
| MP-9 | The map source's licence forbids what the planner does (prefetching) | manual: Apple and OpenStreetMap tile servers forbid it; a self-hosted or offline-friendly source is needed |

## Tests
- `ThatWayCore/Tests/ThatWayCoreTests/MapPrefetchTests.swift`
