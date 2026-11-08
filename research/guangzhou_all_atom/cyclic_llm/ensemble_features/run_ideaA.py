#!/usr/bin/env python3
"""Idea A pilot (docs/20261031_ENSEMBLE_FEATURES_PREREG.md): do simulated two-solvent ensemble features (CycPeptMPDB-4D) help
under leave-one-lab-out?  usage: IDEA_A_DATA=<dir with CycPeptMPDB-4D.csv> python3 run_ideaA.py OUT.json [--controls-only]
Everything here follows the pre-registration; nothing is tuned.  Controls run FIRST; the real contrast is reported only if they pass."""
import os, sys, json, hashlib, argparse, warnings
import numpy as np, pandas as pd
warnings.filterwarnings("ignore")
HERE = os.path.dirname(os.path.abspath(__file__))
STRAT = os.path.join(HERE, "..", "stratification")
sys.path.insert(0, STRAT)
import common as C
from sklearn.ensemble import HistGradientBoostingRegressor as H
from sklearn.model_selection import GroupKFold
from scipy.stats import spearmanr

MD5_4D = "e4b957982bd572aba5029963804e0524"
E_RAW = ["Water_avgGR", "Hexane_avgGR", "Water_avgRMSD_All", "Water_avgRMSD_BackBone", "Hexane_avgRMSD_All", "Hexane_avgRMSD_BackBone",
         "Water_Desolvation_Free_Energy", "Water_3D_SASA", "Water_3D_NPSA", "Water_3D_PSA", "Hexane_3D_SASA", "Hexane_3D_NPSA", "Hexane_3D_PSA"]
MIN_LAB = 40


def mk(): return H(max_iter=150, learning_rate=0.1, random_state=0)       # the committed stratification settings; not tuned


def load(data_dir):
    p = os.path.join(data_dir, "CycPeptMPDB-4D.csv")
    md5 = hashlib.md5(open(p, "rb").read()).hexdigest()
    assert md5 == MD5_4D, f"4D csv checksum mismatch: {md5}"
    f4 = pd.read_csv(p).set_index("CycPeptMPDB_ID")
    d = C.load_labelled()
    sub = d.loc[d.index.isin(f4.index)].copy()
    f4 = f4.loc[sub.index]
    assert (f4.Source.values == sub.Source.values).all(), "source labels disagree with the corrected annotation"
    E = f4[E_RAW].astype(float).copy()
    E["dPSA"] = E.Water_3D_PSA - E.Hexane_3D_PSA
    E["dPSA_frac"] = E.Water_3D_PSA / E.Water_3D_SASA - E.Hexane_3D_PSA / E.Hexane_3D_SASA
    E["dRg"] = E.Water_avgGR - E.Hexane_avgGR
    E["dRMSD"] = E.Water_avgRMSD_All - E.Hexane_avgRMSD_All
    return sub, E


def zsrc(y, src):
    return C.K.source_normalize(y, src)


def lab_spearman(p, y):
    return float(spearmanr(p, y)[0]) if np.std(p) > 0 and np.std(y) > 0 else 0.0


