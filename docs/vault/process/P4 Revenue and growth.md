---
id: p4-revenue
title: Revenue and growth
type: process
tags: [process, finance]
---
# Revenue and growth

> Every number on this page is a **scenario**, not a forecast. Prices, installs, conversion and retention are assumptions until real data exists. What the model *can* tell you honestly is **what your own plan range demands**.

Your plan states a revenue range of **A$5k to A$25k a year**. The model asks: how many people must install the app, and how many must buy, for that to be true?

## Expected revenue

![[Finance model#Revenue]]

## Cumulative profit (revenue minus cost)

![[Finance model#Cumulative profit (revenue minus cost)]]

## Future growth: users

![[Finance model#Users]]

## What the numbers are telling you
- **The plan range is a real marketing job, not a given.** The bottom of it needs on the order of 15,000 installs in the first year at a 3 % conversion; the top needs about three times that. Read the exact figures in the table above; they come from your assumptions, so change them and they move.
- **The paid tier is the whole business.** v1.0 is free, so until v1.1 (30 April 2027) revenue is zero by design. All the money lives in how many free users become one-time buyers.
- **Costs are tiny next to the revenue question.** First-year spend is about A$1.7k (see [[P3 Costs]]). The risk is not overspending; it is under-reaching.
- **The conservative case still breaks even slowly or not at all inside the window.** That is the number to remember when deciding how much contracting time to give up ([[P1 Stages and the MVP line]]).

## How the app grows (and what each stage needs)
| Stage | Users | What drives it | What must be true first |
|---|---|---|---|
| v1.0 free, Jan 2027 | Hundreds | Testers' friends; hiking, camping and festival communities in Melbourne (plan: marketing lane) | The compass does not lie ([[compass-health]]); sign-up works; battery is acceptable ([[P7 Optimisation checks]]) |
| v1.1 paid, May 2027 | Low thousands | Friends bring friends (invite rewards); proximity and tracking are the reasons to pay | UWB works between two real phones ([[nearby-proximity]]); purchase and restore work |
| v1.2 skins, Jun 2027 | Growth plateau or a second wave | Looks, themes, the website offers | Skins load from data; nothing hardcoded ([[store-skins]]) |
| Later | Decided on 31 Aug 2027 from real numbers | Offline routing, creator skins with a revenue share | Retention and conversion measured, not guessed |

## Metrics to start collecting the day TestFlight opens
| Metric | Where | Why |
|---|---|---|
| Installs and proceeds | App Store Connect, Sales and Trends | The real replacement for the installs assumption |
| Day 1, day 7, day 30 retention | App Store Connect, App Analytics (opted-in users only) | The real monthly retention (the model assumes 78 % to 85 %) |
| Free to paid conversion | Purchases divided by installs | The real conversion (the model assumes 2 % to 4 %) |
| Crash-free sessions | Xcode Organizer, Crashes | Below 99.5 % hurts reviews and ranking |
| Battery complaints | Beta feedback form (add a battery question) | The thing a navigation app is judged on |
| Cost per user | AWS bill divided by monthly actives | Tells you when self-hosting or SES pays for itself |

## Replacing assumptions with data (the monthly habit)
1. Open `process/finance-assumptions.json`.
2. Replace one assumption with a measured value (for example `monthly_retention` from App Analytics).
3. Run `python3 scripts/vault/model_finance.py --write` and read what moved.
4. In the commit message, say which number was replaced and by what.

## Not modelled (on purpose)
- Contracting income (May 2027 onward) and your runway: that is a life decision, tracked in the plan's "Life and runway" lane.
- Skin sales and any creator revenue share: no price or volume exists yet.
- Tax, GST and currency effects on Apple payouts.
- Refunds (Apple keeps these out of proceeds, so real numbers will sit a little under the model).

Related: [[P2 Feature value and scope]], [[P3 Costs]].
