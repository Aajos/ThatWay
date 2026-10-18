---
id: flow-watch-drive-guard
title: "Phone in Drive mode: the watch refuses"
type: flow
features: [phone-watch-link, travel-modes, watch-drive-guard, watch-session, watch-travel-modes]
tags: [flow]
---

# Phone in Drive mode: the watch refuses

**Trigger:** The iPhone user selects Drive (or the watch app is opened while the phone is already in Drive mode).

## Steps
1. The iPhone mode change is sent to the watch as WatchConnectivity context and message — [[travel-modes]] [[phone-watch-link]]
2. The watch app receives it live, or reads the stored context when it launches — [[phone-watch-link]]
3. Drive is not a watch mode: everything stops (sessions, location, heading, route) — [[watch-drive-guard]] [[watch-session]] [[watch-travel-modes]]
4. The notice explains why and a countdown runs; the app closes itself after 6 s — [[watch-drive-guard]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| No connection to the phone | An unpaired, out-of-range or uninstalled-companion watch never hears the phone is driving | by design: documented; manual |
| Launch window | About 3 s pass between a cold launch and the stored context arriving | manual: seen in the simulator |
| Embed and signing | Without the companion embed no link exists; with it, iPhone device builds need the watch profile | manual: first device install |
| Self-termination | `exit(0)` may be rejected in App Review | none: revisit before shipping |

## Features touched
- [[phone-watch-link]]
- [[travel-modes]]
- [[watch-drive-guard]]
- [[watch-session]]
- [[watch-travel-modes]]
