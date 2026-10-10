#!/usr/bin/env python3
"""Turns the CSVs written by perf_run.py into a markdown table (and heap growth by class).

  scripts/perf/summarize.py /tmp/perf
"""
import csv, os, re, sys

def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            rows.append({"t": float(r["t"]), "phase": r["phase"],
                         "fp": None if r["footprint_kb"] in ("None", "") else float(r["footprint_kb"]),
                         "cpu": None if r["cpu_pct"] in ("None", "") else float(r["cpu_pct"])})
    return rows

def slope_kb_per_min(rows):
    pts = [(r["t"] / 60.0, r["fp"]) for r in rows if r["fp"] is not None]
    n = len(pts)
    if n < 3:
        return None
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    den = sum((p[0] - mx) ** 2 for p in pts)
    return None if den == 0 else sum((p[0] - mx) * (p[1] - my) for p in pts) / den

def avg(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None

def heap_classes(path):
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path):
        m = re.match(r"\s*(\d+)\s+(\d+)\s+[\d.]+\s+(\S.*?)\s{2,}", line)
        if m:
            out[m.group(3)] = (int(m.group(1)), int(m.group(2)))
    return out

def fmt(x, nd=1):
    return "-" if x is None else f"{x:.{nd}f}"

def main(d):
    modes = [f[:-4] for f in sorted(os.listdir(d)) if f.endswith(".csv")]
    order = [m for m in ("idle", "walk", "run", "cycle", "drive") if m in modes]
    print("| mode | start MB | end MB | peak MB | drift KB/min (after 3 min) | CPU % foreground | CPU % background |")
    print("|---|---|---|---|---|---|---|")
    for m in order:
        rows = load(os.path.join(d, f"{m}.csv"))
        fps = [r["fp"] for r in rows if r["fp"] is not None]
        steady = [r for r in rows if r["t"] >= 180]
        fg = [r["cpu"] for r in rows if r["phase"] == "foreground" and r["t"] >= 60]
        bg = [r["cpu"] for r in rows if r["phase"] == "background" and r["t"] >= 660]
        print(f"| {m} | {fmt(steady[0]['fp']/1024 if steady else None)} | {fmt(fps[-1]/1024)} | {fmt(max(fps)/1024)} | {fmt(slope_kb_per_min(steady))} | {fmt(avg(fg),2)} | {fmt(avg(bg),2)} |")
    print()
    for m in order:
        a, b = heap_classes(os.path.join(d, f"{m}-heap-start.txt")), heap_classes(os.path.join(d, f"{m}-heap-end.txt"))
        growth = sorted(((b[k][1] - a.get(k, (0, 0))[1], k, b[k][0] - a.get(k, (0, 0))[0]) for k in b), reverse=True)[:5]
        print(f"**{m}** top heap growth (bytes, count): " + "; ".join(f"{k} +{g}B/+{c}" for g, k, c in growth if g > 0) or "none")

if __name__ == "__main__":
    main(sys.argv[1])
