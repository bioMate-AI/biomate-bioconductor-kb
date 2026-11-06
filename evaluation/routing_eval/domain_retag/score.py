#!/usr/bin/env python3
"""Score the domain-retag routing A/B. Criterion fixed BEFORE either arm ran (2026-11-05):
a row is correct when the routed card name matches the payload's `mod` regex (case-insensitive).
`retag` rows target workflows whose catalog domain was wrong; `ctl` rows must not regress.
Revision (2026-11-05, after the before-arm, BEFORE any after-arm data): the loose regex counted
raw-spectra pipelines (nf-core/proteomicslfq) as correct for processed protein tables — the very
failure the user reported. Rows with a `strict` regex are also scored against it (`retag_strict`):
the card must be a workflow that takes processed tables.
Usage: score.py <rows.jsonl> [...]"""
import json, re, sys, collections
pl = {p["idx"]: p for p in json.load(open(__file__.replace("score.py", "payloads.json")))}
for f in sys.argv[1:]:
    c = collections.defaultdict(lambda: [0, 0])
    for l in open(f):
        r = json.loads(l); p = pl[r["idx"]]
        ok = bool(r.get("wf")) and bool(re.search(p["mod"], r["wf"], re.I))
        c[p["track"]][0] += ok; c[p["track"]][1] += 1
        if p.get("strict"):
            c["retag_strict"][0] += bool(r.get("wf")) and bool(re.search(p["strict"], r["wf"].strip(), re.I))
            c["retag_strict"][1] += 1
    print(f, {k: f"{a}/{b}" for k, (a, b) in c.items()})
