#!/usr/bin/env python3
"""Validates the feature-map vault (docs/vault) against the codebase and regenerates its reports.

  python3 scripts/vault/check_vault.py            validate only
  python3 scripts/vault/check_vault.py --write    validate, then rewrite docs/vault/_generated/*
  python3 scripts/vault/check_vault.py --fix      first rewrite every note's derived "## Used by" list from depends_on (then validate)

Checks (errors fail the run, exit code 1):
  - every feature note has the required frontmatter, an id equal to its filename, a known status/risk, an existing area
  - every `files:` path exists; every `tests:` path exists and any `path::name` name occurs in that file
  - every `depends_on` id exists; no feature depends on itself
  - every [[wikilink]] in every note resolves to a note
  - each feature's "## Used by" list equals the reverse of everyone's depends_on (it must not drift)
  - flow notes only reference existing features
Optional ledger fields (validated when present, warned about when missing): introduced (YYYY-MM-DD), build (a row in versions.json),
  tier (free|paid|internal), value (1-5), release (v1.0|v1.1|v1.2|later|internal), cpu/memory/battery (start with measured, predicted,
  not measured or n/a). They feed the generated Feature ledger, Build timeline, Performance evidence and Release scope notes.
Warnings (printed, do not fail): Swift source files that no feature claims ("unmapped"), dependency cycles.
Numbers and structure only: the vault holds no coordinates, secrets or personal data.
"""
import os, re, sys, subprocess, glob, json, datetime
from collections import defaultdict

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
VAULT = os.path.join(REPO, 'docs', 'vault')
STATUSES = {'shipped', 'spike', 'dormant', 'setting-only', 'external', 'planned'}
RISKS = {'low', 'medium', 'high'}
REQUIRED = ['id', 'title', 'area', 'status', 'risk', 'files', 'tests', 'manual_checks', 'depends_on']
SOURCE_ROOTS = ['ThatWay', 'ThatWayCore/Sources', 'ThatWayWatch']
TIERS = {'free', 'paid', 'internal'}
RELEASES = {'v1.0', 'v1.1', 'v1.2', 'later', 'internal'}
PERF_PREFIXES = ('measured', 'predicted', 'not measured', 'n/a')
BUILDS = json.load(open(os.path.join(os.path.dirname(__file__), 'versions.json')))['builds']
BUILD_IDS = [b['build'] for b in BUILDS]

errors, warnings = [], []
def err(msg): errors.append(msg)
def warn(msg): warnings.append(msg)

def parse(path):
    text = open(path, encoding='utf-8').read()
    m = re.match(r'^---\n(.*?)\n---\n(.*)$', text, re.S)
    if not m: return {}, text
    fm, key = {}, None
    for line in m.group(1).split('\n'):
        if not line.strip(): continue
        if line.startswith('  - ') and key:
            item = line[4:].strip()
            fm[key].append(item[1:-1] if len(item) >= 2 and item[0] == item[-1] == '"' else item); continue
        k, _, v = line.partition(':')
        key, v = k.strip(), v.strip()
        if v == '': fm[key] = []
        elif v.startswith('[') and v.endswith(']'):
            fm[key] = [x.strip() for x in v[1:-1].split(',') if x.strip()]
        else: fm[key] = v[1:-1] if len(v) >= 2 and v[0] == v[-1] == '"' else v
    return fm, m.group(2)

def section(body, title):
    m = re.search(r'^## ' + re.escape(title) + r'\n(.*?)(?=^## |\Z)', body, re.S | re.M)
    return m.group(1) if m else ''

# ---------- load
notes = {}
for p in glob.glob(f'{VAULT}/**/*.md', recursive=True):
    if '/_generated/' in p: continue
    notes[os.path.splitext(os.path.basename(p))[0]] = p
