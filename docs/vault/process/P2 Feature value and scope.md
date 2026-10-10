---
id: p2-value
title: Feature value and scope
type: process
tags: [process]
---
# Feature value and scope

Every feature note carries three fields that feed the generated [[Release scope]] and [[Feature ledger]]:

| Field | Values | Meaning |
|---|---|---|
| `release` | `v1.0`, `v1.1`, `v1.2`, `later`, `internal` | Which planned release it ships in. `internal` = users never see it (harness, logging, plumbing) |
| `tier` | `free`, `paid`, `internal` | Who gets it. The plan: v1.0 free; v1.1 paid adds tracking and proximity; v1.2 skins |
| `value` | 1 to 5 | What it is worth to a user *if it works*. See the scale below |

The first values were **proposed from the execution plan and the code, not decided by you**. Treat them as a draft to argue with, then edit the notes.

## The value scale (use it the same way every time)
| Score | Meaning | Test question |
|---|---|---|
| 5 | The reason the app exists | Without it, would anyone keep the app? |
| 4 | Users notice within a day and would complain if it broke | Would a one-star review mention it? |
| 3 | Makes the core feel finished or trustworthy | Would you notice it missing within a week? |
| 2 | Nice; a subset of users care | Would anyone notice? |
| 1 | Tooling or decoration | Only you ever sees it |

## How to decide whether something is worth building
Score it on four lines, in this order. Stop at the first "no".

1. **Does it belong to a release?** If it is not in the plan, either add it to the plan (and say what it pushes out) or write it under `later`. A feature added without a release is how January slips.
2. **Value against cost.** Cost is engineering days *plus* the standing cost it adds: CPU and battery ([[P7 Optimisation checks]]), a new failure surface ([[Failure catalogue]]), a new service bill ([[P3 Costs]]), a new thing to test on a device ([[P6 Live testing]]).
3. **Risk against evidence.** A `risk: high` feature needs tests *and* a manual check *and* a measured cost before it ships. The checker lists the ones that do not ([[Gaps]], [[Performance evidence]]).
4. **Can it be a setting-only or spike instead?** A thing that is stored but read by nothing is a lie to the user (see [[03 Known gaps]]); mark it `setting-only` honestly or do not ship the control.

## Where the value is concentrated
The scope table below is generated; read it left to right: how many features, how much value, and which of them are not actually shipped yet.

![[Release scope]]

## Reading it
- **v1.0** should hold the highest-value (4 and 5) features and nearly all of the `shipped` ones. Any v1.0 feature still `spike`, `dormant` or `setting-only` is a gate failure in [[P1 Stages and the MVP line]].
- **v1.1 paid** is where the proximity feature ([[nearby-proximity]]) earns its keep: value 4, but `risk: high`, hardware-dependent, and the test phone cannot run it. That is the single biggest scheduling risk in the plan.
- **later** holds the watch. It has real value (haptic guidance without looking at a phone) but is not in the plan's milestones; promote it deliberately or leave it.

## Keeping it honest
- When a feature ships to a release, change `status` and `release` together and rerun the checker.
- When you cut a feature, do not delete the note: set `release: later` and say why in "Open items". A cut feature that disappears gets rebuilt by accident.
- When a user (a tester, a review) tells you something is worth more or less than your score, change the score and write the quote's *meaning* (not their name) in the note.

Related: [[P1 Stages and the MVP line]], [[P4 Revenue and growth]].
