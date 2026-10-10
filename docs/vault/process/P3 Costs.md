---
id: p3-costs
title: Costs
type: process
tags: [process, finance]
---
# Costs

Where the numbers come from: the budget block in `thatway_execution_plan.html` (its own warning: *"All costs here are estimates and none have been checked against current prices"*). The model turns those into a month-by-month chart. Change the assumptions in `process/finance-assumptions.json`, then run:

```bash
python3 scripts/vault/model_finance.py --write
```

(`check_vault.py --write` runs it for you.)

## The expected cost graph and table

![[Finance model#Costs]]

## What each cost is and what moves it
| Cost | Why you pay it | What would make it jump | The check |
|---|---|---|---|
| Apple Developer Program | Required for TestFlight and the App Store (A$150 a year in the plan; enrol by 15 Nov 2026, milestone c01). Also unlocks Sign in with Apple and a proper watch profile | Nothing: fixed yearly | Renewal date in your calendar |
| Domain and website hosting | The info site and the privacy policy URL App Store Connect demands (c02, 5 Jan 2027) | A move off a static host | One invoice a year |
| AWS (Cognito, API Gateway, Lambda, DynamoDB, CloudWatch) | Accounts, friends, proximity tokens. Plan: A$25 a month after credits and the free tier | Sign-up email volume, a chatty polling client, DynamoDB scans, CloudWatch log volume. The proximity feature polls every 2 s *only while the Find sheet is open*; that is the one pattern to watch | Set an AWS Budget alert at A$25 and at A$50; read Cost Explorer once a month |
| Email (SES) | Cognito's default sender is capped at 50 emails a day. SES lifts that for about US$0.10 per 1,000 emails | A sign-up spike, or resend abuse | SES sending statistics; bounce rate under 5 % |
| Routing server | Plan: A$45 a month from Jan 2027 *if* you self-host OSRM. The public demo hosts are "restricted to reasonable, non-commercial use": not for launch | Users: the demo hosts allow about one request per second | Decide before external beta: [[routing-provider-seam]] makes it one URL change |
| Marketing | The plan matches development cash 1:1 up to a A$800 cap; paid ads only after the paid tier exists and conversion is measured | Anything not on this list | The rule in the plan: never more than you have spent on development, never past the cap |
| Contracting income | **Not modelled.** It starts May 2027 and trades your build hours for runway | n/a | [[P1 Stages and the MVP line]] (the 30 April date is the one most at risk) |

## Before you add any paid service
1. Write the monthly cost at 100, 1,000 and 10,000 monthly users. If you cannot, you do not understand the cost yet.
2. Decide the alert threshold *before* turning it on.
3. Add it to `finance-assumptions.json` and regenerate. If it moves break-even, say so in [[P4 Revenue and growth]].
4. Prefer a service that can be turned off without a code change.

## Costs that are not money
Battery, CPU and memory are the costs your *users* pay. They live in [[P7 Optimisation checks]] and [[Performance evidence]]. A feature that is free to you and costs 10 % battery an hour is not free.

## Monthly money check (10 minutes, first of the month)
- [ ] AWS Cost Explorer: total, and the top service. Within plan?
- [ ] SES: sent, bounced, complained
- [ ] Apple: any fee or renewal due in the next 60 days
- [ ] `finance-assumptions.json`: replace one assumption with a real number if you have it; regenerate
