#!/usr/bin/env python3
"""Stage B ONE-SHOT evaluation (PREREG amendments A2/A3). usage: stageB_eval.py train_scores.jsonl test_scores.jsonl manifest.csv out.json

Fits selector S on TRAIN only, evaluates ONCE on TEST. Nothing is tuned after seeing TEST.
Baselines (all pre-registered, directions fixed a priori): default (confidence_score, high), ipTM (high), pTM (high), interface pLDDT (high), ring strain (low), clash count (low).
Reference rows (not selectors): random-sample expectation and ORACLE (best of N, uses ground truth).
Claim: S is 'best' only if its top-1 success beats the STRONGEST baseline (chosen on TEST = conservative) with a paired receptor-cluster bootstrap 95 % CI of the
difference excluding 0 — on ALL test complexes AND on the novel-receptor subset (receptor cluster absent from TRAIN). Reported at DockQ >= 0.23 (primary) and >= 0.49.
"""
import csv, json, math, random, sys, collections
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import selector as SEL

BASELINES = {"default": ("confidence_score", +1), "iptm": ("iptm", +1), "ptm": ("ptm", +1), "if_plddt": ("if_plddt", +1),
             "ring_strain": ("ring_strain", -1), "clash_count": ("clash_count", -1)}


def load(path):
    by = collections.defaultdict(list)
    for l in open(path):
        r = json.loads(l)
        if r.get("dockq") is not None and not (isinstance(r["dockq"], float) and math.isnan(r["dockq"])):
            by[r["complex_id"]].append(r)
    return {c: rs for c, rs in by.items() if len(rs) >= 3}


def _val(r, k, sign):
    v = r.get(k)
    return sign * v if isinstance(v, (int, float)) and not isinstance(v, bool) and not math.isnan(v) else -1e18


def picks(rows, selector):
    """dockq of the sample chosen by each method for one complex."""
    out = {name: max(rows, key=lambda r: _val(r, k, s))["dockq"] for name, (k, s) in BASELINES.items()}
    out["S"] = rows[selector.pick(rows)]["dockq"]
    out["oracle"] = max(r["dockq"] for r in rows)
    out["_random"] = [r["dockq"] for r in rows]
    return out


def success(per, thr, method, ids):
    if method == "random":
        return sum(sum(d >= thr for d in per[c]["_random"]) / len(per[c]["_random"]) for c in ids) / len(ids)
    return sum(per[c][method] >= thr for c in ids) / len(ids)


def evaluate(per, thr, clusters, ids, B=4000, seed=7):
    methods = list(BASELINES) + ["S", "oracle", "random"]
    point = {m: success(per, thr, m, ids) for m in methods}
    strongest = max(list(BASELINES), key=lambda m: point[m])
    by = collections.defaultdict(list)
    for c in ids: by[clusters.get(c, c)].append(c)
    keys = list(by); rng = random.Random(seed); diffs = []; gaps = []
    for _ in range(B):
        sub = [c for k in (rng.choice(keys) for _ in keys) for c in by[k]]
        s = {m: success(per, thr, m, sub) for m in ("S", strongest, "oracle", "default", "random")}
        diffs.append(s["S"] - s[strongest]); gaps.append(s["oracle"] - s["default"])
    q = lambda x: [round(sorted(x)[int(0.025 * len(x))], 3), round(sorted(x)[int(0.975 * len(x)) - 1], 3)]
    return dict(n_complexes=len(ids), n_clusters=len(keys), success={m: round(v, 3) for m, v in point.items()}, strongest_baseline=strongest,
                S_minus_strongest=dict(value=round(point["S"] - point[strongest], 3), ci95=q(diffs)),
                S_minus_default=dict(value=round(point["S"] - point["default"], 3)),
                oracle_minus_default=dict(value=round(point["oracle"] - point["default"], 3), ci95=q(gaps)),
                verdict_S_best=bool(q(diffs)[0] > 0))


def run(train_path, test_path, manifest, out_path, mixed_only=False, C=0.3, feats=None):
    train, test = load(train_path), load(test_path)
    man = {r["complex_id"]: r for r in csv.DictReader(open(manifest))}
    clusters = {c: man[c]["receptor_cluster40"] for c in list(train) + list(test) if c in man}
    tr_cl = {clusters[c] for c in train if c in clusters}
    sel = SEL.Selector(C=C, mixed_only=mixed_only, feats=feats or SEL.FEATURES).fit(train, thr=0.23)
    per = {c: picks(rs, sel) for c, rs in test.items()}
    ids_all = sorted(per); ids_novel = [c for c in ids_all if clusters.get(c) not in tr_cl]
    res = dict(variant=("S2" if feats else "S1") if mixed_only else "S0", C=C, n_train_complexes=len(train), n_train_clusters=len(tr_cl), selector_coef_top=dict(list(sel.coef().items())[:8]), selector_trivial=sel.trivial)
    for thr in (0.23, 0.49):
        res[f"all_thr{thr}"] = evaluate(per, thr, clusters, ids_all)
        if len(ids_novel) >= 5: res[f"novel_receptor_thr{thr}"] = evaluate(per, thr, clusters, ids_novel)
        for tier, keep in (("strict", [c for c in ids_all if man[c]["runnable_strict"] == "1"]), ("noncanonical", [c for c in ids_all if man[c]["runnable_strict"] != "1"])):
            if len(keep) >= 5: res[f"{tier}_thr{thr}"] = evaluate(per, thr, clusters, keep)
    res["CLAIM_S_best_all_and_novel_at_0.23"] = bool(res["all_thr0.23"]["verdict_S_best"] and res.get("novel_receptor_thr0.23", {}).get("verdict_S_best", False))
    json.dump(res, open(out_path, "w"), indent=1)
    return res


if __name__ == "__main__":
    a = sys.argv[1:]
    # usage: stageB_eval.py train test manifest out [S0|S1 [C]]   (S1 = mixed_only, PREREG A6; C comes from results/stageB_cv_train.json, never from test)
    var = a[4] if len(a) > 4 else "S0"
    if var == "S2":          # PREREG A8 outcome: 3 pLDDT features, C=1.0, mixed complexes only
        from stageB_cv_features import SETS
        r = run(*a[:4], mixed_only=True, C=1.0, feats=SETS["F_pl"])
    else:
        r = run(*a[:4], mixed_only=(var == "S1"), C=float(a[5]) if len(a) > 5 else 0.3)
    print(json.dumps({k: v for k, v in r.items() if k.startswith(("CLAIM", "n_train", "all_thr0.23", "novel_receptor_thr0.23"))}, indent=1))
