#!/usr/bin/env python3
"""Trims a saved trip (active-trip.json shape) to its last N metres, so a run starts inside the
route-line reveal zone and exercises the last-stretch drawing (GuidanceLineView / bake) instead of
only the long, plain part of a trip.

  make_tail_trip.py trip.json out.json [metres=450]
Numbers and shapes only — the output is a local test fixture, never committed.
"""
import json, math, sys

def dist(a, b):
    R = 6371000.0
    p1, p2 = math.radians(a["latitude"]), math.radians(b["latitude"])
    dl, dp = math.radians(b["longitude"] - a["longitude"]), p2 - p1
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))

src, dst = sys.argv[1], sys.argv[2]
keep = float(sys.argv[3]) if len(sys.argv) > 3 else 450.0
trip = json.load(open(src))
route = trip["route"]
geo = route["geometry"]
cum = [0.0]
for a, b in zip(geo, geo[1:]):
    cum.append(cum[-1] + dist(a, b))
total = cum[-1]
cut = max(0.0, total - keep)
first = next(i for i, c in enumerate(cum) if c >= cut)
new_geo = geo[first:]
offset = cum[first]

steps = []
for s in route["steps"]:
    if s["startAlong"] < cut:
        continue
    t = dict(s)
    t["startAlong"] = max(0.0, s["startAlong"] - offset)
    t["endAlong"] = max(0.0, s["endAlong"] - offset)
    t["startIndex"] = max(0, s["startIndex"] - first)
    t["endIndex"] = max(0, s["endIndex"] - first)
    steps.append(t)
# A synthetic first instruction so the card list starts with a depart.
dep = dict(route["steps"][0])
dep.update(startAlong=0.0, endAlong=steps[0]["startAlong"] if steps else 0.0, startIndex=0, endIndex=steps[0]["startIndex"] if steps else 0,
           startCoordinate=new_geo[0], endCoordinate=new_geo[0])
steps.insert(0, dep)

route["geometry"] = new_geo
route["steps"] = steps
route["distance"] = total - offset
seg = route.get("segmentDurations", [])
spd = route.get("segmentSpeeds", [])
route["segmentDurations"] = seg[first:] if seg else []
route["segmentSpeeds"] = spd[first:] if spd else []
route["duration"] = sum(route["segmentDurations"]) if route["segmentDurations"] else route["duration"] * (route["distance"] / total)
json.dump(trip, open(dst, "w"))
print(f"kept {len(new_geo)} of {len(geo)} points, {route['distance']:.0f} m, {len(steps)} steps")