features, flows = {}, {}
for name, p in notes.items():
    fm, body = parse(p)
    rel = os.path.relpath(p, VAULT)
    if rel.startswith('features/'):
        fm['_body'] = body; fm['_path'] = rel; features[name] = fm
    elif rel.startswith('flows/'):
        fm['_body'] = body; fm['_path'] = rel; flows[name] = fm

areas = {n[len('area-'):] for n in notes if n.startswith('area-')}
# generated notes exist after --write, so hand-written notes may link to them
generated = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob(f'{VAULT}/_generated/*.md')} | {
    'Feature ledger', 'Build timeline', 'Performance evidence', 'Release scope', 'Finance model',
    'Dependency matrix', 'Blast radius', 'Coverage', 'Failure catalogue', 'Gaps'}

# ---------- validate features
for fid, fm in features.items():
    where = fm['_path']
    for k in REQUIRED:
        if k not in fm: err(f"{where}: missing frontmatter '{k}'")
    if fm.get('id') != fid: err(f"{where}: id '{fm.get('id')}' != filename '{fid}'")
    if fm.get('status') not in STATUSES: err(f"{where}: unknown status '{fm.get('status')}'")
    if fm.get('risk') not in RISKS: err(f"{where}: unknown risk '{fm.get('risk')}'")
    if fm.get('area') not in areas: err(f"{where}: area '{fm.get('area')}' has no area-<name>.md note")
    for p in fm.get('files', []):
        if not os.path.exists(os.path.join(REPO, p)): err(f"{where}: file not found: {p}")
    for t in fm.get('tests', []):
        path, _, name = t.partition('::')
        full = os.path.join(REPO, path)
        if not os.path.exists(full): err(f"{where}: test file not found: {path}"); continue
        if name and name not in open(full, encoding='utf-8').read(): err(f"{where}: '{name}' not found in {path}")
    for d in fm.get('depends_on', []):
        if d == fid: err(f"{where}: depends on itself")
        elif d not in features: err(f"{where}: depends_on unknown feature '{d}'")

# ---------- ledger fields (optional but kept honest)
for fid, fm in features.items():
    where = fm['_path']
    if 'introduced' not in fm or 'build' not in fm:
        warn(f"{where}: no introduced/build (add them so the Feature ledger can place it)")
    else:
        try: datetime.date.fromisoformat(fm['introduced'])
        except ValueError: err(f"{where}: introduced '{fm['introduced']}' is not YYYY-MM-DD")
        if fm['build'] not in BUILD_IDS: err(f"{where}: build '{fm['build']}' is not in versions.json")
    if 'tier' in fm and fm['tier'] not in TIERS: err(f"{where}: unknown tier '{fm['tier']}'")
    if 'release' in fm and fm['release'] not in RELEASES: err(f"{where}: unknown release '{fm['release']}'")
    if 'value' in fm and not (fm['value'].isdigit() and 1 <= int(fm['value']) <= 5): err(f"{where}: value must be 1-5")
    for k in ('cpu', 'memory', 'battery'):
        if k in fm and not str(fm[k]).lower().startswith(PERF_PREFIXES):
            err(f"{where}: {k} must start with one of {PERF_PREFIXES}")

# ---------- --fix: rewrite the derived "Used by" sections
if '--fix' in sys.argv:
    rev = defaultdict(set)
    for fid, fm in features.items():
        for d in fm.get('depends_on', []):
            if d in features: rev[d].add(fid)
    for fid, fm in features.items():
        path = os.path.join(VAULT, fm['_path'])
        text = open(path, encoding='utf-8').read()
        lines = [f"- [[{u}]] — {features[u].get('title', u)}" for u in sorted(rev[fid])] or ['- (nothing else depends on it)']
        new = re.sub(r'(^## Used by\n)(.*?)(?=^## |\Z)', lambda m: m.group(1) + '\n'.join(lines) + '\n\n', text, count=1, flags=re.S | re.M)
        if new != text: open(path, 'w', encoding='utf-8').write(new)
        fm['_body'] = parse(path)[1]

