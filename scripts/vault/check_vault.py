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
Warnings (printed, do not fail): Swift source files that no feature claims ("unmapped"), dependency cycles.
Numbers and structure only: the vault holds no coordinates, secrets or personal data.
"""
import os, re, sys, subprocess, glob
from collections import defaultdict

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
VAULT = os.path.join(REPO, 'docs', 'vault')
STATUSES = {'shipped', 'spike', 'dormant', 'setting-only', 'external', 'planned'}
RISKS = {'low', 'medium', 'high'}
REQUIRED = ['id', 'title', 'area', 'status', 'risk', 'files', 'tests', 'manual_checks', 'depends_on']
SOURCE_ROOTS = ['ThatWay', 'ThatWayCore/Sources', 'ThatWayWatch']

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
            fm[key].append(line[4:].strip()); continue
        k, _, v = line.partition(':')
        key, v = k.strip(), v.strip()
        if v == '': fm[key] = []
        elif v.startswith('[') and v.endswith(']'):
            fm[key] = [x.strip() for x in v[1:-1].split(',') if x.strip()]
        else: fm[key] = v
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
        if target not in notes: err(f"{os.path.relpath(p, VAULT)}: broken link [[{target}]]")

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
    write_reports(); print('wrote docs/vault/_generated/')
sys.exit(1 if errors else 0)
