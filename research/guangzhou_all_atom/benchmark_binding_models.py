#!/usr/bin/env python3
"""Track A1b — stronger cyclic-peptide binding models + a RIGOROUS novel-target eval.

Extends train_binding_model.py. Two honest additions over the baseline:
  (1) GROUPED leave-targets-out CV (GroupKFold by target_uniprot) -> a robust
      novel-target Spearman with a spread (the baseline held out only PD-L1+avb6,
      n=327, 2 targets -> not a robust generalization estimate).
  (2) Stronger features (ECFP4+physchem+assay  vs  +MACCS+extra RDKit desc) and a
      stronger GBM (sklearn HistGradientBoosting; xgboost unavailable on py3.14).

Reuses the cached ECFP4+physchem features (results/binding_feature_cache.npz).
Headline = grouped novel-target CV (leakage-safe). Random split reported only as the
analog-leaky upper bound. No fabrication; every number from this run.
"""
import json, os, time
import numpy as np, pandas as pd
from scipy.stats import spearmanr

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
CSV = os.path.join(HERE, "data/raw/binding_affinity/binding_affinity_v1.csv")
CACHE = os.path.join(RESULTS, "binding_feature_cache.npz")
ASSAY = ["IC50", "Ki", "EC50", "Kd"]


def load_and_clean(csv_path):
    df = pd.read_csv(csv_path, low_memory=False)
    df = df[df["relation"].isin(["=", "~"])].copy()
    df = df[df["affinity_nM"] > 0]
    df = df[(df["affinity_nM"] >= 1e-3) & (df["affinity_nM"] <= 1e8)]
    df["pAff"] = 9.0 - np.log10(df["affinity_nM"].astype(float))
    df = df[df["affinity_type"].isin(ASSAY)]
    df["smiles"] = df["smiles"].astype(str)
    df = (df.groupby(["smiles", "target_uniprot", "affinity_type"], as_index=False)
            .agg(pAff=("pAff", "median"), is_pdl1=("is_pdl1", "max"),
                 is_avb6=("is_avb6", "max"), cyclic_bool=("cyclic_bool", "max")))
    return df


def maccs_and_extra(smiles):
    from rdkit import Chem
    from rdkit.Chem import MACCSkeys, Descriptors, rdMolDescriptors
    extra_fns = [Descriptors.FractionCSP3, rdMolDescriptors.CalcNumRings,
                 rdMolDescriptors.CalcNumAromaticRings, rdMolDescriptors.CalcNumRotatableBonds,
                 rdMolDescriptors.CalcNumHBD, rdMolDescriptors.CalcNumHBA,
                 Descriptors.MolLogP, Descriptors.TPSA, Descriptors.MolWt,
                 rdMolDescriptors.CalcNumAmideBonds]
    macc = np.zeros((len(smiles), 167), np.float32); ex = np.zeros((len(smiles), len(extra_fns)), np.float32)
    for i, smi in enumerate(smiles):
        m = Chem.MolFromSmiles(smi)
        if m is None:
            continue
        try:
            macc[i] = np.array(MACCSkeys.GenMACCSKeys(m), np.float32)
            ex[i] = [f(m) for f in extra_fns]
        except Exception:
            pass
    return macc, np.nan_to_num(ex, nan=0.0, posinf=0.0, neginf=0.0)


def models():
    from sklearn.ensemble import RandomForestRegressor, HistGradientBoostingRegressor
    from sklearn.linear_model import Ridge
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler
    return {
        "Ridge": make_pipeline(StandardScaler(with_mean=False), Ridge(alpha=10.0)),
        "RandomForest": RandomForestRegressor(n_estimators=300, min_samples_leaf=3,
                                              max_features="sqrt", n_jobs=-1, random_state=0),
        "HistGBM": HistGradientBoostingRegressor(max_iter=600, learning_rate=0.05,
                                                 max_depth=8, l2_regularization=1.0, random_state=0),
    }


def sp(y, p):
    return float(spearmanr(y, p).correlation)


def grouped_cv(X, y, groups, n_splits=5):
    """GroupKFold by target -> per-fold Spearman on held-out targets. Returns per model."""
    from sklearn.model_selection import GroupKFold
    gkf = GroupKFold(n_splits=n_splits)
    per = {name: [] for name in models()}
    for tr, te in gkf.split(X, y, groups):
        mdl = models()
        for name, m in mdl.items():
            m.fit(X[tr], y[tr])
            per[name].append(sp(y[te], m.predict(X[te])))
    out = {}
    for name, vals in per.items():
        v = np.array(vals, float)
        out[name] = {"spearman_mean": float(v.mean()), "spearman_std": float(v.std()),
                     "folds": [round(x, 3) for x in v], "n_splits": n_splits}
    return out


