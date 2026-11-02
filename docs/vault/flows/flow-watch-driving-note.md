---
id: flow-watch-driving-note
title: "Phone in Drive mode: the watch ignores it"
type: flow
features: [phone-watch-link, travel-modes, watch-driving-note, watch-travel-modes]
tags: [flow]
---

# Phone in Drive mode: the watch ignores it

**Trigger:** The iPhone user selects Drive (or the watch app is opened while the phone is already in Drive mode).

## Steps
1. The iPhone mode change is sent to the watch as WatchConnectivity context and message — [[travel-modes]] [[phone-watch-link]]
2. The watch receives it live, or reads the stored context when it launches — [[phone-watch-link]]
3. Drive is not a watch mode, so the watch ignores it and keeps its own walk, run or cycle mode; nothing stops and nothing closes — [[watch-driving-note]] [[watch-travel-modes]]
4. The watch's main screen already says "Not safe to use while driving"; that note is the whole rule — [[watch-driving-note]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Someone uses the watch while driving | Nothing prevents it; only the note | by design: decided 2026-11-02 |
| Embed and signing | Without the companion embed no link exists; with it, iPhone device builds need the watch profile | manual: first device install |

## Features touched
- [[phone-watch-link]]
- [[travel-modes]]
- [[watch-driving-note]]
- [[watch-travel-modes]]
