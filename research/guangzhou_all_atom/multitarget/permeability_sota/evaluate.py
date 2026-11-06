"""Pooled out-of-fold evaluation with cluster-bootstrap CIs, paired differences, claim rule, per-assay/source tables, calibration, error analysis.
Usage: evaluate.py  -> results/results.json + results/results_table.md"""
import glob, json, numpy as np, pandas as pd
from common import *
import cv
c, f = cv.load(); NB = 1000
BASE = ["M1", "M2", "M3", "M5", "G1"]; OURS = ["M4", "G2", "G3", "C1", "E1"]
P = {}
for fn in glob.glob(os.path.join(HERE, "results/preds/*.csv")):
    n = os.path.basename(fn)[:-4]
    if n.startswith("LC_") or n.startswith("P0_") or n.endswith("_sub"): continue
    P[n] = pd.read_csv(fn)
def key(d): return d.split.astype(str) + "|" + d.fold.astype(str) + "|" + d.row.astype(str)
for n in P: P[n]["k"] = key(P[n]); P[n] = P[n].drop_duplicates("k").set_index("k")
if all(m in P for m in ["M1", "M4", "G2", "G3"]):
    ks = P["M1"].index
    for m in ["M4", "G2", "G3"]: ks = ks.intersection(P[m].index)
    P["E1"] = P["M1"].loc[ks, ["split", "fold", "row"]].copy(); P["E1"]["pred"] = np.mean([P[m].loc[ks, "pred"].values for m in ["M1", "M4", "G2", "G3"]], 0)
GROUP = {"S0": lambda d: c.pid.values[d.row.values], "S1": lambda d: c.scaf.values[d.row.values], "S2": lambda d: f.s2_cluster.values[d.row.values], "S3": lambda d: c.scaf.values[d.row.values]}
def sub(n, sp, assay=None):
    d = P[n][P[n].split == sp]
    if assay: d = d[c.assay.values[d.row.values] == assay]
    return d
res = {"models": sorted(P), "tables": {}, "claim": {}}
lines = ["| split | assay | model | R2 [95% CI] | RMSE [95% CI] | Spearman [95% CI] | n |", "|---|---|---|---|---|---|---|"]
for sp in ["S0", "S1", "S2", "S3"]:
    for assay in [None, "PAMPA", "Caco2"]:
        names = [n for n in P if len(sub(n, sp, assay))]
        if not names: continue
        # common rows across models for a fair, paired comparison
        common = None
        for n in names:
            kk = set(zip(sub(n, sp, assay).fold, sub(n, sp, assay).row)); common = kk if common is None else common & kk
        if not common: continue
        idx = sorted(common); d0 = P[names[0]][P[names[0]].split == sp].reset_index(); 
        def aligned(n):
            d = sub(n, sp, assay); d = d.set_index([d.fold, d.row]); d = d[~d.index.duplicated()]; return d.loc[idx, "pred"].values
        rows = np.array([r for _, r in idx]); y = c.y.values[rows]; g = GROUP[sp](pd.DataFrame({"row": rows}))
        pr = {n: aligned(n) for n in names}
        ci = cluster_bootstrap(y, pr, g, NB)
        tab = {n: {m: ci[n][m] for m in ci[n]} | {"n": len(y)} for n in names}
        res["tables"][f"{sp}|{assay or 'ALL'}"] = tab
        for n in names:
            t = tab[n]; lines.append(f"| {sp} | {assay or 'ALL'} | {n} | {t['r2'][0]:.3f} [{t['r2'][1]:.3f}, {t['r2'][2]:.3f}] | {t['rmse'][0]:.3f} [{t['rmse'][1]:.3f}, {t['rmse'][2]:.3f}] | {t['spearman'][0]:.3f} [{t['spearman'][1]:.3f}, {t['spearman'][2]:.3f}] | {len(y)} |")
        if assay is None and "E1" in pr:
            bn = [b for b in BASE if b in pr]
            if bn:
                best = max(bn, key=lambda b: tab[b]["r2"][0]); dd = paired_diff(y, pr["E1"], pr[best], g, "r2", NB)
                res["claim"][sp] = {"strongest_baseline": best, "baseline_r2": tab[best]["r2"][0], "E1_r2": tab["E1"]["r2"][0], "paired_diff_r2": dd, "excludes_zero_positive": bool(dd[1] > 0)}
        if sp == "S3" and assay is None:
            per = {}
            for src_i in sorted(set(f.s3_fold[rows])):
                m = f.s3_fold.values[rows] == src_i
                per[int(src_i)] = {n: metrics(y[m], pr[n][m]) for n in names}
            res["S3_per_source"] = per
            res["S3_per_source_names"] = {str(i): s for i, s in zip(range(8), c.source[c.source.isin(c.source.value_counts()[lambda s: s >= 100].index)].value_counts().index)}
ok = [res["claim"].get(s, {}).get("excludes_zero_positive") for s in ["S1", "S2", "S3"]]
res["verdict_rule_all_three"] = bool(all(ok)) if all(v is not None for v in ok) else None
# ---- error analysis + calibration on E1 (or best available)
ref = "E1" if "E1" in P else None
if ref:
    d = P[ref].copy(); d["y"] = c.y.values[d.row.values]; d["err"] = d.pred - d.y
    d["ring"] = c.ring_res.values[d.row.values]; d["nme"] = np.clip(c.n_nme_smiles.values[d.row.values], 0, 6); d["assay"] = c.assay.values[d.row.values]
    ea = {}
    for sp in ["S1", "S2", "S3"]:
        dd = d[d.split == sp]
        ea[sp] = {"by_ring_res": {int(k): {"n": int(len(g)), "rmse": rmse(g.y, g.pred)} for k, g in dd.groupby("ring") if len(g) >= 30},
                  "by_nme": {int(k): {"n": int(len(g)), "rmse": rmse(g.y, g.pred)} for k, g in dd.groupby("nme") if len(g) >= 30},
                  "by_assay": {k: {"n": int(len(g)), "rmse": rmse(g.y, g.pred)} for k, g in dd.groupby("assay") if len(g) >= 30}}
    res["error_analysis_E1"] = ea
    members = [m for m in ["M1", "M4", "G2", "G3"] if m in P]
    if len(members) >= 3:
        sd_ = {}
        for sp in ["S0", "S1", "S2", "S3"]:
            ks = d[d.split == sp].index; M = np.stack([P[m].loc[P[m].index.intersection(ks), "pred"].reindex(ks).values for m in members], 1)
            sd_[sp] = (ks, np.nanstd(M, 1))
        # scale k calibrated on S0 only (90% two-sided normal => 1.645*k*sigma), then applied OOD
        ks0, s0 = sd_["S0"]; e0 = np.abs(d.loc[ks0, "err"].values); k = np.quantile(e0 / (s0 + 1e-6), 0.9) / 1.645
        cal = {"scale_k_from_S0": float(k)}
        for sp, (ks, s) in sd_.items():
            e = np.abs(d.loc[ks, "err"].values)
            cal[sp] = {"coverage90_uncalibrated": float(np.mean(e <= 1.645 * s)), "coverage90_S0_calibrated": float(np.mean(e <= 1.645 * k * s)),
                       "spearman_abs_err_vs_sigma": spearman(e, s), "mean_sigma": float(s.mean()), "n": int(len(e))}
        res["calibration_E1_member_spread"] = cal
json.dump(res, open(os.path.join(HERE, "results/results.json"), "w"), indent=1, default=float)
open(os.path.join(HERE, "results/results_table.md"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines)); print(json.dumps(res["claim"], indent=1, default=float)); print(res.get("calibration_E1_member_spread"))
