#!/usr/bin/env python3
"""One-off helper that wrote `introduced` / `build` into every feature note's frontmatter from git history.

For each feature it finds the earliest commit in which a characteristic symbol (or, failing that, the feature's primary
file) appeared (`git log -S`), and maps that commit to a dev build via versions.json. Kept so the method is reproducible;
new features just get their `introduced` / `build` written by hand when the note is created.

  python3 scripts/vault/backfill_history.py          print what it would write
  python3 scripts/vault/backfill_history.py --apply  write it into notes that do not have the keys yet
"""
import os, re, sys, json, subprocess, glob
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
VAULT = os.path.join(REPO, 'docs', 'vault', 'features')
builds = json.load(open(os.path.join(os.path.dirname(__file__), 'versions.json')))['builds']
commit_build = {c: b['build'] for b in builds for c in b['commits']}

# feature -> symbol that first appears when the feature does (pickaxe over the whole history); others use files[0]
SIGNATURE = {
    'arrival': 'arrived', 'bearing-math': 'func bearing', 'continuous-angle': 'ContinuousAngle',
    'route-models': 'struct RouteStep', 'theme-system': 'struct AppTheme', 'guidance-mode': 'func startGuidance',
    'location-issues': 'locationIssue', 'mode-change-reroute': 'scheduleModeChangeReroute', 'off-route-reroute': 'offRoute',
    'persistence-defaults': 'UserDefaults', 'redraw-model': 'DialHost', 'travel-modes': 'enum TravelMode',
    'routing-provider-seam': 'protocol RoutingProvider', 'haptics-ios': 'UIImpactFeedbackGenerator',
    'background-guidance': 'isIdleTimerDisabled', 'audio-cue-plan': 'AudioManager', 'compass-screen-layout': 'struct CompassScreen',
}

def git(*args): return subprocess.run(['git', *args], cwd=REPO, capture_output=True, text=True).stdout.strip().splitlines()

def first_commit(fid, files):
    if fid in SIGNATURE:
        rows = git('log', '-S' + SIGNATURE[fid], '--format=%h %ad', '--date=short')
    else:
        rows = git('log', '--diff-filter=A', '--format=%h %ad', '--date=short', '--', files[0])
    return rows[-1].split() if rows else None

for p in sorted(glob.glob(f'{VAULT}/*.md')):
    fid = os.path.basename(p)[:-3]
    text = open(p, encoding='utf-8').read()
    if re.search(r'^introduced:', text, re.M): continue
    files = [l[4:].strip() for l in re.search(r'^files:\n((?:  - .*\n)+)', text, re.M).group(1).splitlines()]
    hit = first_commit(fid, files)
    if not hit: print(f'{fid:24} no history (new, uncommitted)'); date, build = '2026-10-09', 'unreleased'
    else: date, build = hit[1], commit_build.get(hit[0], '?')
    print(f'{fid:24} {date} build {build}')
    if '--apply' in sys.argv:
        text = re.sub(r'(^last_verified: .*\n)', r'\1introduced: ' + date + '\nbuild: ' + build + '\n', text, count=1, flags=re.M)
        open(p, 'w', encoding='utf-8').write(text)
