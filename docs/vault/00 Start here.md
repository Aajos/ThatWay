---
id: start
title: Start here
tags: [index]
---
# ThatWay feature map

A map of what the app does, which parts depend on which, how each can fail and what catches it. It is meant to be **read**:
half of finding a bug is looking at two boxes and the arrow between them.

- Counts, coverage and gaps live in `_generated/Coverage` (regenerate with `python3 scripts/vault/check_vault.py --fix --write`).
- Open this folder (`docs/vault`) as a vault in Obsidian and use **Graph view**: nodes are features, edges are "depends on"; high-risk, spike and setting-only notes are coloured.
- Everything is plain Markdown, so it also reads fine on GitHub or in any editor.

## Where to look
| I want to… | Go to |
|---|---|
| see the whole shape | [[01 Architecture map]] |
| browse by area | [[area-navigation-core]] · [[area-guidance-ui]] · [[area-location-sensors]] · [[area-routing]] · [[area-audio-haptics]] · [[area-power-performance]] · [[area-app-shell]] · [[area-accounts-backend]] · [[area-watch]] · [[area-shared-modules]] |
| trace a user situation across features | [[flow-first-launch]] · [[flow-start-guidance]] · [[flow-guidance-refresh]] · [[flow-off-route]] · [[flow-mode-change]] · [[flow-phone-locked]] · [[flow-offline-midroute]] · [[flow-arrival]] · [[flow-compass-wrong]] · [[flow-relaunch-restore]] · [[flow-watch-guidance]] |
| see what is broken, unwired or untested | [[03 Known gaps]] and `_generated/Gaps` |
| know what a change could break | `_generated/Blast radius` |
| add or change a feature | [[04 Changing the app]] |
| keep this honest | [[02 How this vault works]] |