def lolo(arms, y_raw, src, labs, flat_id, boot=0, seed=0):
    """arms: name -> feature matrix.  Returns per-lab Spearman for each arm (+ per-lab flat-cluster bootstrap CIs of the paired difference vs best 2D arm if boot)."""
    res = {a: {} for a in arms}; preds = {a: {} for a in arms}
    for L in labs:
        te = src == L; tr = ~te
        ytr = zsrc(y_raw[tr], src[tr])
        for a, X in arms.items():
            p = mk().fit(X[tr], ytr).predict(X[te]); preds[a][L] = p; res[a][L] = lab_spearman(p, y_raw[te])
    out = {"per_lab": res}
    if boot and "D+E" in arms and "D" in arms:
        rng = np.random.default_rng(seed); ci = {}
        for L in labs:
            te = src == L; yy = y_raw[te]; fid = flat_id[te]; ug, inv = np.unique(fid, return_inverse=True); by = [np.where(inv == k)[0] for k in range(len(ug))]
            base = "F" if ("F" in arms and res["F"][L] > res["D"][L]) else "D"
            vals = []
            for _ in range(boot):
                ii = np.concatenate([by[k] for k in rng.integers(0, len(ug), len(ug))])
                vals.append(lab_spearman(preds["D+E"][L][ii], yy[ii]) - lab_spearman(preds[base][L][ii], yy[ii]))
            ci[L] = {"base": base, "diff": res["D+E"][L] - res[base][L], "ci95": [float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))], "n_flat_clusters": int(len(ug)), "n": int(te.sum())}
        out["paired_vs_best2d"] = ci
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--controls-only", action="store_true"); ap.add_argument("--seeds", type=int, default=5)
    a = ap.parse_args()
    data_dir = os.environ.get("IDEA_A_DATA", HERE)
    sub, E = load(data_dir)
    y_raw = sub.y_raw.values.astype(float); src = sub.Source.values; flat = sub.flat_id.values
    cnt = pd.Series(src).value_counts(); labs = [s for s in cnt.index if cnt[s] >= MIN_LAB]
    D = C.desc_matrix(sub)[0]; Ev = E.values; F = C.fingerprints(sub.SMILES.values, True)
    print(f"joined {len(sub)} peptides, sources {cnt.to_dict()}, held-out labs {labs}", flush=True)
    R = {"n": int(len(sub)), "sources": {k: int(v) for k, v in cnt.items()}, "labs": labs, "E_columns": list(E.columns), "nan_E": int(np.isnan(Ev).sum())}

    # ---------- controls (cheap arms only) ----------
    cheap = lambda Ex: {"D": D, "E": Ex, "D+E": np.hstack([D, Ex])}
    ctl = {}
    sh = []
    for s in range(a.seeds):
        rng = np.random.default_rng(100 + s); ys = y_raw.copy()
        for g in np.unique(src): m = np.where(src == g)[0]; ys[m] = y_raw[rng.permutation(m)]
        r = lolo(cheap(Ev), ys, src, labs, flat)["per_lab"]; sh.append({k: float(np.mean(list(v.values()))) for k, v in r.items()})
    ctl["shuffled_mean_over_labs"] = {k: float(np.mean([x[k] for x in sh])) for k in sh[0]}
    ctl["shuffled_pass"] = bool(all(abs(v) <= 0.05 for v in ctl["shuffled_mean_over_labs"].values()))
    pl = []
    for s in range(a.seeds):
        rng = np.random.default_rng(200 + s); dp = E.dPSA.values
        yp = np.zeros(len(y_raw))
        for g in np.unique(src):
            m = src == g; z = (dp[m] - dp[m].mean()) / (dp[m].std() or 1.0); yp[m] = z + 0.5 * rng.standard_normal(m.sum())
        r = lolo(cheap(Ev), yp, src, labs, flat)["per_lab"]; pl.append({k: float(np.mean(list(v.values()))) for k, v in r.items()})
    ctl["planted_mean_over_labs"] = {k: float(np.mean([x[k] for x in pl])) for k in pl[0]}
    pm = ctl["planted_mean_over_labs"]; ctl["planted_pass"] = bool(pm["D+E"] >= 0.5 and pm["D"] <= pm["D+E"] - 0.2)
    dc = []
    for s in range(a.seeds):
        rng = np.random.default_rng(300 + s); Ed = Ev[rng.permutation(len(Ev))]
        r = lolo({"D": D, "D+E": np.hstack([D, Ed])}, y_raw, src, labs, flat)["per_lab"]; dc.append({k: float(np.mean(list(v.values()))) for k, v in r.items()})
    ctl["decoy_mean_over_labs"] = {k: float(np.mean([x[k] for x in dc])) for k in dc[0]}
    ctl["decoy_pass"] = bool(abs(ctl["decoy_mean_over_labs"]["D+E"] - ctl["decoy_mean_over_labs"]["D"]) <= 0.02)
    ctl["all_pass"] = bool(ctl["shuffled_pass"] and ctl["planted_pass"] and ctl["decoy_pass"])
    R["controls"] = ctl; print("controls", json.dumps(ctl), flush=True)
    json.dump(R, open(a.out, "w"), indent=1)
    if a.controls_only: return

    # ---------- real contrast ----------
    arms = {"D": D, "F": F, "E": Ev, "D+E": np.hstack([D, Ev]), "F+E": np.hstack([F, Ev])}
    real = lolo(arms, y_raw, src, labs, flat, boot=1000)
    R["real"] = real
    pl_ = real["per_lab"]; R["mean_over_labs"] = {k: float(np.mean(list(v.values()))) for k, v in pl_.items()}
    pv = real["paired_vs_best2d"]; n_ge = sum(1 for v in pv.values() if v["diff"] >= 0.03); n_lo = sum(1 for v in pv.values() if v["ci95"][0] > 0)
    n_le = sum(1 for v in pv.values() if v["diff"] <= 0.03)
    mean_diff = float(np.mean([v["diff"] for v in pv.values()]))
    R["rule"] = {"labs_with_diff_ge_0.03": n_ge, "labs_with_ci_lower_gt_0": n_lo, "labs_with_diff_le_0.03_or_below": n_le, "mean_paired_diff": mean_diff}
    R["verdict"] = ("SUPPORTED (exploratory, 5 labs)" if (n_ge >= 4 and mean_diff >= 0.03 and n_lo >= 3) else ("NOT SUPPORTED" if n_le >= 3 else "MIXED"))
    R["formal_gate"] = "UNDERPOWERED (fewer than 5 informative held-out labs for a cluster CI; per-lab only)"
    # reference: pooled flat-grouped 5-fold
    gp = {}
    for nm, X in arms.items():
        p = np.zeros(len(y_raw)); ysrc = zsrc(y_raw, src)
        for tr, te in GroupKFold(5).split(X, groups=flat): p[te] = mk().fit(X[tr], ysrc[tr]).predict(X[te])
        gp[nm] = lab_spearman(p, ysrc)
    R["flat_grouped_5fold_pooled_spearman"] = gp
    json.dump(R, open(a.out, "w"), indent=1); print(json.dumps({k: R[k] for k in ("mean_over_labs", "rule", "verdict", "formal_gate", "flat_grouped_5fold_pooled_spearman")}, indent=1), flush=True)


if __name__ == "__main__":
    main()
