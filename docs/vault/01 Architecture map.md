---
id: architecture
title: Architecture map
tags: [index]
---
# Architecture map

```mermaid
flowchart TB
  subgraph Shared["Shared packages (iPhone + watch)"]
    Core["ThatWayCore: route models, bearing maths, travel modes, route tracker, heading blender, haptic patterns"]
    UI["ThatWayUI: themes, Nunito, needle skins"]
  end
  subgraph Phone["iPhone app"]
    Model["AppModel (hub): lifecycle, refresh chain, published state"]
    Loc["LocationManager + LocationProfile"]
    Route["RoutingManager + governor + providers"]
    Screens["CompassScreen: DialView, cards, route line, carousel, search"]
    Audio["AudioManager"]
    Logs["TripLog + Perf harness"]
  end
  subgraph Watch["Watch app (spike)"]
    W["WatchModel + HeadingBlender + RouteTracker + session A/B + haptics"]
  end
  subgraph Cloud["External"]
    OSRM["OSRM routing hosts"]
    AWS["Cognito + API Gateway + Lambda"]
  end
  Loc --> Model
  Model --> Route
  Route --> OSRM
  Model --> Screens
  Model --> Audio
  Model --> Logs
  Core --> Phone
  Core --> Watch
  UI --> Screens
  UI --> Watch
  Model -. sign-in gate .-> AWS
```

## How to read it
- **AppModel is the hub.** Almost every feature reaches the screen or the speaker through it, which is why [[guidance-mode]] and [[redraw-model]] are rated high risk.
- **The seams that have broken before** (each is a real bug found while building): heading not republishing in idle ([[dial-view]]), keyboard resizing the layout ([[compass-screen-layout]]), a wrapped angle spinning the dial ([[continuous-angle]]), routing from a guessed position ([[location-issues]]), the compass check running when idle ([[compass-health]]).
- The areas are listed in [[00 Start here]]; the per-feature dependency arrows live in each note and in `_generated/Dependency matrix`.
