---
id: how-it-works
title: How this vault works
tags: [index]
---
# How this vault works

## Shape
- `features/` one note per operable feature: what it covers, what it depends on, what depends on it, how it fails, which tests and manual checks guard it.
- `flows/` user situations that cross features, with the **seams** where they can break.
- `areas/` map-of-content per area.
- `process/` the development procedure: stages and the MVP line, value, costs, revenue, accessibility, live testing, optimisation, the commit gate, how the app works, the backend runbook. Hand-written, in order of use.
- `_generated/` produced by `scripts/vault/check_vault.py`: dependency matrix, blast radius, coverage, failure catalogue, gaps, **feature ledger, build timeline, performance evidence, release scope, finance model**. **Never edit these by hand.**

## Two graphs
Open Obsidian's Graph view and use the search box at the top of the panel:
- **Operation graph** (how the app works): `path:features OR path:flows OR path:areas`
- **Development procedure graph** (how it is built, tested and paid for): `path:process`
Colour groups are already set (blue process, purple flows, red high risk, orange spike, green shipped). The two canvases in `process/` draw the same ideas as diagrams. Everything under `_generated/` is hidden from the graph by default (it links to everything) but is the data behind the ledger, timeline and finance charts.

## Setting it up in Obsidian (once)
1. Obsidian, **Open folder as vault**, choose `docs/vault`. When asked about community plugins, leave them off: nothing here needs one (charts are Mermaid, which Obsidian renders itself).
2. The `.obsidian/` folder is committed on purpose (graph colours, property types); only your window layout (`workspace*.json`) is ignored.
3. Open `P0 Product development map` first.

## Conventions
- A feature note's frontmatter is the contract: `id` (= filename), `area`, `status` (shipped / spike / dormant / setting-only / external / planned), `risk` (low / medium / high), `files`, `tests`, `manual_checks`, `depends_on`. Ledger fields (the checker warns when missing): `introduced` (first commit date), `build` (a row in `scripts/vault/versions.json`), `release` (v1.0 / v1.1 / v1.2 / later / internal), `tier` (free / paid / internal), `value` (1 to 5), and `cpu` / `memory` / `battery` which must start with `measured`, `predicted`, `not measured` or `n/a` (say whether it is the simulator or the device).
- `tests` entries are `path` or `path::name`; the checker confirms the path exists and the name occurs in the file.
- Failure points have an ID and a "Caught by" that starts with `test:` / `tests:`, `manual:`, `none` or something looser. `none` shows up in the gap report.
- Link notes with double square brackets around the note id. The "Used by" list is derived from `depends_on`; the checker fails if it drifts.

## Keep it honest
```bash
python3 scripts/vault/check_vault.py          # validate: links, files, tests, used-by, unmapped source
python3 scripts/vault/check_vault.py --write  # also regenerate _generated/
```
It exits non-zero on a broken link, a missing file or test, or a stale "Used by". Run it before a commit that adds or moves code.

## Why Obsidian (and why plain files)
Obsidian's graph and backlinks make the dependency web visible, and wikilinks cost nothing. But nothing here *needs* Obsidian: it is Markdown in the repo, versioned with the code, checked by a script, readable by anyone (and by Claude). Do not store secrets, coordinates or personal data in it.
