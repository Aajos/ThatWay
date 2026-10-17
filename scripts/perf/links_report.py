#!/usr/bin/env python3
"""Builds docs/perf-links.html (inline SVG charts) from <dir>/results.jsonl.

  scripts/perf/links_report.py /tmp/links docs/perf-links.html
"""
import json, sys, html

rows = [json.loads(l) for l in open(sys.argv[1] + "/results.jsonl")]
base = [r for r in rows if r["case"].startswith("base")]
cases = [r for r in rows if not r["case"].startswith("base")]

def m(r, k): return r.get("mean", {}).get(k, 0.0)
def avg(rs, k): return sum(m(r, k) for r in rs) / max(1, len(rs))
def spread(rs, k):
    v = [m(r, k) for r in rs]
    return (max(v) - min(v)) if v else 0

metrics = [("cpu_pct", "App CPU %"), ("main_pct", "Main-thread CPU %"), ("appPublish", "AppModel publishes /s"),
           ("body.compass", "CompassScreen body /s"), ("body.dial", "Dial body /s")]
b = {k: avg(base, k) for k, _ in metrics}
noise = {k: spread(base, k) for k, _ in metrics}

def bars(key, title):
    items = [("baseline", b[key], "#8a8a8a")] + [(r["case"], m(r, key), "#ff7a1f" if m(r, key) < b[key] - noise[key] else "#4a90d9") for r in cases]
    top = max(v for _, v, _ in items) or 1
    h = 22 * len(items) + 40
    out = [f'<svg width="760" height="{h}" font-family="-apple-system,Helvetica" font-size="12">',
           f'<text x="0" y="16" font-weight="700" font-size="14">{html.escape(title)}</text>']
    for i, (n, v, c) in enumerate(items):
        y = 30 + i * 22
        w = 520 * v / top
        out.append(f'<text x="0" y="{y+13}">{html.escape(n)}</text><rect x="110" y="{y}" width="{w:.1f}" height="16" fill="{c}" rx="3"/>'
                   f'<text x="{116+w:.1f}" y="{y+13}">{v:.2f}</text>')
    nb = b[key] - noise[key]
    out.append(f'<line x1="{110+520*b[key]/top:.1f}" y1="24" x2="{110+520*b[key]/top:.1f}" y2="{h}" stroke="#888" stroke-dasharray="3"/>')
    out.append("</svg>")
    return "\n".join(out)

table = ["<table><tr><th>case</th>" + "".join(f"<th>{t}</th>" for _, t in metrics) + "<th>Δ CPU vs base</th><th>locGap p95 ms</th><th>dial gap p95 ms</th><th>visual diff</th></tr>"]
table.append("<tr><td><b>baseline (3 runs)</b></td>" + "".join(f"<td>{b[k]:.2f} ±{noise[k]:.2f}</td>" for k, _ in metrics) + "<td>-</td><td>-</td><td>-</td><td>0</td></tr>")
for r in cases:
    d = m(r, "cpu_pct") - b["cpu_pct"]
    sig = abs(d) > noise["cpu_pct"]
    g = r.get("gaps", {})
    table.append(f"<tr><td>{r['case']}</td>" + "".join(f"<td>{m(r,k):.2f}</td>" for k, _ in metrics)
                 + f"<td style='color:{'#c33' if sig and d>0 else '#2a7' if sig else '#888'}'>{d:+.2f}</td>"
                 + f"<td>{g.get('locGap',{}).get('p95_ms',0):.0f}</td><td>{g.get('dialUpdate',{}).get('p95_ms',0):.0f}</td><td>{(r.get('visual_diff') or 0):.2f}</td></tr>")
table.append("</table>")

page = f"""<!doctype html><meta charset=utf-8><title>ThatWay link-by-link</title>
<style>body{{font-family:-apple-system,Helvetica;margin:24px;max-width:900px}}table{{border-collapse:collapse;font-size:12px}}td,th{{border:1px solid #ccc;padding:4px 8px;text-align:right}}td:first-child,th:first-child{{text-align:left}}</style>
<h1>ThatWay: link-by-link (2-minute A/B, Release, SE 2nd gen sim, walk guidance)</h1>
<p>Orange = a case that saved more than the baseline noise; blue = no measurable change. Grey dashed line = baseline.
Noise (spread across three baselines): CPU ±{noise['cpu_pct']:.2f} points.</p>
{bars('cpu_pct','App CPU %')}{bars('main_pct','Main-thread CPU %')}{bars('appPublish','AppModel published-state changes per second')}{bars('body.compass','CompassScreen body evaluations per second')}
<h2>All numbers</h2>{''.join(table)}"""
open(sys.argv[2], "w").write(page)
print("wrote", sys.argv[2])