# ---------- reverse edges and "Used by"
used_by = defaultdict(set)
for fid, fm in features.items():
    for d in fm.get('depends_on', []):
        if d in features: used_by[d].add(fid)
for fid, fm in features.items():
    listed = set(re.findall(r'\[\[([^\]]+)\]\]', section(fm['_body'], 'Used by')))
    if listed != used_by[fid]:
        missing, extra = sorted(used_by[fid] - listed), sorted(listed - used_by[fid])
        err(f"{fm['_path']}: 'Used by' is stale (missing {missing}, extra {extra})")

# ---------- wikilinks
for name, p in notes.items():
    text = open(p, encoding='utf-8').read()
    text = re.sub(r'```.*?```', '', text, flags=re.S)
    for target in re.findall(r'\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]', text):
        if target not in notes and target not in generated: err(f"{os.path.relpath(p, VAULT)}: broken link [[{target}]]")

# ---------- canvases: every file node must exist
for cv in glob.glob(f'{VAULT}/**/*.canvas', recursive=True):
    try: data = json.load(open(cv))
    except ValueError: err(f"{os.path.relpath(cv, VAULT)}: not valid JSON"); continue
    for node in data.get('nodes', []):
        if node.get('type') == 'file' and not os.path.exists(os.path.join(VAULT, node.get('file', ''))):
            err(f"{os.path.relpath(cv, VAULT)}: missing file {node.get('file')}")

# ---------- flows
for fl, fm in flows.items():
    for fid in fm.get('features', []):
        if fid not in features: err(f"{fm['_path']}: unknown feature '{fid}'")

# ---------- failure points
FAIL_ROW = re.compile(r'^\|\s*([A-Z]+-[A-Za-z0-9]+)\s*\|(.*?)\|(.*?)\|\s*$')
def classify(c):
    c = c.strip().lower()
    if c.startswith('none'): return 'none'
    if c.startswith('manual'): return 'manual'
    if 'test:' in c or 'tests:' in c or c.startswith('test'): return 'test'
    return 'other'
failures = []
for fid, fm in features.items():
    for line in section(fm['_body'], 'Failure points').split('\n'):
        m = FAIL_ROW.match(line.strip())
        if m: failures.append((fid, m.group(1), m.group(2).strip(), m.group(3).strip(), classify(m.group(3))))
seen = defaultdict(list)
for fid, i, *_ in failures: seen[i].append(fid)
for i, fs in seen.items():
    if len(fs) > 1: err(f"failure id {i} used by more than one feature: {fs}")

# ---------- source coverage
try:
    tracked = subprocess.run(['git', 'ls-files'] + [r for r in SOURCE_ROOTS], cwd=REPO, capture_output=True, text=True).stdout.split()
    untracked = subprocess.run(['git', 'ls-files', '--others', '--exclude-standard'] + SOURCE_ROOTS, cwd=REPO, capture_output=True, text=True).stdout.split()
    sources = sorted({p for p in tracked + untracked if p.endswith('.swift') and os.path.exists(os.path.join(REPO, p))})
except Exception:
    sources = sorted(os.path.relpath(p, REPO) for r in SOURCE_ROOTS for p in glob.glob(f'{REPO}/{r}/**/*.swift', recursive=True))
claimed = {p for fm in features.values() for p in fm.get('files', [])} | {t.partition('::')[0] for fm in features.values() for t in fm.get('tests', [])}
unmapped = [s for s in sources if s not in claimed]
for s in unmapped: warn(f"unmapped source file: {s}")

# ---------- cycles
def find_cycles():
    graph = {f: [d for d in fm.get('depends_on', []) if d in features] for f, fm in features.items()}
    color, stack, found = {}, [], []
    def dfs(n):
        color[n] = 1; stack.append(n)
        for m in graph[n]:
            if color.get(m) == 1: found.append(stack[stack.index(m):] + [m])
            elif m not in color: dfs(m)
        stack.pop(); color[n] = 2
    for n in graph:
        if n not in color: dfs(n)
    return found
