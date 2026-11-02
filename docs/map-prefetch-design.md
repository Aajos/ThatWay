# Map downloads and tourism: design

Status: the **decision algorithm is built and tested** (`ThatWayCore/Sources/ThatWayCore/MapPrefetch`, 44 tests). Nothing downloads
yet, because that needs a map source, and choosing one is yours (section 2). Written 2026-11-02.

## 1. The problem

While someone travels, decide **where** and **how much** of a map to download, and **what to throw away**, so that:

- the map and the guidance never go blank when the signal does (a tunnel, a trail, roaming off);
- data, storage and battery are not wasted on places the person will not go;
- exploring is fun: nearby places worth seeing are already there when they decide to detour, and a few hours can be turned into a good route.

## 2. What the research changed (read this first)

| Fact | Consequence |
|---|---|
| **Apple's Maps terms prohibit caching or prefetching MapKit data** beyond a temporary performance cache ([Apple forum thread quoting the terms](https://developer.apple.com/forums/thread/20648); the quoted agreement is from 2017, so check Apple's current terms) | The current Map tab (MapKit) can never work offline. Offline needs a different map source |
| **OpenStreetMap's own tile servers prohibit bulk download and offline use** ([raster policy](https://operations.osmfoundation.org/policies/tiles/), [vector policy](https://operations.osmfoundation.org/policies/vector/)) | We cannot point the app at tile.openstreetmap.org and prefetch. We need self-hosted tiles or a provider that allows offline use |
| **Protomaps/PMTiles**: the whole planet is about 120 GB; a city or region extract is about 90 to 200 MB; each extra zoom level roughly doubles the size ([Protomaps downloads](https://docs.protomaps.com/basemaps/downloads)). Tiles are ordered along a Hilbert curve, so nearby tiles are nearby bytes and HTTP range requests fetch them cheaply | Self-hosting is cheap (one file on S3 behind CloudFront). It also suggests the transport: fetch byte ranges for exactly the tiles the planner chooses |
| One iOS SDK's docs say PMTiles sources do not support its offline-pack download ([MapMetrics iOS](https://docs.mapatlas.xyz/overview/sdk/ios-native/PMTiles)); the MapLibre docs say to bundle a regional file locally for fully offline use | Whether MapLibre Native on iOS can read tiles we download ourselves needs a small proof before we commit (decision 2 below) |
| Valhalla (routing) is MIT-licensed and runs on iOS ([Valhalla](https://github.com/Valhalla/valhalla)); OpenStreetMap data is ODbL (credit required) | On-device rerouting is possible but heavy. Meanwhile the planned route is simply saved; if someone leaves it offline, the compass still points to the destination |

The planner is therefore **map-source-agnostic**: it works in tiles (z/x/y), bytes and seconds. Whatever serves the map only has to turn a
`TileID` into bytes.

## 3. The algorithm

One function from the situation to an ordered download list: `PrefetchPlanner.plan(input, cost:) -> PrefetchPlan`. Four layers.

### 3.1 Policy: how far ahead, how many bytes

| Situation | Plans ahead | Spends at most |
|---|---|---|
| Offline | nothing | 0 |
| **Wifi** | the whole trip | the trip pack (150 to 250 MB by mode) |
| **Cellular** | the next 15 min walking, 12 cycling, 8 driving | 20 to 30 MB a round |
| Cellular, **Low Data Mode** | a third of that | a quarter of that |
| **Roaming**, or battery under 15% and not charging | the next 3 minutes, finest detail only | 3 MB |
| A **dead zone** ahead (any of the above) | stretched to when signal returns, plus a minute | up to the trip pack |

### 3.2 Need: how likely is each tile wanted, and by when

Everything is a probability and a deadline. A **source** (the route, an alternative route, a stop, an attraction, the person themself) reaches
tiles within a radius that **doubles every zoom out**:

    radius(z) = baseRadius × 2^(maxZoom − z)

Tiles double in width each zoom out, so each level costs about half the tiles of the one below it and the whole pyramid costs about twice its
finest level. That single rule replaces a pile of thresholds: street detail stays near the path, wide context is there cheaply.

| Source | Base radius (at the finest zoom) | Weight |
|---|---|---|
| Route | corridor: walk 120 m, cycle 250 m, drive 600 m, **widened** by speed × 20 s reroute delay × 1.5 and 3 × GPS error | 1 |
| Alternative routes (multi-routing) | same corridor | the chance of taking it |
| The person now | 250 to 1000 m | 1 |
| No route: where they are heading, dead-reckoned from heading and speed | corridor | 0.6 |
| Destination or waypoint | 250 m, up to 500 m for a long stay | 1 |
| Attraction (tourism) | 120 m | interest × how worth seeing × e^(−detour minutes / 20); more than a 30-minute detour is ignored |

Finest zoom: walk and run 17, cycle 16, drive 15.

### 3.3 Selection: best value for the bytes

For every candidate tile: **value = probability × usefulness of that zoom × e^(−seconds until needed / 1200)**, and **density = value / bytes**.
Pick by density, within the budget. Choosing a tile also brings in its missing parent tiles (their bytes counted), so the map always zooms out cleanly.

- Near stretches are worth more than far ones, so when budget runs short **the far detail is dropped, never the street around the person**.
- A first version filled coarse to fine and spent a tight budget on mid-zoom context, leaving nothing at street level. Tests caught it; this replaced it.

### 3.4 Order and honesty

- Download order: what is needed soonest first, a minute at a time, coarse before fine inside a minute.
- A **dead zone** moves every deadline that falls inside it to just before it starts (what comes after can wait for signal).
- The plan is replayed at the measured throughput, and says which tiles will arrive late and whether a dead zone will start before the map is ready.

### 3.5 What to throw away

`EvictionPlanner`: when the store is over budget it frees down to 85% of it. Lowest keep-score goes first: the need model's retention (how likely
it is wanted again given where the person is going) plus a small bonus for recent use. Saved trips and the home area are **pinned**. A tile the person
has just passed goes before one still ahead.

### 3.6 Learning real sizes

`FlatCostModel` is a placeholder (about 30 to 60 KB a tile). `LearnedCostModel` keeps an average of what each zoom actually weighs and replaces the guess
as tiles download, so the "this trip is about 7 MB" estimate gets honest after the first trip.

## 4. What it plans for a real trip (placeholder tile sizes)

| Trip | Tiles | About | Notes |
|---|---|---|---|
| 5 km walk, wifi | 167 | 7 MB | 56 at street level, 8 overview |
| 5 km walk, cellular | 94 | 4 MB | the next 15 minutes |
| 5 km walk, 5 MB budget | 117 | 5 MB | 50 tiles dropped, all far detail |
| 30 km ride, wifi | 332 | 16 MB | |
| 100 km drive, wifi | 692 | 37 MB | |
| 100 km drive, cellular | 136 | 7 MB | the next 8 minutes |
| Standing at the hotel, no route | 79 | 4 MB | around you, plus attractions within a 15-minute walk |

## 5. Privacy: asking for tiles tells a server roughly where someone is

Every tile request reveals location. Options, in order of cost:

1. **Do nothing special** (exact tiles): cheapest, most precise leak.
2. **Round requests up to whole blocks** (`PrivacyBlocks`): the server only learns a coarse block (a z12 block is about 8 km across). It costs the rest of the block: the tests show a bigger block hides more and costs more, and the overhead is measured so it can be chosen, not guessed.
3. Host the tiles on our own CDN with **no request logging** and no account identifier on the requests (we control this).

The privacy policy already names the route provider; it will need a line for the tile host. Nothing here is stored off the phone: the "signal memory" for dead-zone
prediction (coarse cells, on the phone, deletable) never leaves it.

## 6. Multi-routing and trips (built: `TripPlanner`)

- **Alternatives**: the routing service returns several routes; each becomes a source weighted by how likely it is taken, so the map covers the plausible ones without paying for all.
- **Multi-stop trips**: given places worth seeing, a time budget (and optionally a finish point, opening hours and must-visit stops), choose which and in what order to see the most. This is the orienteering problem; up to 13 candidates are solved **exactly** (checked against brute force), more are narrowed to the best 13 first. Travel times come from a closure: road times from OSRM's table service when online, straight-line estimates when offline.
- **Scoring places** (`TourismScorer`): the best-matching interest, lifted by how well known the place is, cut when it is closed. A landmark you did not ask for still scores a little.

## 7. Making tourism fun (ideas, not yet built; pick what fits)

The app is a compass, so the most distinctive idea is **compass-first discovery**:

1. **Wander mode**: no destination. The needle points to the most interesting thing within a 15-minute walk, with only a distance; the place is revealed on arrival. A treasure hunt, one point at a time.
2. **"I have 90 minutes"**: you say how long and roughly where you end up; the trip planner builds a loop of the best stops that fits, and the prefetcher has already got the map.
3. **Themes**: history, food, nature, street art, kid-friendly: the interest profile the scorer uses.
4. **Stamps**: visited places collect, with a short story card (text is tiny to prefetch).
5. **With friends**: the existing trace permission already finds a friend; "meet at the next interesting place" is the planner picking a stop between you.
6. **Scenic routes**: needs a routing engine that can weight beauty over speed (Valhalla can; the current OSRM demo cannot per request).

## 8. Data sources for places (to verify before use)

| Source | Gives | Licence note |
|---|---|---|
| OpenStreetMap | places, tags (tourism, historic, amenity), links to Wikipedia and Wikidata | ODbL: credit required, share-alike for derived databases |
| Wikidata | identifiers, and how many language editions cover a place (a good popularity signal) | CC0 |
| Wikipedia / Wikivoyage | short descriptions and travel text | CC BY-SA: credit required |
| Overture Maps places | more businesses and opening hours | **not verified**: check its licence before bundling |

## 9. What is built, and what is not

| Built and tested | Not built |
|---|---|
| Tile maths, need model, planner and policy, cost models, eviction, privacy blocks, trip planner, place scoring | Anything that downloads tiles |
| | A map source and renderer; the offline Map tab |
| | Reading real tile sizes and dead zones from the phone (the "signal memory") |
| | Place data and the Wander mode / trip screens |
| | The UI: a "Download this trip: about 7 MB" sheet and a storage manager |

## 10. Decisions for you

1. **Map source for offline.** Self-host a PMTiles extract (cheap: the planet is about 120 GB, roughly US$3 a month to store, and a trip is about 7 MB to fetch) or pay a provider that explicitly allows offline use. I lean self-hosted, with the planner choosing byte ranges.
2. **Renderer.** MapLibre Native on iOS (open source) is the obvious fit, but whether it can read tiles we download ourselves needs a small proof first. This also decides whether the existing MapKit Map tab is replaced or kept for online use.
3. **Offline rerouting.** Save the route and point the compass when off it (simple, what the app does already), or embed Valhalla (heavy). I lean the first until the second is proven needed.
4. **Privacy default**: exact tiles, or blocks (the cost is shown by the planner).
5. **Storage budget** default (I would start at 500 MB, user-adjustable) and whether trips are saved to keep (pinned).
6. **Which tourism ideas** in section 7 to build first. I would start with Wander mode and "I have 90 minutes", since they use the compass and the trip planner you already have.
7. **Place data** sources and who is credited.
8. The route provider and licensing questions already on the launch report still apply: offline map tiles from a provider with commercial terms, and credit lines for OpenStreetMap.
