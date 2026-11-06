#!/usr/bin/env python3
"""TRAIN-ONLY grouped CV to choose S1's C (PREREG A6). Never reads test scores. usage: stageB_cv.py train.jsonl manifest.csv out.json"""
import sys, os, json, csv, random, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import selector as SEL, stageB_eval as E

GRID = [0.01, 0.03, 0.1, 0.3, 1.0]


def cv(tr, clusters, mk, seed, k=5):
    groups = collections.defaultdict(list)
    for c in tr: groups[clusters.get(c, c)].append(c)
    keys = sorted(groups); random.Random(seed).shuffle(keys); hit = n = 0
    for f in [keys[i::k] for i in range(k)]:
        te = {c for g in f for c in groups[g]}; sel = mk().fit({c: r for c, r in tr.items() if c not in te}, thr=0.23)
        for c in te: hit += tr[c][sel.pick(tr[c])]["dockq"] >= 0.23; n += 1
    return hit / n


def baseline(tr, key, sign):
    return sum(max(tr[c], key=lambda r: E._val(r, key, sign))["dockq"] >= 0.23 for c in tr) / len(tr)


if __name__ == "__main__":
    tr = E.load(sys.argv[1]); man = {r["complex_id"]: r for r in csv.DictReader(open(sys.argv[2]))}
    cl = {c: man[c]["receptor_cluster40"] for c in tr if c in man}; seeds = range(5)
    res = {"n_train_complexes": len(tr), "default_confidence": round(baseline(tr, "confidence_score", 1), 3),
           "random": round(sum(sum(r["dockq"] >= 0.23 for r in rs) / len(rs) for rs in tr.values()) / len(tr), 3),
           "oracle": round(sum(max(r["dockq"] for r in rs) >= 0.23 for rs in tr.values()) / len(tr), 3)}
    res["S0_C0.3_all_samples"] = round(sum(cv(tr, cl, lambda: SEL.Selector(C=0.3), s) for s in seeds) / 5, 3)
    for C in GRID: res[f"S1_C{C}"] = round(sum(cv(tr, cl, lambda C=C: SEL.Selector(C=C, mixed_only=True), s) for s in seeds) / 5, 3)
    best = max(GRID, key=lambda C: (res[f"S1_C{C}"], -C)); res["S1_chosen_C"] = best
    json.dump(res, open(sys.argv[3], "w"), indent=1); print(json.dumps(res, indent=1))
