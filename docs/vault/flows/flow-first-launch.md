---
id: flow-first-launch
title: First launch and permissions
type: flow
features: [core-package, dial-view, heading, location-issues, location-manager, persistence-defaults, point-mode, route-persistence, theme-system]
tags: [flow]
---

# First launch and permissions

**Trigger:** The app opens for the first time on a phone.

## Steps
1. `ThatWayApp.init` registers the Nunito font and the lift hook — [[theme-system]] [[core-package]]
2. `AppModel` starts, restores persisted preferences and any saved trip — [[persistence-defaults]] [[route-persistence]]
3. Location permission is requested; heading starts once allowed — [[location-manager]] [[heading]]
4. If denied / Precise off / no fix yet the card explains it — [[location-issues]]
5. The idle dial follows north — [[dial-view]] [[point-mode]]

## Where it can break (the seams)

| Seam | What breaks | Caught by |
|---|---|---|
| Font registration vs first Text | Nunito missing falls back silently to the system font | manual: visual check |
| Permission vs first route | Guidance started before a fix routes from a guessed place | manual: cold start with Airplane Mode off |
| Restore vs permissions | A restored trip begins while location is still denied | none |

## Features touched
- [[core-package]] — Shared packages (ThatWayCore, ThatWayUI) (risk high)
- [[dial-view]] — Compass dial and needle (risk medium)
- [[heading]] — Heading pipeline (risk medium)
- [[location-issues]] — Permission, precision and waiting-for-fix handling (risk medium)
- [[location-manager]] — LocationManager (fixes and permission) (risk high)
- [[persistence-defaults]] — Persisted preferences (risk low)
- [[point-mode]] — Point mode (straight-line pointing) (risk medium)
- [[route-persistence]] — Trip persistence and restore (risk medium)
- [[theme-system]] — Themes and shared look (risk low)
