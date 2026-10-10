#!/usr/bin/env python3
"""2-minute A/B per link of the guidance chain, one simulator, strictly sequential.

Each case relaunches the app with `-TW_PERF 1 -TW_OFF <links>`, replays the same GPS track along the
same saved trip, and after 120 s reads the app's own counters (Documents/perf-result.json). Results are
appended to <out>/results.jsonl as they finish, so nothing is lost if the run is stopped.

  scripts/perf/link_test.py --app ThatWay.app --trip trip.json --out /tmp/links [--only dial,anim]
The app must be built with SWIFT_ACTIVE_COMPILATION_CONDITIONS=PERF and Config.backendEnabled = false.
Numbers only: no coordinates are written anywhere.
"""
import argparse, json, math, os, subprocess, sys, time

BUNDLE = "com.aadittesting.ThatWay.ThatWay"
SE2 = "com.apple.CoreSimulator.SimDeviceType.iPhone-SE--2nd-generation-"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
SECONDS = 120

LINKS = ["loc", "locprofile", "tick", "refresh", "sched", "advance", "arrival", "eta", "tilt", "audio",
         "persist", "deadreckon", "topbar", "cards", "dial", "dialfx", "aura", "anim", "etarow"]
ALL_OFF = ["tick", "refresh", "sched", "topbar", "cards", "dial", "aura", "etarow"]


def sh(*a, check=True, input=None):
    r = subprocess.run(a, capture_output=True, text=True, input=input)
    if check and r.returncode:
        raise RuntimeError(f"{a[:3]} {r.stderr.strip()}")
    return r.stdout.strip()


def dist(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl, dp = math.radians(b[1] - a[1]), p2 - p1
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def track(trip):
    g = [(p["latitude"], p["longitude"]) for p in json.load(open(trip))["route"]["geometry"]]
    out, carry = [g[0]], 0.0
    for a, b in zip(g, g[1:]):
        carry += dist(a, b)
        if carry >= 20:
            out.append(b); carry = 0
    return "\n".join(f"{la:.6f},{lo:.6f}" for la, lo in out) + "\n"


def wait_idle():
    for _ in range(4):
        load = float(sh("sysctl", "-n", "vm.loadavg").split()[1])
        if load < 14:
            return load
        time.sleep(3)
    return load


def bmp_signature(png):
    bmp = png.replace(".png", ".bmp")
    sh("sips", "-Z", "120", "-s", "format", "bmp", png, "--out", bmp, check=False)
    return open(bmp, "rb").read() if os.path.exists(bmp) else b""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True); ap.add_argument("--trip", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--only", default=""); ap.add_argument("--seconds", type=int, default=120); ap.add_argument("--first", type=int, default=0); ap.add_argument("--nobase", action="store_true"); ap.add_argument("--repeat", type=int, default=1); ap.add_argument("--mode", default="walk")
    args = ap.parse_args()
    global SECONDS
    SECONDS = args.seconds
    os.makedirs(args.out, exist_ok=True)
    cases = [("base1", []), ("base2", []), ("base3", [])] + [(l, [l]) for l in LINKS] + [("all", ALL_OFF)]
    if args.only:
        want = set(args.only.split(","))
        cases = [c for c in cases if c[0] in want or (c[0].startswith("base") and not args.nobase)]
        cases = [(f"{n}#{i+1}" if args.repeat > 1 else n, o) for n, o in cases for i in range(args.repeat)]
    if args.first:
        cases = cases[:args.first]
    sim = sh("xcrun", "simctl", "create", "TW-LINKS", SE2, RUNTIME)
    try:
        sh("xcrun", "simctl", "boot", sim); sh("xcrun", "simctl", "bootstatus", sim, "-b", check=False)
        sh("xcrun", "simctl", "install", sim, args.app)
        sh("xcrun", "simctl", "privacy", sim, "grant", "location", BUNDLE)
        sh("xcrun", "simctl", "spawn", sim, "defaults", "write", BUNDLE, "travelMode.v1", "-string", args.mode)
        sh("xcrun", "simctl", "spawn", sim, "defaults", "write", BUNDLE, "audioStyle.v1", "-string", "tone")
        sh("xcrun", "simctl", "launch", sim, BUNDLE); time.sleep(3); sh("xcrun", "simctl", "terminate", sim, BUNDLE, check=False)
        container = sh("xcrun", "simctl", "get_app_container", sim, BUNDLE, "data")
        support = os.path.join(container, "Library", "Application Support"); os.makedirs(support, exist_ok=True)
        open(os.path.join(support, "active-trip.json"), "wb").write(open(args.trip, "rb").read())
        pts = track(args.trip)
        result_file = os.path.join(container, "Documents", "perf-result.json")
        baseline_sig = None
        for name, off in cases:
            load = wait_idle()
            sh("xcrun", "simctl", "terminate", sim, BUNDLE, check=False)
            if os.path.exists(result_file): os.remove(result_file)
            sh("xcrun", "simctl", "location", sim, "start", "--speed=1.4", "-", input=pts)
            t0 = time.time()
            sh("xcrun", "simctl", "launch", sim, BUNDLE, "-TW_PERF", "1", "-TW_OFF", ",".join(off))
            shot = os.path.join(args.out, f"{name}.png")
            time.sleep(max(1, SECONDS - 25))
            sh("xcrun", "simctl", "io", sim, "screenshot", shot, check=False)
            time.sleep(max(0, SECONDS - (time.time() - t0)))
            sh("xcrun", "simctl", "location", sim, "clear", check=False)
            try:
                res = json.load(open(result_file))
            except Exception as e:
                res = {"error": str(e)}
            sig = bmp_signature(shot)
            if name == "base1": baseline_sig = sig
            diff = None
            if baseline_sig and sig and len(sig) == len(baseline_sig):
                diff = sum(abs(a - b) for a, b in zip(baseline_sig[54:], sig[54:])) / (len(sig) - 54)
            rec = {"case": name, "off": off, "load_before": load, "visual_diff": diff, **res}
            with open(os.path.join(args.out, "results.jsonl"), "a") as f:
                f.write(json.dumps(rec) + "\n")
            print(name, "cpu", res.get("mean", {}).get("cpu_pct"), flush=True)
    finally:
        sh("xcrun", "simctl", "shutdown", sim, check=False); sh("xcrun", "simctl", "delete", sim, check=False)


if __name__ == "__main__":
    main()
