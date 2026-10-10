#!/usr/bin/env python3
"""Long-session CPU / memory harness for ThatWay on iPhone SE (2nd generation) simulators.

One simulator per mode, run in parallel. Each run: seed the mode and a saved trip, play a GPS track
along it at that mode's speed, keep the app in the foreground for --fg minutes, then push it to the
background (Settings in front) for the rest. Every --interval seconds it records the app's physical
footprint and CPU use, and it snapshots `heap` at the start and end so growth can be traced to a class.

Nothing here logs coordinates: the GPS track is fed straight to `simctl location` and only
numbers (memory, CPU) are written out.

  scripts/perf/perf_run.py --app /path/ThatWay.app --trip trip.json --out /tmp/perf \
      --minutes 30 --fg 10 --modes walk,run,cycle,drive,idle

The app must be built with Config.backendEnabled = false so it opens straight to the compass.
Simulator numbers are for CPU and memory trends only: energy needs a real device (Instruments > Energy Log).
"""
import argparse, json, math, os, re, subprocess, sys, threading, time

BUNDLE = "com.aadittesting.ThatWay.ThatWay"
SE2 = "com.apple.CoreSimulator.SimDeviceType.iPhone-SE--2nd-generation-"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
SPEEDS = {"walk": 1.4, "run": 3.0, "cycle": 6.0, "drive": 11.5}  # m/s


def sh(*args, check=True, input=None):
    r = subprocess.run(args, capture_output=True, text=True, input=input)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} -> {r.stderr.strip()}")
    return r.stdout.strip()


def dist(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl, dp = math.radians(b[1] - a[1]), p2 - p1
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def waypoints(trip_path, step=25.0):
    trip = json.load(open(trip_path))
    g = [(p["latitude"], p["longitude"]) for p in trip["route"]["geometry"]]
    out, carry = [g[0]], 0.0
    for a, b in zip(g, g[1:]):
        d = dist(a, b)
        carry += d
        if carry >= step:
            out.append(b)
            carry = 0.0
    out.append(g[-1])
    return "\n".join(f"{la:.6f},{lo:.6f}" for la, lo in out) + "\n", g[0]


def footprint_kb(pid, tmp):
    """Exact physical footprint in KB, from `footprint --json` (the plain output rounds to whole MB)."""
    sh("footprint", "-p", str(pid), "--json", tmp, check=False)
    try:
        return json.load(open(tmp))["processes"][0]["auxiliary"]["phys_footprint"] / 1024.0
    except Exception:
        return None


def cpu_seconds(pid):
    t = sh("ps", "-o", "time=", "-p", str(pid), check=False)
    if not t:
        return None
    parts = t.split(":")
    secs = 0.0
    for p in parts:
        secs = secs * 60 + float(p)
    return secs


def run_mode(mode, args, results):
    name = f"TW-PERF-{mode}"
    sim = sh("xcrun", "simctl", "create", name, SE2, RUNTIME)
    try:
        sh("xcrun", "simctl", "boot", sim)
        sh("xcrun", "simctl", "bootstatus", sim, "-b", check=False)
        sh("xcrun", "simctl", "install", sim, args.app)
        sh("xcrun", "simctl", "privacy", sim, "grant", "location", BUNDLE)
        if mode != "idle":
            sh("xcrun", "simctl", "spawn", sim, "defaults", "write", BUNDLE, "travelMode.v1", "-string", mode)
            sh("xcrun", "simctl", "spawn", sim, "defaults", "write", BUNDLE, "audioStyle.v1", "-string", "tone")
        sh("xcrun", "simctl", "launch", sim, BUNDLE)
        time.sleep(3)
        sh("xcrun", "simctl", "terminate", sim, BUNDLE, check=False)
        track, start = waypoints(args.trip)
        if mode != "idle":
            container = sh("xcrun", "simctl", "get_app_container", sim, BUNDLE, "data")
            support = os.path.join(container, "Library", "Application Support")
            os.makedirs(support, exist_ok=True)
            with open(args.trip, "rb") as src, open(os.path.join(support, "active-trip.json"), "wb") as dst:
                dst.write(src.read())
            sh("xcrun", "simctl", "location", sim, "start", f"--speed={SPEEDS[mode]}", "-", input=track)
        else:
            sh("xcrun", "simctl", "location", sim, "set", f"{start[0]:.6f},{start[1]:.6f}")
        out = sh("xcrun", "simctl", "launch", sim, BUNDLE)
        pid = int(out.split(":")[-1])
        csv_path = os.path.join(args.out, f"{mode}.csv")
        with open(csv_path, "w") as f:
            f.write("t,phase,footprint_kb,cpu_pct\n")
        samples, t0, last_cpu, last_t = [], time.time(), None, None
        heap_start = None
        total = args.minutes * 60
        backgrounded = False
        while True:
            elapsed = time.time() - t0
            if elapsed >= total:
                break
            if not backgrounded and elapsed >= args.fg * 60:
                sh("xcrun", "simctl", "launch", sim, "com.apple.Preferences", check=False)
                backgrounded = True
            fp = footprint_kb(pid, os.path.join(args.out, f".fp-{mode}.json"))
            cpu = cpu_seconds(pid)
            pct = None
            if cpu is not None and last_cpu is not None and elapsed > last_t:
                pct = 100.0 * (cpu - last_cpu) / (elapsed - last_t)
            last_cpu, last_t = cpu, elapsed
            sample = {"t": round(elapsed), "phase": "background" if backgrounded else "foreground",
                      "footprint_kb": fp, "cpu_pct": None if pct is None else round(pct, 2)}
            samples.append(sample)
            with open(csv_path, "a") as f:
                f.write(f"{sample['t']},{sample['phase']},{sample['footprint_kb']},{sample['cpu_pct']}\n")
            if heap_start is None and elapsed > 120:
                heap_start = sh("heap", str(pid), "-s", check=False)
                open(os.path.join(args.out, f"{mode}-heap-start.txt"), "w").write(heap_start)
            time.sleep(args.interval)
        heap_end = sh("heap", str(pid), "-s", check=False)
        open(os.path.join(args.out, f"{mode}-heap-end.txt"), "w").write(heap_end)
        results[mode] = samples
    finally:
        sh("xcrun", "simctl", "shutdown", sim, check=False)
        sh("xcrun", "simctl", "delete", sim, check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--trip", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--minutes", type=float, default=30)
    ap.add_argument("--fg", type=float, default=10, help="minutes in the foreground before backgrounding")
    ap.add_argument("--interval", type=float, default=15)
    ap.add_argument("--modes", default="walk,run,cycle,drive,idle")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    results, threads = {}, []
    for mode in args.modes.split(","):
        t = threading.Thread(target=lambda m=mode: run_mode(m, args, results))
        t.start()
        threads.append(t)
        time.sleep(5)
    for t in threads:
        t.join()
    json.dump(results, open(os.path.join(args.out, "summary.json"), "w"))
    print("done", list(results))


if __name__ == "__main__":
    main()
