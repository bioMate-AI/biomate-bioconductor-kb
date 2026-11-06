#!/usr/bin/env python3
"""Aggregate Part B. usage: aggregate_B.py RESDIR_B OUT.json. Bootstrap over held-out sources (2000)."""
import glob, json, sys, collections
import numpy as np
from scipy.stats import spearmanr
RES, OUT = sys.argv[1:3]; rng = np.random.default_rng(0)
rows = [json.load(open(f)) for f in glob.glob(f"{RES}/*__*.json")]
by = collections.defaultdict(list)
for r in rows: by[r["world"]].append(r)
def bs_median(v, B=2000):
    v = np.array(v, float); v = v[~np.isnan(v)]
    if len(v) == 0: return None
    m = [np.median(v[rng.integers(0, len(v), len(v))]) for _ in range(B)]
    return dict(median=float(np.median(v)), mean=float(v.mean()), ci95=[float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))], n_sources=int(len(v)))
out = {"n_files": len(rows)}
for w, rs in by.items():
    o = {}
    o["raw_within_spearman"] = bs_median([r["variants"]["raw"]["within"] for r in rs])
    if w == "real": o["z_within_spearman_reference"] = bs_median([r["variants"]["z"]["within"] for r in rs]); o["z_minus_raw"] = bs_median([r["variants"]["z"]["within"] - r["variants"]["raw"]["within"] for r in rs])
    for k in (3, 5, 10):
        g = [r["variants"][f"cal_k{k}"]["gain_mean"] for r in rs if f"cal_k{k}" in r["variants"] and r["variants"][f"cal_k{k}"]["gain_mean"] is not None]
        ns = [r["variants"][f"cal_k{k}"]["n_cal_sources"] for r in rs if f"cal_k{k}" in r["variants"]]
        if g or f"cal_k{k}" in (rs[0]["variants"] if rs else {}):
            o[f"gain_cal_k{k}"] = bs_median(g) if g else None; o[f"n_calibrated_training_sources_k{k}"] = (int(np.median(ns)) if ns else 0)
            rec = [r["variants"][f"cal_k{k}"]["offset_recovery_r"] for r in rs if f"cal_k{k}" in r["variants"] and r["variants"][f"cal_k{k}"].get("offset_recovery_r") is not None]
            if rec: o[f"offset_recovery_r_k{k}"] = float(np.nanmean(rec))
            # share of held-out sources whose gain > 0
            if g: o[f"frac_gain_positive_k{k}"] = float(np.mean(np.array(g) > 0))
    # pooled practical metric (held-out sources with >= k anchors): cal+b_h vs raw
    for k in (3, 5):
        ys, cals, raws = [], [], []
        for f in glob.glob(f"{RES}/pooled_{w}_*_k{k}.npz"):
            z = np.load(f); ys.append(z["y"]); cals.append(z["cal"].mean(0)); raws.append(z["raw"].mean(0))
        if ys:
            y = np.concatenate(ys); c = np.concatenate(cals); r_ = np.concatenate(raws)
            o[f"pooled_spearman_k{k}"] = dict(cal_plus_offset=float(spearmanr(c, y)[0]), raw=float(spearmanr(r_, y)[0]), n=int(len(y)), n_sources=len(ys))
    out[w] = o
# pre-registered verdicts
def get(w, k): 
    return out.get(w, {}).get(f"gain_cal_k{k}")
v = {}
g5 = get("real", 5); v["kill_criterion_real_k5_median_gain_lt_0.03"] = (None if not g5 else bool(g5["median"] < 0.03))
pf = get("planted_full", 5); pp = get("planted", 5); nn = get("null", 5)
v["planted_offset_recovery_r_gt_0.9_k5"] = {w: out.get(w, {}).get("offset_recovery_r_k5") for w in ("planted", "planted_full")}
v["planted_gain_gt_0.1_k5"] = {"planted": (pp and pp["median"]), "planted_full": (pf and pf["median"])}
v["null_gain_CI_includes_0"] = (None if not nn else bool(nn["ci95"][0] <= 0 <= nn["ci95"][1]))
out["verdicts"] = v
json.dump(out, open(OUT, "w"), indent=1); print(json.dumps(out, indent=1)[:5000])
