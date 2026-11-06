#!/usr/bin/env python3
"""Objective scorer for the channel_routing benchmark. Gold = destination channel; acceptable_alts credited.
Reports overall accuracy + per-channel recall + the drug-discovery subset + a confusion summary (what the
mis-routes go to). No LLM judge.

Usage: python3 score.py <predictions.jsonl>   # preds: {"id":..., "prediction":"<channel>"}
"""
import json, sys, os, re
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CHANNELS = set(json.load(open(os.path.join(HERE, "channels.json"))).keys())


def norm(s):
    return re.sub(r"[\s-]+", "_", str(s).strip().lower())


def load_gold():
    return {r["id"]: r for r in (json.loads(l) for l in open(os.path.join(HERE, "data.jsonl")) if l.strip())}


def score(gold, preds):
    n = hit = dd_n = dd_hit = 0
    per = defaultdict(lambda: [0, 0])          # channel -> [hit, n]
    confusion = Counter()                       # (gold, pred) for misses
    empty = 0
    for i, r in gold.items():
        if i not in preds:
            continue
        n += 1
        g = {norm(r["correct_channel"])} | {norm(a) for a in r.get("acceptable_alts", [])}
        p = norm(preds[i])
        ok = p in g
        per[r["correct_channel"]][1] += 1
        per[r["correct_channel"]][0] += ok
        if r["domain"] == "drug_discovery":
            dd_n += 1; dd_hit += ok
        hit += ok
        if not preds[i] or p not in CHANNELS:
            empty += 1
        if not ok:
            confusion[(r["correct_channel"], preds[i] or "<empty>")] += 1
    out = {"scored": n, "accuracy": round(hit / n, 4) if n else None,
           "drug_discovery_accuracy": round(dd_hit / dd_n, 4) if dd_n else None, "dd_n": dd_n,
           "off_channel_or_empty": empty,
           "per_channel": {k: {"acc": round(v[0] / v[1], 3) if v[1] else None, "n": v[1]} for k, v in sorted(per.items())},
           "top_confusions": [f"{g}->{p}: {c}" for (g, p), c in confusion.most_common(8)]}
    return out


def main():
    gold = load_gold()
    preds = {r["id"]: r.get("prediction") for r in (json.loads(l) for l in open(sys.argv[1]) if l.strip())}
    print(json.dumps(score(gold, preds), indent=2))


if __name__ == "__main__":
    main()
