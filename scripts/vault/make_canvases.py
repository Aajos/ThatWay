#!/usr/bin/env python3
"""Regenerates the two Obsidian canvases in docs/vault/process/ (they are JSON; this keeps them tidy and the file links valid).

  python3 scripts/vault/make_canvases.py

  Development procedure.canvas   the stages S0..S8 as a flow, with the playbooks and money notes hanging off the stage that uses them
  Operation flow.canvas          launch to arrival: the flows, in the order a user meets them, with the features each leans on
check_vault.py verifies every file node points at a note that exists.
"""
import json, os
VAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'docs', 'vault')
_id = [0]
def nid(prefix='n'):
    _id[0] += 1; return f'{prefix}{_id[0]:03d}'

class Canvas:
    def __init__(self): self.nodes, self.edges = [], []
    def text(self, text, x, y, w=300, h=170, color=None):
        n = {'id': nid(), 'type': 'text', 'text': text, 'x': x, 'y': y, 'width': w, 'height': h}
        if color: n['color'] = color
        self.nodes.append(n); return n['id']
    def file(self, path, x, y, w=300, h=120, color=None):
        n = {'id': nid(), 'type': 'file', 'file': path, 'x': x, 'y': y, 'width': w, 'height': h}
        if color: n['color'] = color
        self.nodes.append(n); return n['id']
    def edge(self, a, b, label=None, fs='right', ts='left'):
        e = {'id': nid('e'), 'fromNode': a, 'fromSide': fs, 'toNode': b, 'toSide': ts}
        if label: e['label'] = label
        self.edges.append(e)
    def save(self, name):
        path = os.path.join(VAULT, 'process', name)
        json.dump({'nodes': self.nodes, 'edges': self.edges}, open(path, 'w'), indent=2)

# colours: 1 red, 2 orange, 3 yellow, 4 green, 5 cyan, 6 purple
def procedure():
    c = Canvas()
    stages = [
        ('S0 Prototype', 'Sep 2026\nDONE\nScreens, real location, compass, OSRM', '4'),
        ('S1 Core build', 'to 15 Nov 2026\nNOW\nv1.0 features, working sign-up and friends, polyline on 3 routes', '2'),
        ('S2 Hardening', 'to 14 Nov 2026\nPower and memory baselines, accessibility pass', '2'),
        ('S3 Internal TestFlight', '1 Dec 2026\nYou plus 2 friends: a full drive and walk, no crash', '3'),
        ('S4 External beta', 'to 10 Jan 2027\n20 to 50 testers, App Review dry run', '3'),
        ('S5 Launch v1.0 (MVP)', '15 Jan 2027\nFree: core navigation and basic friends', '1'),
        ('S6 v1.1 paid', 'to 30 Apr 2027\nProximity (UWB), tracking, purchase and restore', '5'),
        ('S7 v1.2 looks', 'to 30 Jun 2027\nSkins and themes as data', '5'),
        ('S8 Growth and review', 'to 1 Oct 2027\nUsers, retention, runway decision', '6'),
    ]
    ids = []
    for i, (t, body, col) in enumerate(stages):
        ids.append(c.text(f'## {t}\n{body}', i * 360, 0, 320, 190, col))
    for a, b in zip(ids, ids[1:]): c.edge(a, b)
    def hang(note, x, y, targets, color=None, w=300):
        n = c.file(f'process/{note}.md', x, y, w, 110, color)
        for t in targets: c.edge(ids[t], n, fs='bottom', ts='top')
        return n
    hang('P1 Stages and the MVP line', 0, 330, [0, 1, 5, 8])
    hang('P9 How the app works', 360, 330, [1])
    hang('P10 Backend and proximity runbook', 720, 330, [1, 6], '2')
    hang('P7 Optimisation checks', 1080, 330, [2])
    hang('P5 Accessibility testing', 1440, 330, [2, 3])
    hang('P6 Live testing', 1800, 330, [3, 4])
    hang('P8 Before you push or commit', 2160, 330, [3, 4, 5], '1')
    hang('P2 Feature value and scope', 360, 560, [1, 5])
    hang('P3 Costs', 1080, 560, [3, 5])
    hang('P4 Revenue and growth', 2160, 560, [6, 8])
    c.file('process/P0 Product development map.md', 1080, -230, 300, 110, '6')
    c.save('Development procedure.canvas')

def operation():
    c = Canvas()
    steps = [
        ('flows/flow-first-launch.md', 'Open the app'),
        ('flows/flow-start-guidance.md', 'Search, pick, start'),
        ('flows/flow-guidance-refresh.md', 'Every location fix'),
        ('flows/flow-off-route.md', 'Wrong turn'),
        ('flows/flow-mode-change.md', 'Change mode mid-trip'),
        ('flows/flow-offline-midroute.md', 'Network drops'),
        ('flows/flow-phone-locked.md', 'Screen locks'),
        ('flows/flow-compass-wrong.md', 'Compass lies'),
        ('flows/flow-arrival.md', 'Arrive'),
        ('flows/flow-relaunch-restore.md', 'Relaunch mid-trip'),
    ]
    ids = []
    for i, (f, _) in enumerate(steps):
        x = (i % 5) * 360; y = (i // 5) * 360
        ids.append(c.file(f, x, y, 320, 140, '6'))
    for a, b in zip(ids[:5], ids[1:5]): c.edge(a, b)
    for a, b in zip(ids[5:], ids[6:]): c.edge(a, b)
    c.edge(ids[4], ids[5], fs='bottom', ts='top')
    feats = [('features/guidance-mode.md', 1, '1'), ('features/routing-governor.md', 1, '1'), ('features/route-progress.md', 2, '1'),
             ('features/off-route-reroute.md', 3, '1'), ('features/compass-health.md', 7, '2'), ('features/background-guidance.md', 6, '1'),
             ('features/arrival.md', 8, '2'), ('features/auth.md', 0, '1')]
    for k, (f, step, col) in enumerate(feats):
        n = c.file(f, k * 360, 760, 320, 110, col)
        c.edge(ids[step], n, fs='bottom', ts='top')
    c.text('## Reading this\nPurple = situations (flows). Red = high-risk features they lean on. Orange = medium. Open a flow to see its seams and what catches each failure.', 0, -230, 720, 140)
    c.file('process/P9 How the app works.md', 1080, -230, 320, 110, '6')
    c.save('Operation flow.canvas')

if __name__ == '__main__':
    procedure(); operation(); print('wrote 2 canvases')
