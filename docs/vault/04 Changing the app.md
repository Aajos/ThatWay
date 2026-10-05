---
id: changing
title: Changing the app
tags: [index]
---
# Changing the app: use the map

## Before you change something
1. Find its note (search by file name: every source file is claimed by a feature; the checker lists any that are not).
2. Read **Used by**: that is the blast radius. `_generated/Blast radius` lists everything downstream, transitively.
3. Read **Failure points** and **Scenarios that pass through it**: those are the situations to re-check by hand.
4. Run the listed tests; do the listed manual checks.

## When you add a feature
- Copy the shape of a nearby note, give it an `id`, an `area`, honest `status` and `risk`.
- List the files, the tests (even if none: say so), the features it depends on. If something now depends on it, add it to *their* `depends_on`.
- Add a scenario step or a new flow if it changes a user situation.
- Run the checker. A new source file that no note claims is reported as **unmapped**.

## When something breaks
- Find the failing seam in a flow note; if the failure was not listed, add it with an ID and what would have caught it. A bug that was not on the map is a gap in the map.
- If nothing caught it, that is a `none` in the failure catalogue: write the test, or write why not.

## Smell tests (from this project's history)
- A published write or a view reading the whole model undoes the redraw savings: see [[redraw-model]].
- A setting with no reader is a lie: see [[settings-profile]] and [[haptics-ios]].
- Two copies of the same maths drift: see [[route-progress]] and [[route-tracker]].
- Anything near the wrap point of an angle needs [[continuous-angle]].
- A new shared type needs `public` and an initialiser: see [[core-package]].
