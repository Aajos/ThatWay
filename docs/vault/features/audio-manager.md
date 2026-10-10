---
id: audio-manager
title: Audio manager (tones and voice)
area: audio-haptics
status: shipped
risk: high
last_verified: 2026-10-05
introduced: 2026-10-05
build: 0.7
tier: free
value: 4
release: v1.0
cpu: "not measured"
memory: "not measured"
battery: "not measured"
files:
  - ThatWay/Managers/AudioManager.swift
tests:
  - ThatWayTests/AudioManagerTests.swift
manual_checks:
  - Music playing: cue plays over it; a call mid-trip then resumes
  - Headphones unplugged mid-trip
depends_on: [audio-cue-plan, persistence-defaults]
tags: [feature, area/audio-haptics, status/shipped, risk/high]
---

# Audio manager (tones and voice)

> Audio session and playback for guidance cues: tones (AVAudioPlayer from generated WAV), spoken cues, mixing with music (ducking only when asked), interruption and route-change handling, trip-long session.

**Area:** [[area-audio-haptics]] · **Status:** shipped · **Risk:** high

## What it covers
- `.playback` + `.mixWithOthers`; duck only if requested
- Trip-long session (`prepareForGuidance`/`finishGuidance`)
- Interruption (calls) and route-change (headphones) observers
- Tone buffers, stereo pan
- Off / Tone / Voice style, persisted

## Depends on
- [[audio-cue-plan]] — Audio cue plan, panning, voice script
- [[persistence-defaults]] — Persisted preferences

## Used by
- [[arrival]] — Arrival detection and completion
- [[background-guidance]] — Background guidance, scene phases, screen awake
- [[guidance-mode]] — Guidance mode lifecycle
- [[settings-profile]] — Settings and Profile screen

## Failure points

| ID | What breaks | Caught by |
|---|---|---|
| AM-1 | Starting an audio engine stalls the test host (tests only configure the session) | by design in tests |
| AM-2 | Session left active after the trip (blocks other apps' audio) | manual: END and arrival call `finishGuidance` |
| AM-3 | Audio cues cost about 0.5 CPU points in the simulator | perf harness; verify on device |

## Tests
- `ThatWayTests/AudioManagerTests.swift`

## Manual checks
- Music playing: cue plays over it; a call mid-trip then resumes
- Headphones unplugged mid-trip

## Open items
- Voice cue wording and the unwired 'Voice of directions' setting.

## Scenarios that pass through it
- [[flow-start-guidance]] — Search, pick, start guidance
- [[flow-guidance-refresh]] — One second of guidance (the refresh chain)
- [[flow-phone-locked]] — Phone locked mid-trip
- [[flow-arrival]] — Arriving