cycles = find_cycles()
for c in cycles: warn("dependency cycle: " + ' -> '.join(c))

# ---------- reports
def L(i): return f"[[{i}]]"
def closure(start):
    out, todo = set(), [start]
    while todo:
        n = todo.pop()
        for u in used_by[n]:
            if u not in out: out.add(u); todo.append(u)
    return out
RISK_W = {'low': 1, 'medium': 2, 'high': 3}

def write_reports():
    gen = os.path.join(VAULT, '_generated'); os.makedirs(gen, exist_ok=True)
    header = lambda t: f"---\ntags: [generated]\n---\n# {t}\n\n> Generated by `scripts/vault/check_vault.py --write`. Do not edit by hand.\n\n"
    order = sorted(features, key=lambda f: (features[f]['area'], f))

    # dependency list + hotspots
    out = header('Dependency matrix')
    out += '| Feature | Area | Depends on | Used by | Fan-in | Fan-out |\n|---|---|---|---|---|---|\n'
    for f in order:
        d = features[f].get('depends_on', [])
        out += f"| {L(f)} | {features[f]['area']} | {' '.join(L(x) for x in d) or '-'} | {' '.join(L(x) for x in sorted(used_by[f])) or '-'} | {len(used_by[f])} | {len(d)} |\n"
    out += '\n## Hotspots (most depended on)\n\n| Feature | Fan-in | Risk |\n|---|---|---|\n'
    for f in sorted(features, key=lambda f: -len(used_by[f]))[:12]:
        out += f"| {L(f)} | {len(used_by[f])} | {features[f]['risk']} |\n"
    out += '\n## Cycles\n\n' + ('\n'.join('- ' + ' -> '.join(L(x) for x in c) for c in cycles) if cycles else 'None.') + '\n'
    open(f'{gen}/Dependency matrix.md', 'w').write(out)

    # blast radius
    out = header('Blast radius') + 'If you change a feature, everything below it may be affected (transitive "used by"). Re-run those scenarios and manual checks.\n\n'
    out += '| Feature | Risk | Direct users | All affected (transitive) | Scenarios |\n|---|---|---|---|---|\n'
    rows = []
    for f in features:
        cl = closure(f)
        fls = [fl for fl, fm in flows.items() if f in fm.get('features', [])]
        rows.append((len(cl), f, cl, fls))
    for n, f, cl, fls in sorted(rows, reverse=True):
        out += f"| {L(f)} | {features[f]['risk']} | {len(used_by[f])} | {n}: {' '.join(L(x) for x in sorted(cl)) or '-'} | {' '.join(L(x) for x in fls) or '-'} |\n"
    open(f'{gen}/Blast radius.md', 'w').write(out)

    # coverage
    out = header('Coverage') + '| Feature | Status | Risk | Tests | Manual checks | Failure points (test / manual / none / other) |\n|---|---|---|---|---|---|\n'
    for f in order:
        fm = features[f]
        mine = [x for x in failures if x[0] == f]
        c = {k: sum(1 for x in mine if x[4] == k) for k in ('test', 'manual', 'none', 'other')}
        out += f"| {L(f)} | {fm['status']} | {fm['risk']} | {len(fm['tests'])} | {len(fm['manual_checks'])} | {len(mine)} ({c['test']} / {c['manual']} / {c['none']} / {c['other']}) |\n"
    tot = {k: sum(1 for x in failures if x[4] == k) for k in ('test', 'manual', 'none', 'other')}
    out += f"\n**Totals:** {len(features)} features, {len(failures)} failure points: {tot['test']} caught by tests, {tot['manual']} by manual checks, {tot['other']} partly, {tot['none']} not caught at all.\n"
    open(f'{gen}/Coverage.md', 'w').write(out)

    # failure catalogue
    out = header('Failure catalogue') + 'Every documented way a feature can fail. Sorted so the uncaught ones come first.\n\n'
    out += '| ID | Feature | Risk | What breaks | Caught by | Class |\n|---|---|---|---|---|---|\n'
    rank = {'none': 0, 'other': 1, 'manual': 2, 'test': 3}
    for fid, i, text, caught, cls in sorted(failures, key=lambda x: (rank[x[4]], -RISK_W[features[x[0]]['risk']], x[1])):
        out += f"| {i} | {L(fid)} | {features[fid]['risk']} | {text} | {caught} | {cls} |\n"
    open(f'{gen}/Failure catalogue.md', 'w').write(out)

    # feature ledger
    def pf(v): return str(v).replace('|', '/')
    led = sorted(features, key=lambda f: (features[f].get('introduced', '9999'), f))
    out = header('Feature ledger') + ('Every feature: when it was first committed, in which internal dev build, what release it belongs to, and what it costs the '
          'SE 2nd-gen in CPU, memory and battery. **"measured (sim)"** is the SE 2nd-gen *simulator*; nothing has been measured on the device yet, and anything '
          'marked predicted was written before measuring. "First committed" is from git (early work was committed in batches, so dates are when it landed, not '
          'when it was started). See [[P7 Optimisation checks]] for how to measure and [[Performance evidence]] for coverage.\n\n')
    out += '| Feature | Area | Status | First committed | Build | Release | Tier | Value | CPU | Memory | Battery |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
    for f in led:
        fm = features[f]
        out += (f"| {L(f)} | {fm['area']} | {fm['status']} | {fm.get('introduced', '?')} | {fm.get('build', '?')} | {fm.get('release', '?')} | {fm.get('tier', '?')} | "
                f"{fm.get('value', '?')} | {pf(fm.get('cpu', 'not measured'))} | {pf(fm.get('memory', 'not measured'))} | {pf(fm.get('battery', 'not measured'))} |\n")
    open(f'{gen}/Feature ledger.md', 'w').write(out)

    # build timeline
    out = header('Build timeline') + 'Internal dev builds (see `scripts/vault/versions.json`). These are not App Store versions: the public v1.0 is still ahead ([[P1 Stages and the MVP line]]).\n\n'
    counts = []
    for b in BUILDS:
        mine = [f for f in led if features[f].get('build') == b['build']]
        counts.append(len(mine))
        out += f"## Build {b['build']} ({b['date']}): {b['title']}\n\n" + (', '.join(L(f) for f in mine) or '(no features first committed here)') + f"\n\n{len(mine)} feature(s).\n\n"
    labels = ', '.join(f'"{b["build"]}"' for b in BUILDS)
    out += '## Features first committed per build\n\n```mermaid\nxychart-beta\n    title "Features first committed per dev build"\n    x-axis [' + labels + ']\n    y-axis "features" 0 --> ' + str(max(counts) + 2) + '\n    bar [' + ', '.join(map(str, counts)) + ']\n```\n'
    open(f'{gen}/Build timeline.md', 'w').write(out)

    # performance evidence
    out = header('Performance evidence') + 'How much of the cost of each feature has actually been measured. The goal before launch: every high-risk shipped feature has a measured CPU, memory and battery figure on the **device**, not just the simulator.\n\n'
    out += '| Metric | measured | predicted | not measured | n/a |\n|---|---|---|---|---|\n'
    def kind(v):
        v = str(v).lower()
        return next((k for k in ('measured', 'predicted', 'not measured', 'n/a') if v.startswith(k)), 'not measured')
    for k, label in (('cpu', 'CPU'), ('memory', 'Memory'), ('battery', 'Battery')):
        c = {x: 0 for x in ('measured', 'predicted', 'not measured', 'n/a')}
        for f in features: c[kind(features[f].get(k, 'not measured'))] += 1
        out += f"| {label} | {c['measured']} | {c['predicted']} | {c['not measured']} | {c['n/a']} |\n"
    dev = [f for f in order if features[f]['status'] == 'shipped' and features[f]['risk'] == 'high' and kind(features[f].get('battery', '')) in ('not measured', 'predicted')]
    out += '\n## High-risk shipped features with no measured battery figure\n' + ('\n'.join(f"- {L(f)}: {pf(features[f].get('battery', 'not measured'))}" for f in dev) or '- none') + '\n'
    out += '\n## Everything measured so far\n' + ('\n'.join(f"- {L(f)}: CPU {pf(features[f].get('cpu'))}" for f in order if kind(features[f].get('cpu', '')) == 'measured') or '- nothing') + '\n'
    open(f'{gen}/Performance evidence.md', 'w').write(out)

    # release scope (the MVP line)
    out = header('Release scope') + 'What each planned release contains, from each feature\'s `release`, `tier` and `value`. **The MVP line is the end of the v1.0 block.** See [[P1 Stages and the MVP line]].\n\n'
    out += '| Release | Features | Total value | Not yet shipped (spike, dormant, setting-only, planned) |\n|---|---|---|---|\n'
    for rel in ('v1.0', 'v1.1', 'v1.2', 'later', 'internal'):
        mine = [f for f in order if features[f].get('release') == rel]
        val = sum(int(features[f].get('value', 0)) for f in mine)
        pend = [f for f in mine if features[f]['status'] in ('spike', 'dormant', 'setting-only', 'planned')]
        out += f"| {rel} | {len(mine)} | {val} | {' '.join(L(f) for f in pend) or '-'} |\n"
    for rel in ('v1.0', 'v1.1', 'v1.2', 'later'):
        mine = sorted([f for f in features if features[f].get('release') == rel], key=lambda f: (-int(features[f].get('value', 0)), f))
        out += f"\n## {rel}\n\n| Feature | Value | Tier | Status | Risk |\n|---|---|---|---|---|\n"
        for f in mine: out += f"| {L(f)} | {features[f].get('value')} | {features[f].get('tier')} | {features[f]['status']} | {features[f]['risk']} |\n"
    open(f'{gen}/Release scope.md', 'w').write(out)

    # gaps
    out = header('Gaps')
    out += '## High-risk features with no automated tests\n' + ('\n'.join(f"- {L(f)}" for f in order if features[f]['risk'] == 'high' and not features[f]['tests']) or '- none') + '\n\n'
    out += '## Any feature with no automated tests\n' + ('\n'.join(f"- {L(f)} ({features[f]['risk']}, {features[f]['status']})" for f in order if not features[f]['tests']) or '- none') + '\n\n'
    out += '## Failure points nothing catches\n' + ('\n'.join(f"- {x[1]} {L(x[0])}: {x[2]}" for x in failures if x[4] == 'none') or '- none') + '\n\n'
    out += '## Not fully real (status is not shipped/external)\n' + ('\n'.join(f"- {L(f)}: {features[f]['status']}" for f in order if features[f]['status'] in ('setting-only', 'dormant', 'spike', 'planned')) or '- none') + '\n\n'
    out += '## Source files no feature claims\n' + ('\n'.join(f"- `{s}`" for s in unmapped) or '- none: every Swift source file is mapped') + '\n'
    open(f'{gen}/Gaps.md', 'w').write(out)

# ---------- report
for w in warnings: print('warning:', w)
for e in errors: print('ERROR:', e)
print(f"{len(features)} features, {len(flows)} flows, {len(areas)} areas, {len(failures)} failure points; "
      f"{len(errors)} errors, {len(warnings)} warnings")
if '--write' in sys.argv:
    write_reports(); subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'model_finance.py'), '--write'], capture_output=True)
    print('wrote docs/vault/_generated/')
sys.exit(1 if errors else 0)
