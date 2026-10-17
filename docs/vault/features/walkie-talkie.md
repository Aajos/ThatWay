---
id: walkie-talkie
title: Walkie talkie (push to talk in a trace)
area: audio-haptics
status: planned
risk: high
last_verified: 2026-10-12
introduced: 2026-10-12
build: unreleased
tier: paid
value: 4
release: later
cpu: "not measured (not built)"
memory: "not measured (not built)"
battery: "not measured (not built)"
files:
tests:
manual_checks:
  - Hands-free operation works without touching the screen (headset button or voice) and is the only way offered while the phone is moving
  - A clip sent by one phone is heard by every other phone in the trace chain within a few seconds, then deleted
  - Microphone permission is requested with a clear purpose string, and nothing is recorded while the button is not held
depends_on: [trace-friends, audio-manager]
tags: [feature, area/audio-haptics, status/planned, risk/high]
---

# Walkie talkie (push to talk in a trace)

> **Not built.** A design record: a button on the compass that lets everyone in a trace chain talk to the rest, like a walkie talkie. The decisions below were made on 2026-10-12 and should be re-read before building.

**Area:** [[area-audio-haptics]] · **Status:** planned · **Risk:** high

## The idea
A 3D, tactile button on the compass. Pressed, it speaks to everyone in the trace chain (a convoy of cars following each other is a chain of accepted traces). It appears with an animation, and "WALKIE TALKIE" in an old American radio stencil face animates in and around the button's outer edge.

## Recommendation: compress, store briefly, deliver, delete
**Do not stream raw audio and do not put audio in the database.**
- *Compress always.* Raw 16 kHz mono PCM is about 32 KB a second; AAC at 24 kbps is about 3 KB a second (ten times less), and the CPU cost of encoding is negligible. A 10 second clip is about 30 KB.
- *Short-lived object storage, not DynamoDB.* DynamoDB charges one write unit per KB: a 30 KB clip is 30 write units, which would throttle the free-tier table instantly. Put the clip in S3 (a lifecycle rule that expires it after a day as a backstop) and keep only a tiny metadata row (sender, clip key, expiry) in DynamoDB.
- *Delete on delivery.* The recipient plays it and the clip is removed; the expiry is only the backstop. Nothing is kept, transcribed or logged.
- *Store-and-forward first, true streaming later.* "Over a radio frequency" has no equivalent for a phone app: the choices are (1) short clips sent when the button is released, (2) the same in 1 to 2 second chunks so listeners hear it almost live, or (3) real-time streaming over WebRTC, which needs a media service (Amazon Chime SDK, a WebRTC provider) and is billed per participant minute. Build (1), move to (2) if it feels slow, and only buy (3) if users demand sub-second latency.
- *Latency expectation:* 2 to 5 seconds with polling; under a second only with streaming.

## The chain
Everyone connected to you through accepted traces. The server finds the connected set (capped, say 8 people) and delivers to all of them. Half duplex: if two people press at once, clips are queued in server time order.

## Safety, which comes first
- **A touch button is the wrong control for a moving car.** Handheld use is illegal in many places (including Australia). Offer hands-free first: a headset or AirPods button, voice activation (VOX), CarPlay, or the Apple Watch (the natural fit: tap to talk). While the phone is moving, do not show a "hold to talk" button by default.
- Same consent model as a trace: nobody receives audio from a person they have not both accepted into a trace; a visible indicator whenever the microphone is open; mute per person.
- Microphone permission string and App Review disclosure (audio recording).

## The button and the type
- Spawn animation, depth (layered shadows and a pressed state), haptic on press.
- Lettering around the rim is drawn letter by letter on a circular path. Built-in iOS faces that fit: Copperplate Bold or American Typewriter Bold. The authentic look is a **stencil** face (an Army-stencil style); that means bundling a font file, which needs a licence check and is a download to approve.

## Costs (rough)
S3 and requests are cents; the cost that scales is listeners: a 10 second clip to 8 listeners is 9 requests and about 240 KB. At realistic volume this is under a dollar a month; streaming (WebRTC) is the part that is priced per minute.

## Open items
- Decide hands-free first or on-screen button first (safety).
- Decide store-and-forward versus streaming budget.
- Choose and licence the lettering font.
- The group model: a "convoy" concept on top of pairwise traces, with a size cap.
