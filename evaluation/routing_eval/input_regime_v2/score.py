#!/usr/bin/env python3
"""Score input_regime_v2 runs (route_eval.py rows) against acceptable.json (fixed before any run).
A row is correct when the card's slug equals the slug of an acceptable workflow; no card = incorrect.
Prints overall, per group, and per query (k/reps). Usage: score.py <rows.jsonl> [...]"""
import collections, json, re, sys
from pathlib import Path
HERE = Path(__file__).parent
slug = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())
ACC = {k: {slug(x) for x in v} for k, v in json.load(open(HERE / "acceptable.json"))["acceptable"].items()}
Q = {i: q for i, q in enumerate(json.load(open(HERE / "queries.json")))}
for f in sys.argv[1:]:
    rows = [json.loads(l) for l in open(f) if l.strip()]
    per_q, per_g = collections.defaultdict(list), collections.defaultdict(list)
    for r in rows:
        q = Q[r["idx"]]; ok = slug(r.get("wf")) in ACC[q["id"]]
        per_q[q["id"]].append(ok); per_g[q["group"]].append(ok)
    tot = [x for v in per_q.values() for x in v]
    print(f"{f}: {sum(tot)}/{len(tot)} = {sum(tot)/max(1,len(tot)):.3f}")
    print("  groups: " + ", ".join(f"{g} {sum(v)}/{len(v)}" for g, v in sorted(per_g.items())))
    print("  misses: " + ", ".join(f"{k} {sum(v)}/{len(v)}" for k, v in sorted(per_q.items()) if not all(v)))
