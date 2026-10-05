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
- `_generated/` produced by `scripts/vault/check_vault.py`: dependency matrix, blast radius, coverage, failure catalogue, gaps, unmapped source files. **Never edit these by hand.**

## Conventions
- A feature note's frontmatter is the contract: `id` (= filename), `area`, `status` (shipped / spike / dormant / setting-only / external / planned), `risk` (low / medium / high), `files`, `tests`, `manual_checks`, `depends_on`.
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