def pdl1_avb6_holdout(X, y, held, is_pdl1, is_avb6):
    tr, te = np.where(~held)[0], np.where(held)[0]
    out = {}
    mdl = models()
    for name, m in mdl.items():
        m.fit(X[tr], y[tr]); pred = m.predict(X[te])
        out[name] = {"spearman": sp(y[te], pred), "n": int(len(te))}
        if name == "HistGBM":
            for tgt, mask in (("PD-L1", is_pdl1), ("avb6", is_avb6)):
                tt = np.where(mask)[0]
                if len(tt) >= 10:
                    out.setdefault("breakdown", {})[tgt] = {"spearman": sp(y[tt], m.predict(X[tt])), "n": int(len(tt))}
    return out


def main():
    t0 = time.time()
    df = load_and_clean(CSV).reset_index(drop=True)
    z = np.load(CACHE, allow_pickle=True)
    assert z["smiles"].shape[0] == len(df) and bool((z["smiles"] == df["smiles"].values).all()), \
        "cache/smiles mismatch — recompute features via train_binding_model.py first"
    fp, desc = z["fp"].astype(np.float32), z["desc"].astype(np.float32)
    onehot = np.zeros((len(df), 4), np.float32)
    for j, a in enumerate(ASSAY):
        onehot[:, j] = (df["affinity_type"].values == a).astype(np.float32)

    mask = df["cyclic_bool"].astype(bool).values
    df = df[mask].reset_index(drop=True); fp, desc, onehot = fp[mask], desc[mask], onehot[mask]
    print(f"cyclic rows: {len(df)}  ({time.time()-t0:.0f}s)", flush=True)

    X_base = np.nan_to_num(np.hstack([fp, desc, onehot]), nan=0.0, posinf=0.0, neginf=0.0)
    X_base[:, fp.shape[1]:fp.shape[1]+desc.shape[1]] = np.clip(X_base[:, fp.shape[1]:fp.shape[1]+desc.shape[1]], -1e6, 1e6)
    macc, extra = maccs_and_extra(df["smiles"].values)
    X_rich = np.nan_to_num(np.hstack([X_base, macc, extra]), nan=0.0, posinf=0.0, neginf=0.0)
    print(f"features: base {X_base.shape[1]}  rich {X_rich.shape[1]}  ({time.time()-t0:.0f}s)", flush=True)

    y = df["pAff"].values.astype(np.float32)
    held = (df["is_pdl1"].astype(bool) | df["is_avb6"].astype(bool)).values
    # grouped CV needs a target group per row; drop empty target_uniprot for the CV only
    tgt = df["target_uniprot"].fillna("").astype(str).values
    gmask = tgt != ""
    n_targets = len(set(tgt[gmask]))
    print(f"grouped-CV rows {int(gmask.sum())} across {n_targets} targets; PD-L1/avb6 held {int(held.sum())}", flush=True)

    report = {"n_cyclic": int(len(df)), "n_targets_for_cv": int(n_targets),
              "headline": "grouped leave-targets-out CV (leakage-safe); PD-L1/avb6 holdout matches baseline",
              "baseline_ref": "results/binding_model_metrics_cyclic.json (RF/XGB novel-target Spearman 0.42/0.38)",
              "splits": {}}

    print("== grouped leave-targets-out CV: BASE features ==", flush=True)
    report["splits"]["grouped_cv_base"] = grouped_cv(X_base[gmask], y[gmask], tgt[gmask])
    print(json.dumps(report["splits"]["grouped_cv_base"], indent=1), flush=True)

    print(f"== grouped CV: RICH features ==  ({time.time()-t0:.0f}s)", flush=True)
    report["splits"]["grouped_cv_rich"] = grouped_cv(X_rich[gmask], y[gmask], tgt[gmask])
    print(json.dumps(report["splits"]["grouped_cv_rich"], indent=1), flush=True)

    print(f"== PD-L1/avb6 holdout (match baseline): BASE ==  ({time.time()-t0:.0f}s)", flush=True)
    report["splits"]["pdl1_avb6_holdout_base"] = pdl1_avb6_holdout(
        X_base, y, held, df["is_pdl1"].astype(bool).values, df["is_avb6"].astype(bool).values)
    report["splits"]["pdl1_avb6_holdout_rich"] = pdl1_avb6_holdout(
        X_rich, y, held, df["is_pdl1"].astype(bool).values, df["is_avb6"].astype(bool).values)
    print(json.dumps(report["splits"]["pdl1_avb6_holdout_rich"], indent=1), flush=True)

    out = os.path.join(RESULTS, "binding_model_benchmark_cyclic.json")
    json.dump(report, open(out, "w"), indent=2)
    print(f"\nwrote {out}  ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
