# Real-world test logs

The app records numbers about every guided trip so real use on the test phone (iPhone SE 2nd gen, battery
health 73 %) can be compared with the simulator predictions in `perf-weekly.md`.

**Never recorded:** coordinates, place names, route shapes, account details. A route is only its length,
duration and number of steps (`TripLogMathTests` / `TripLogFileTests.logsNeverContainCoordinatesOrNames`).

## When it records
From the moment guidance starts (or a saved trip is restored on launch) until it ends — by arrival, END, or
turning logging off. Nothing is recorded in Point/idle mode. Profile ▸ Test logs ▸ *Record test logs* switches it
off. A sample is taken every 10 s, including while the screen is locked (guidance keeps running).

## Getting the files to Claude
1. **Cable (simplest):** plug the phone in and say so — I copy the folder directly:
   `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.aadittesting.ThatWay.ThatWay --source Documents/TripLogs --destination <folder>`
2. **Share button:** Profile ▸ Test logs ▸ **Share logs** → AirDrop to the Mac, or save to Files / send to yourself.
3. **Files app:** On My iPhone ▸ ThatWay ▸ TripLogs (file sharing is switched on in the app).
The newest 60 trips are kept; **Clear** deletes them all.

## File format (JSON lines, one file per trip: `yyyyMMdd-HHmmss-<mode>.jsonl`)
| line `type` | contents |
|---|---|
| `session` | start time, travel mode, device model, iOS version, app version, whether the trip was restored after a relaunch, Low Power Mode |
| `route` | route length (m), expected duration (s), number of steps — never the shape |
| `sample` (every 10 s) | `t` seconds in; `cpu` % of one core (this app only); `memMB` footprint; `battery` % (−1 unknown), `charging`; `thermal` 0–3; `lowPower`; `screenOn`; `fixes` / `headings` since last sample; `cellRx/Tx`, `wifiRx/Tx` bytes since last sample |
| `event` | `reroute`, `modeChange`, `screenOn`/`screenOff`, `lowPowerOn/Off`, `compassSuspect`, `gpsDirection`, `recalibrate`, `failure.<offline\|timeout\|serverUnavailable\|rateLimited\|noRoute\|noRoadNearby\|locationUnavailable>` |
| `summary` | duration, distance covered vs route length, CPU mean / p95 / max, memory start / peak / end, battery start / end / drop per hour (trips over ~3 min), thermal max, screen-on fraction, GPS fixes and compass updates, network bytes, event counts, free storage start / end, app storage |

## Caveats
- **Network bytes are device-wide** (all apps) for the cellular and Wi-Fi interfaces, not just ThatWay. Compare
  trips, don't read them as the app's own usage.
- **Battery** is whole percent points; a 30-minute trip moves it by only a few points, so judge it across
  several trips (the summary's drop-per-hour only appears for trips longer than ~3 minutes).
- **CPU** is this app's CPU time ÷ wall time (100 % = one full core), comparable with the simulator runs.
- iOS gives apps no per-app energy figure; for that use Xcode's Energy gauge with the phone tethered, or the
  daily MetricKit report (not collected yet).
