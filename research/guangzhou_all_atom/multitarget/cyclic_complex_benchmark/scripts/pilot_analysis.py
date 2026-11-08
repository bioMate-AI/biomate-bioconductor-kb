#!/usr/bin/env python3
"""Pilot analysis (PREREG: primary metric = top-1 success DockQ >= 0.23 of the SELECTED sample; stop rule: oracle - default < 10 pp => NO-HEADROOM).

usage: pilot_analysis.py scores.jsonl manifest.csv out.json
Selectors compared per complex: default (Boltz confidence_score), iptm, random (expected value), oracle (best of N, GT-aware upper bound), ring-validity-filtered default.
CIs: bootstrap over RECEPTOR CLUSTERS (complexes of one receptor are not independent). Also reports mean DockQ and the per-sample ipTM-vs-DockQ AUROC (pooled and within-complex).
"""
import csv, json, sys, random, math, collections


def load(path):
    rows = [json.loads(l) for l in open(path)]
    by = collections.defaultdict(list)
    for r in rows:
        by[r["complex_id"]].append(r)
    return by


def dq(r):
    for k in ("DockQ", "dockq"):
        if r.get(k) is not None and not (isinstance(r[k], float) and math.isnan(r[k])):
            return float(r[k])
    return None


def per_complex(rs, thr):
    rs = [r for r in rs if dq(r) is not None]
    if not rs:
        return None
    d = [dq(r) for r in rs]
    pick = lambda key: max(rs, key=lambda r: (r.get(key) if r.get(key) is not None else -1e9))
    valid = [r for r in rs if r.get("ring_valid")] or rs
    return dict(n=len(rs),
                default=dq(pick("confidence_score")), iptm=dq(pick("iptm")),
                default_ringvalid=dq(max(valid, key=lambda r: r.get("confidence_score") or -1e9)),
                oracle=max(d), random_mean=sum(d) / len(d), random_succ=sum(x >= thr for x in d) / len(d),
                ring_valid_frac=sum(1 for r in rs if r.get("ring_valid")) / len(rs))


def auroc(pos_neg):
    pos = [s for s, y in pos_neg if y]; neg = [s for s, y in pos_neg if not y]
    if not pos or not neg:
        return None
    w = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return w / (len(pos) * len(neg))


def summarize(pc, thr, clusters, B=4000, seed=1):
    ids = sorted(pc)
    def stats(sub):
        f = lambda k: sum(pc[c][k] >= thr for c in sub) / len(sub)
        return dict(default=f("default"), iptm=f("iptm"), default_ringvalid=f("default_ringvalid"), oracle=f("oracle"),
                    random=sum(pc[c]["random_succ"] for c in sub) / len(sub))
    point = stats(ids)
    by_cl = collections.defaultdict(list)
    for c in ids:
        by_cl[clusters.get(c, c)].append(c)
    keys = list(by_cl); rng = random.Random(seed); boots = []
    for _ in range(B):
        sub = [c for k in (rng.choice(keys) for _ in keys) for c in by_cl[k]]
        s = stats(sub); s["gap_oracle_default"] = s["oracle"] - s["default"]; s["gain_ringvalid"] = s["default_ringvalid"] - s["default"]; boots.append(s)
    ci = lambda k: [sorted(b[k] for b in boots)[int(0.025 * B)], sorted(b[k] for b in boots)[int(0.975 * B)]]
    out = {k: dict(value=round(v, 3), ci95=[round(x, 3) for x in ci(k)]) for k, v in point.items()}
    out["gap_oracle_default"] = dict(value=round(point["oracle"] - point["default"], 3), ci95=[round(x, 3) for x in ci("gap_oracle_default")])
    out["gain_ringvalid_filter"] = dict(value=round(point["default_ringvalid"] - point["default"], 3), ci95=[round(x, 3) for x in ci("gain_ringvalid")])
    out["n_complexes"] = len(ids); out["n_clusters"] = len(keys)
    return out


if __name__ == "__main__":
    scores, manifest, outp = sys.argv[1:4]
    by = load(scores)
    man = {r["complex_id"]: r for r in csv.DictReader(open(manifest))}
    clusters = {c: man[c]["receptor_cluster40"] for c in by if c in man}
    res = {}
    for thr in (0.23, 0.49):
        pc = {c: p for c, rs in by.items() if (p := per_complex(rs, thr))}
        res[f"all_thr{thr}"] = summarize(pc, thr, clusters)
        for tier, flag in (("strict", "runnable_strict"), ("noncanonical", None)):
            sub = {c: p for c, p in pc.items() if c in man and ((man[c][flag] == "1") if flag else (man[c]["runnable_strict"] != "1"))}   # manifest flags are "1"/"0"
            if len(sub) >= 3:
                res[f"{tier}_thr{thr}"] = summarize(sub, thr, clusters)
    # ipTM calibration
    pooled, within = [], []
    for c, rs in by.items():
        rs = [r for r in rs if dq(r) is not None and r.get("iptm") is not None]
        pooled += [(r["iptm"], dq(r) >= 0.23) for r in rs]
        ys = [dq(r) >= 0.23 for r in rs]
        if 0 < sum(ys) < len(ys):
            within.append(auroc([(r["iptm"], y) for r, y in zip(rs, ys)]))
    res["iptm_auroc_pooled"] = round(auroc(pooled), 3) if auroc(pooled) is not None else None
    res["iptm_auroc_within_complex_mean"] = round(sum(within) / len(within), 3) if within else None
    res["n_complexes_with_mixed_outcomes"] = len(within)
    res["ring_valid_fraction_overall"] = round(sum(1 for rs in by.values() for r in rs if r.get("ring_valid")) / sum(len(rs) for rs in by.values()), 3)
    res["per_complex"] = {c: {k: (round(v, 3) if isinstance(v, float) else v) for k, v in (per_complex(rs, 0.23) or {}).items()} for c, rs in sorted(by.items())}
    json.dump(res, open(outp, "w"), indent=1)
    print(json.dumps({k: v for k, v in res.items() if k != "per_complex"}, indent=1))
