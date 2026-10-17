---
id: perf-harness
title: Performance harness (PERF build)
area: power-performance
status: shipped
risk: low
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: internal
value: 3
release: v1.0
cpu: "n/a (debug and PERF builds only)"
memory: "n/a"
battery: "n/a"
files:
  - ThatWay/Perf.swift
  - scripts/perf/link_test.py
  - scripts/perf/make_tail_trip.py
  - docs/perf-weekly.md
tests:
manual_checks:
  - Release + PERF simulator build, one simulator at a time
depends_on: []
tags: [feature, area/power-performance, status/shipped, risk/low]
---

# Performance harness (PERF build)

> Test-only instrumentation: the PERF compile flag, `-TW_OFF` link switches, counters, a 2-minute single-simulator A/B runner and analysis scripts, with the weekly predictions log.

**Area:** [[area-power-performance]] · **Status:** shipped · **Risk:** low

## What it covers
- Counters flushed every 15 s
- `-TW_OFF` links incl. deadreckon
- `-TW_GHOST` forced overlay (PERF only)
- link_test.py, make_tail_trip.py, summarize/links_report
- docs/perf-links.md and perf-weekly.md

## Depends on
- (nothing: a leaf)

## Used by
- [[redraw-model]] — Redraw and publish model

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| PH-1 | More than two simulators at once thrashes the machine and ruins results | process rule |
| PH-2 | Probe overhead distorts what it measures | mitigated: flush every 15 s |

## Tests
- none yet

## Manual checks
- Release + PERF simulator build, one simulator at a time

## Open items
- Simulator CPU is not device CPU; battery and heading cannot be measured here.
