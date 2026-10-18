#!/usr/bin/env python3
"""Turns docs/vault/process/finance-assumptions.json into monthly cost, revenue, user-base and net tables plus
Mermaid charts, written to docs/vault/_generated/Finance model.md (embedded by the finance notes).

  python3 scripts/vault/model_finance.py            print the headline numbers
  python3 scripts/vault/model_finance.py --write    also rewrite the generated note

Deliberately simple, so every number can be explained in one sentence:
  new installs      = launch burst for the first months, then organic installs growing a fixed % a month up to a cap
  monthly actives   = last month's actives * retention + new installs * activation
  purchases         = conversion * new installs after the paid tier exists
                      + existing_upgrade spread evenly over the first 3 paid months, applied to the actives at that point
  net revenue       = purchases * price * (1 - store cut)
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
SRC = os.path.join(REPO, 'docs', 'vault', 'process', 'finance-assumptions.json')
OUT = os.path.join(REPO, 'docs', 'vault', '_generated', 'Finance model.md')

def months(first, last):
    y, m = map(int, first.split('-')); ly, lm = map(int, last.split('-')); out = []
    while (y, m) <= (ly, lm):
        out.append(f'{y:04d}-{m:02d}'); m += 1
        if m == 13: y, m = y + 1, 1
    return out

def idx(ms, key): return ms.index(key)

def build(cfg):
    ms = months(cfg['first_month'], cfg['last_month'])
    n = len(ms)
    free_i, paid_i = idx(ms, cfg['free_launch_month']), idx(ms, cfg['paid_launch_month'])

    # ---- costs
    dev = [0.0] * n
    for c in cfg['costs']:
        s = idx(ms, c['start'])
        for i in range(s, n):
            if c['repeat'] == 'monthly' or (c['repeat'] == 'yearly' and (i - s) % 12 == 0) or (c['repeat'] == 'once' and i == s):
                dev[i] += c['amount']
    mk = cfg['marketing']
    first_year = [i for i, m in enumerate(ms) if cfg['first_month'] <= m <= '2027-09']
    dev_year = sum(dev[i] for i in first_year)
    mkt_total = min(mk['cap'], mk['ratio'] * dev_year)
    mkt_ms = [i for i, m in enumerate(ms) if mk['first_month'] <= m <= mk['last_month']]
    mkt = [0.0] * n
    for i in mkt_ms: mkt[i] = mkt_total / len(mkt_ms)
    cost = [dev[i] + mkt[i] for i in range(n)]

    # ---- scenarios
    res = {}
    price, cut = cfg['price_one_time'], cfg['store_cut']

    def simulate(s, scale):
        installs, mau, purchases = [0.0] * n, [0.0] * n, [0.0] * n
        organic = s['organic_start'] * scale
        for i in range(n):
            if i < free_i: continue
            k = i - free_i
            organic = min(s['organic_cap'] * scale, organic * (1 + s['organic_growth'])) if k else s['organic_start'] * scale
            burst = s['burst_installs'] * scale / s['burst_months'] if k < s['burst_months'] else 0
            installs[i] = burst + organic
        for i in range(n):
            mau[i] = (mau[i - 1] if i else 0) * s['monthly_retention'] + installs[i] * s['activation']
        for i in range(paid_i, n):
            p = installs[i] * s['conversion']
            if i - paid_i < 3 and paid_i: p += s['existing_upgrade'] * mau[paid_i - 1] / 3
            purchases[i] = p
        net = [p * price * (1 - cut) for p in purchases]
        return installs, mau, purchases, net

    for name, s in cfg['scenarios'].items():
        scale = 1.0
        if 'target_net_12m' in s:                      # everything is linear in installs, so one division solves it
            base = sum(simulate(s, 1.0)[3][paid_i:paid_i + 12])
            scale = s['target_net_12m'] / base if base else 1.0
        installs, mau, purchases, net = simulate(s, scale)
        cum_installs = [sum(installs[:i + 1]) for i in range(n)]
        cum_rev = [sum(net[:i + 1]) for i in range(n)]
        cum_cost = [sum(cost[:i + 1]) for i in range(n)]
        cum_profit = [cum_rev[i] - cum_cost[i] for i in range(n)]
        first12 = sum(net[paid_i:paid_i + 12])
        be = next((ms[i] for i in range(n) if cum_profit[i] >= 0 and cum_rev[i] > 0), None)
        res[name] = dict(installs=installs, mau=mau, purchases=purchases, net=net, cum_installs=cum_installs, cum_rev=cum_rev,
                         cum_profit=cum_profit, first12=first12, breakeven=be, buyers12=sum(purchases[paid_i:paid_i + 12]),
                         note=s.get('note', ''), scale=scale, installs12=sum(installs[free_i:free_i + 12]))
    return dict(ms=ms, dev=dev, mkt=mkt, cost=cost, cum_cost=[sum(cost[:i + 1]) for i in range(n)], res=res,
                dev_year=dev_year, mkt_total=mkt_total, paid_i=paid_i, free_i=free_i, cfg=cfg)

def r(x): return f'{x:,.0f}'

def chart(title, ms, series, ytitle, step=3):
    """Quarterly points with unique labels (Mermaid merges duplicate category labels, which scrambles the lines)."""
    pick = list(range(0, len(ms), step))
    if pick[-1] != len(ms) - 1: pick.append(len(ms) - 1)
    labels = ', '.join(f'"{ms[i]}"' for i in pick)
    top = max(max(s[i] for i in pick) for _, s in series) or 1
    low = min(min(s[i] for i in pick) for _, s in series)
    out = f'```mermaid\nxychart-beta\n    title "{title}"\n    x-axis [{labels}]\n    y-axis "{ytitle}" {0 if low >= 0 else int(low * 1.1) - 1} --> {int(top * 1.1) + 1}\n'
    for _, vals in series:
        out += '    line [' + ', '.join(f'{vals[i]:.0f}' for i in pick) + ']\n'
    out += '```\n'
    out += '*Quarterly points. Lines, in order: ' + ', '.join(n for n, _ in series) + '.*\n'
    return out

def render(m):
    cfg, ms = m['cfg'], m['ms']
    cur = cfg['currency']
    o = '---\ntags: [generated]\n---\n# Finance model\n\n> Generated by `scripts/vault/model_finance.py --write` from `process/finance-assumptions.json`. Do not edit by hand: change the assumptions and regenerate.\n\n'
    o += ('**Read this first.** Costs come from the execution plan (its own caveat: estimates, not checked against current prices). '
          'Price, installs, conversion and retention are *assumptions*, not data. Three scenarios bracket your plan\'s own A$5k to A$25k a year. '
          'Replace the assumptions with real TestFlight and App Store numbers as soon as they exist.\n\n')
    o += '## Assumptions in force\n\n'
    o += f'- Currency {cur}; free v1.0 launch **{cfg["free_launch_month"]}**, paid tier (v1.1) **{cfg["paid_launch_month"]}**\n'
    o += f'- Paid tier = one-time purchase at **{cur} {cfg["price_one_time"]}**, Apple keeps {cfg["store_cut"]*100:.0f}% (Small Business Program)\n'
    o += f'- Marketing = the smaller of the cap ({cur} {cfg["marketing"]["cap"]}) and {cfg["marketing"]["ratio"]}x first-year development cash, spread over {cfg["marketing"]["first_month"]} to {cfg["marketing"]["last_month"]}\n\n'
    o += '| Scenario | Installs at launch | Organic start /mo | Organic growth | Conversion | Retention /mo | Note |\n|---|---|---|---|---|---|---|\n'
    for name, s in cfg['scenarios'].items():
        o += f'| {name} | {s["burst_installs"]} over {s["burst_months"]} mo | {s["organic_start"]} (cap {s["organic_cap"]}) | {s["organic_growth"]*100:.0f}% | {s["conversion"]*100:.0f}% | {s["monthly_retention"]*100:.0f}% | {s["note"]} |\n'

    o += '\n## Costs\n\n'
    o += '| Item | Amount | Starts | Repeats |\n|---|---|---|---|\n'
    for c in cfg['costs']: o += f'| {c["name"]} | {cur} {c["amount"]} | {c["start"]} | {c["repeat"]} |\n'
    o += f'| Marketing (earned from development spend, capped) | {cur} {r(m["mkt_total"])} in total | {cfg["marketing"]["first_month"]} | spread evenly |\n'
    o += f'\nFirst plan year (to 2027-09): development cash **{cur} {r(m["dev_year"])}**, marketing **{cur} {r(m["mkt_total"])}**, total **{cur} {r(m["dev_year"] + m["mkt_total"])}**. Contracting income is deliberately not modelled here.\n\n'
    o += chart('Cumulative cost (' + cur + ')', ms, [('Cost', m['cum_cost'])], 'AUD')
    o += '\n### Cost by month\n\n| Month | Development | Marketing | Total | Cumulative |\n|---|---|---|---|---|\n'
    for i, mo in enumerate(ms):
        if m['cost'][i]: o += f'| {mo} | {r(m["dev"][i])} | {r(m["mkt"][i])} | {r(m["cost"][i])} | {r(m["cum_cost"][i])} |\n'

    o += '\n## Revenue\n\n'
    o += '| Scenario | Installs needed, first 12 months | Buyers, first 12 paid months | Net revenue, first 12 paid months | Cumulative net to ' + ms[-1] + ' | Cumulative profit to ' + ms[-1] + ' | Break-even month |\n|---|---|---|---|---|---|---|\n'
    for name, d in m['res'].items():
        o += f'| {name} | {r(d["installs12"])} | {r(d["buyers12"])} | {cur} {r(d["first12"])} | {cur} {r(d["cum_rev"][-1])} | {cur} {r(d["cum_profit"][-1])} | {d["breakeven"] or "not within the model"} |\n'
    o += '\n' + chart('Cumulative net revenue (' + cur + ')', ms, [(k, d['cum_rev']) for k, d in m['res'].items()], 'AUD')
    o += '\n## Cumulative profit (revenue minus cost)\n\n'
    o += chart('Cumulative profit (' + cur + ')', ms, [(k, d['cum_profit']) for k, d in m['res'].items()] + [('Zero', [0] * len(ms))], 'AUD')
    o += '\n## Users\n\n'
    o += '| Scenario | Total installs by ' + ms[-1] + ' | Monthly active users then | Peak monthly installs |\n|---|---|---|---|\n'
    for name, d in m['res'].items():
        o += f'| {name} | {r(d["cum_installs"][-1])} | {r(d["mau"][-1])} | {r(max(d["installs"]))} |\n'
    o += '\n' + chart('Total installs', ms, [(k, d['cum_installs']) for k, d in m['res'].items()], 'installs')
    o += '\n' + chart('Monthly active users', ms, [(k, d['mau']) for k, d in m['res'].items()], 'users')
    return o

def main():
    cfg = json.load(open(SRC))
    m = build(cfg)
    cur = cfg['currency']
    print(f'first plan year: dev {cur} {r(m["dev_year"])}, marketing {cur} {r(m["mkt_total"])}')
    for name, d in m['res'].items():
        print(f'{name:13} installs(first 12 mo) {r(d["installs12"]):>7}  buyers(12mo) {r(d["buyers12"]):>6}  net(12mo) {cur} {r(d["first12"]):>7}  installs {r(d["cum_installs"][-1]):>7}  MAU {r(d["mau"][-1]):>6}  break-even {d["breakeven"]}')
    if '--write' in sys.argv:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        open(OUT, 'w').write(render(m)); print('wrote', os.path.relpath(OUT, REPO))

if __name__ == '__main__':
    main()
