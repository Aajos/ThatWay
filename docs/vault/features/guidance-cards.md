---
id: guidance-cards
title: Guidance cards
area: guidance-ui
status: shipped
risk: medium
last_verified: 2026-10-05
files:
  - ThatWay/Compass/GuidanceCardsView.swift
  - ThatWay/Compass/CompassScreen.swift
tests:
manual_checks:
  - Run a trip on an iPhone SE at default and large text: no truncation, no overlap
  - Pull the stack up and down
depends_on: [route-progress, theme-system, redraw-model]
tags: [feature, area/guidance-ui, status/shipped, risk/medium]
---

# Guidance cards

> The active instruction card, the next two stacked behind it in the last stretch, the 'Up next' stack under the compass, and the full-list curtain. The stacks take plain values and are Equatable.

**Area:** [[area-guidance-ui]] · **Status:** shipped · **Risk:** medium

## What it covers
- Front card: icon, short title, road, phase line, distance, END
- Peek cards with depth fan
- 'Up next' stack (first card with content, two behind)
- Curtain: scrollable full list with the current card highlighted, pull-down to close
- matchedGeometry between collapsed and expanded
- Dynamic Type: cards grow, 'Up next' hides at accessibility sizes

## Depends on
- [[route-progress]] — Route progress tracking
- [[theme-system]] — Themes and shared look
- [[redraw-model]] — Redraw and publish model

## Used by
- [[compass-screen-layout]] — Compass screen layout and small screens

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| GC-1 | Card text renders from stale values (equatable skip hides a change) | manual: GuidanceStackState holds every shown string |
| GC-2 | Layout overflow on small screens / large text | manual on SE |

## Tests
- none yet

## Manual checks
- Run a trip on an iPhone SE at default and large text: no truncation, no overlap
- Pull the stack up and down

## Open items
- The curtain still observes the whole model (only drawn while expanded).

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-offline-midroute]] — Losing the connection mid-trip
