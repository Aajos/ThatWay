---
id: watch-spike-log
title: Watch spike log and analysis
area: watch
status: spike
risk: low
last_verified: 2026-10-05
files:
  - ThatWayWatch/SpikeLog.swift
  - scripts/watch/analyze_spike_log.py
  - docs/watch-spike.md
tests:
manual_checks:
  - Run the analyser on a simulator log (done)
depends_on: []
tags: [feature, area/watch, status/spike, risk/low]
---

# Watch spike log and analysis

> Numbers-only JSON-lines log on the watch (speed, heading, course, accuracy, source, battery, counts, haptic trials) and a script that turns it into the report numbers.

**Area:** [[area-watch]] · **Status:** spike · **Risk:** low

## What it covers
- No coordinates ever
- Error of magnetometer and blended heading vs GPS course
- Silent-tick detection for Test 1
- Haptic accuracy and confusions

## Depends on
- (nothing: a leaf)

## Used by
- [[watch-haptics]] — Watch haptic patterns
- [[watch-session]] — Watch wrist-down session (A/B)

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| SL-1 | Log lines carry a location by mistake | none: no unit test on the watch side |

## Tests
- none yet

## Manual checks
- Run the analyser on a simulator log (done)

## Open items
- Add a no-coordinates test like the iPhone trip log has.

## Scenarios that pass through it
- [[flow-watch-guidance]] — Guidance on the watch
