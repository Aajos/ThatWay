#!/usr/bin/env python3
"""Turns the watch spike's JSON-lines logs into the numbers for the report.

  analyze_spike_log.py <dir-or-files...>

For each log file prints:
  - Test 1 (session): kind, duration, battery start/end and drop per 30 min, ticks, the longest gap between
    location / heading updates, heartbeat count, scene phases, errors.
  - Test 2 (heading): share of time per source, and the error against GPS course (median, p90, max of |error|)
    for the raw magnetometer and for the blended/filtered heading, over samples where the course is trusted
    (speed >= 1.5 m/s, valid and accurate course).
  - Test 3 (haptics): correct / total per set and per event, with a confusion list.
Numbers only — the logs never contain coordinates, and neither does this output.
"""
import json, sys, glob, os, statistics as st
from collections import Counter, defaultdict

def pct(values, p):
    if not values: return None
    v = sorted(values); return v[min(len(v) - 1, int(round((len(v) - 1) * p)))]

def load(path):
    out = []
    for line in open(path):
        line = line.strip()
        if line:
            try: out.append(json.loads(line))
            except json.JSONDecodeError: pass
    return out

def report(path):
    rows = load(path)
    print("=" * 78); print(os.path.basename(path), f"({len(rows)} lines)")
    by = defaultdict(list)
    for r in rows: by[r.get("type")].append(r)

    sess = by.get("session", [])
    if sess:
        s = sess[0]
        ticks = by.get("tick", []) + by.get("final", [])
        dur = max((r.get("elapsed", 0) for r in ticks), default=0)
        b0 = s.get("battery", -1)
        b1 = next((r["battery"] for r in reversed(ticks) if r.get("battery", -1) >= 0), -1)
        print(f"TEST 1  session {s.get('kind')}  {dur/60:.1f} min  battery {b0}% -> {b1}%", end="")
        if b0 >= 0 and b1 >= 0 and dur > 0: print(f"  drop {(b0 - b1) / dur * 1800:.1f} points per 30 min (whole-percent resolution)")
        else: print()
        print(f"        device {s.get('model')} watchOS {s.get('os')}   thresholds: GPS>={s.get('courseEnter')} m/s, mag<{s.get('magEnter')} m/s")
        t = [r for r in ticks if r.get("type") == "tick"]
        if t:
            zero_loc = [r["elapsed"] for r in t if r.get("locSince", 0) == 0]
            zero_head = [r["elapsed"] for r in t if r.get("headSince", 0) == 0]
            print(f"        30 s ticks: {len(t)}   with NO location update: {len(zero_loc)}   with NO heading update: {len(zero_head)}")
            if zero_loc: print(f"        location silent at elapsed s: {zero_loc[:12]}")
            if zero_head: print(f"        heading silent at elapsed s: {zero_head[:12]}")
        print(f"        heartbeats {len(by.get('heartbeat', []))}   thermal max {max([r.get('thermal', 0) for r in ticks] or [0])}")
        ph = by.get("phase", [])
        if ph: print("        scene phases:", ", ".join(f"{r['phase']}@{r['t']:.0f}s" for r in ph[:16]))
        for e in by.get("error", []): print("        ERROR", e.get("where"), e.get("message"))

    hs = by.get("heading", [])
    if hs:
        src = Counter(r["source"] for r in hs)
        n = sum(src.values())
        print(f"TEST 2  heading samples {n}   source: " + "  ".join(f"{k} {v / n * 100:.0f}%" for k, v in src.items()))
        em = [abs(r["errMag"]) for r in hs if "errMag" in r]
        ef = [abs(r["errFiltered"]) for r in hs if "errFiltered" in r]
        for name, e in (("raw magnetometer", em), ("blended/filtered ", ef)):
            if e: print(f"        error vs GPS course, {name}: n={len(e)} median {st.median(e):.0f}°  p90 {pct(e, .9):.0f}°  max {max(e):.0f}°")
            else: print(f"        error vs GPS course, {name}: no samples with trusted course (>=1.5 m/s)")
        sp = [r["speed"] for r in hs if r.get("speed", -1) >= 0]
        if sp: print(f"        speed m/s: median {st.median(sp):.2f}  p90 {pct(sp, .9):.2f}  max {max(sp):.2f}")

    trials = by.get("hapticTrial", [])
    if trials:
        print("TEST 3  haptic blind test")
        for setname in sorted({t["set"] for t in trials}):
            ts = [t for t in trials if t["set"] == setname]
            ok = sum(1 for t in ts if t["correct"])
            print(f"        set '{setname}': {ok}/{len(ts)} correct")
            for ev in ("left", "right", "arrive", "offRoute"):
                e = [t for t in ts if t["played"] == ev]
                if e:
                    wrong = Counter(t["answer"] for t in e if not t["correct"])
                    rt = [t["reactionMs"] for t in e if t["reactionMs"] >= 0]
                    print(f"          {ev:9s} {sum(1 for t in e if t['correct'])}/{len(e)}  median reaction {st.median(rt):.0f} ms" +
                          (f"  confused as {dict(wrong)}" if wrong else "") if rt else f"          {ev:9s} {sum(1 for t in e if t['correct'])}/{len(e)}")

if __name__ == "__main__":
    files = []
    for a in sys.argv[1:] or ["."]:
        files += sorted(glob.glob(os.path.join(a, "*.jsonl"))) if os.path.isdir(a) else [a]
    if not files: print("no .jsonl files found"); sys.exit(1)
    for f in files: report(f)
