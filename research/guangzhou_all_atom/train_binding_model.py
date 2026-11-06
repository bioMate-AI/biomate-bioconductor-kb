#!/usr/bin/env python3
"""Track A1 — real-data cyclic-peptide binding predictor.

Trains SMILES -> measured pAffinity (= 9 - log10(affinity_nM)) models on
binding_affinity_v1 (136,730 measured rows). HONEST dual eval:
  (1) RANDOM split            — optimistic, in-distribution
  (2) NOVEL-TARGET held-out   — hold out PD-L1 + alphaVbeta6 rows ENTIRELY,
                                evaluate on them (the generalization reality).

Censored relations ('>','<', ...) are EXCLUDED from training/eval (documented).
Duplicate (smiles, target, assay_type) rows are collapsed to their median pAffinity.

Baselines: Ridge, RandomForest, XGBoost on ECFP4(2048) + 16 physchem descriptors
+ assay-type one-hot. (Chemprop/DMPNN: not run here — needs GPU/extra setup; XGB
is the strong CPU baseline. Documented as a gap.)

Outputs (research/guangzhou_all_atom/results/):
  binding_model_metrics.json   — all split x model metrics + calibration
  binding_model_prod.pkl       — XGB trained on ALL usable rows (for A3 scoring)
  binding_feature_cache.npz    — cached features (regenerated if missing)
"""
import argparse, json, os, pickle, sys, time
import numpy as np
import pandas as pd
from scipy.stats import spearmanr, pearsonr

from binding_features import featurize_smiles, DESC_NAMES

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
os.makedirs(RESULTS, exist_ok=True)

ASSAY_TYPES = ["IC50", "Ki", "EC50", "Kd"]


def load_and_clean(csv_path):
    df = pd.read_csv(csv_path, low_memory=False)
    n0 = len(df)
    # keep exact/approx measurements only (censored excluded, documented)
    df = df[df["relation"].isin(["=", "~"])].copy()
    n_censored_removed = n0 - len(df)
    # sane affinity range: 1 pM .. 100 mM  => pAffinity in [ -2 , 12 ]
    df = df[df["affinity_nM"] > 0]
    df = df[(df["affinity_nM"] >= 1e-3) & (df["affinity_nM"] <= 1e8)]
    df["pAff"] = 9.0 - np.log10(df["affinity_nM"].astype(float))
    df = df[df["affinity_type"].isin(ASSAY_TYPES)]
    df["smiles"] = df["smiles"].astype(str)
    # collapse exact duplicates (same ligand, target, assay) -> median
    df = (df.groupby(["smiles", "target_uniprot", "affinity_type"], as_index=False)
            .agg(pAff=("pAff", "median"),
                 is_pdl1=("is_pdl1", "max"),
                 is_avb6=("is_avb6", "max"),
                 cyclic_bool=("cyclic_bool", "max")))
    return df, n0, n_censored_removed


def build_features(df, cache):
    if os.path.exists(cache):
        z = np.load(cache, allow_pickle=True)
        if z["smiles"].shape[0] == len(df) and bool((z["smiles"] == df["smiles"].values).all()):
            return z["fp"], z["desc"]
    fps, descs, ok = [], [], np.zeros(len(df), dtype=bool)
    t0 = time.time()
    for i, smi in enumerate(df["smiles"].values):
        r = featurize_smiles(smi)
        if r is None:
            fps.append(np.zeros(2048, np.uint8)); descs.append(np.zeros(16, np.float32))
        else:
            fps.append(r[0]); descs.append(r[1]); ok[i] = True
        if (i + 1) % 20000 == 0:
            print(f"  featurized {i+1}/{len(df)} ({time.time()-t0:.0f}s)", flush=True)
    fp = np.vstack(fps); desc = np.vstack(descs)
    np.savez_compressed(cache, fp=fp, desc=desc, ok=ok, smiles=df["smiles"].values)
    return fp, desc


def assemble_X(df, fp, desc):
    # standardize descriptors later (per-fit); append assay one-hot here
    onehot = np.zeros((len(df), len(ASSAY_TYPES)), np.float32)
    at = df["affinity_type"].values
    for j, a in enumerate(ASSAY_TYPES):
        onehot[:, j] = (at == a).astype(np.float32)
    return fp.astype(np.float32), desc.astype(np.float32), onehot


def metrics(y_true, y_pred):
    y_true = np.asarray(y_true); y_pred = np.asarray(y_pred)
    rmse = float(np.sqrt(np.mean((y_true - y_pred) ** 2)))
    mae = float(np.mean(np.abs(y_true - y_pred)))
    sp = float(spearmanr(y_true, y_pred).correlation)
    pr = float(pearsonr(y_true, y_pred)[0]) if len(y_true) > 2 else float("nan")
    # R^2
    ss_res = np.sum((y_true - y_pred) ** 2); ss_tot = np.sum((y_true - y_true.mean()) ** 2)
    r2 = float(1 - ss_res / ss_tot) if ss_tot > 0 else float("nan")
    within1 = float(np.mean(np.abs(y_true - y_pred) <= 1.0))  # within 1 log unit
    # calibration: slope of y_true ~ y_pred (1.0 = perfectly calibrated spread)
    if np.std(y_pred) > 1e-9:
        cal_slope = float(np.polyfit(y_pred, y_true, 1)[0])
    else:
        cal_slope = float("nan")
    return dict(n=int(len(y_true)), rmse=rmse, mae=mae, spearman=sp, pearson=pr,
                r2=r2, within_1_log=within1, calibration_slope=cal_slope,
                pred_mean=float(y_pred.mean()), true_mean=float(y_true.mean()),
                pred_std=float(y_pred.std()), true_std=float(y_true.std()))


def fit_models(Xtr, ytr):
    from sklearn.linear_model import Ridge
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.preprocessing import StandardScaler
    import xgboost as xgb
    out = {}
    # Ridge needs scaling; tree models don't
    scaler = StandardScaler().fit(Xtr.astype(np.float64))
    Xs = np.nan_to_num(scaler.transform(Xtr.astype(np.float64)), nan=0.0, posinf=0.0, neginf=0.0)
    ridge = Ridge(alpha=10.0).fit(Xs, ytr)
    out["Ridge"] = ("scaled", scaler, ridge)
    rf = RandomForestRegressor(n_estimators=300, max_depth=None, n_jobs=-1,
                               min_samples_leaf=3, max_features="sqrt", random_state=0)
    rf.fit(Xtr, ytr)
    out["RandomForest"] = ("raw", None, rf)
    xgbm = xgb.XGBRegressor(n_estimators=600, max_depth=8, learning_rate=0.05,
                            subsample=0.8, colsample_bytree=0.6, tree_method="hist",
                            n_jobs=-1, random_state=0, reg_lambda=1.0)
    xgbm.fit(Xtr, ytr)
    out["XGBoost"] = ("raw", None, xgbm)
    return out


def predict(model_tuple, X):
    kind, scaler, m = model_tuple
    if kind == "scaled":
        Xs = np.nan_to_num(scaler.transform(X.astype(np.float64)), nan=0.0, posinf=0.0, neginf=0.0)
        return m.predict(Xs)
    return m.predict(X)


def main():
    ap = argparse.ArgumentParser()
    import dataset_path  # G8: default the training CSV to the registry's binding_affinity_v1
    ap.add_argument("--csv", default=str(dataset_path.resolve(
        "binding_affinity_v1", "data/raw/binding_affinity/binding_affinity_v1.csv")),
        help="measured-affinity training CSV (default: cyclic_data_registry binding_affinity_v1)")
    ap.add_argument("--cyclic-only", action="store_true",
                    help="train/eval on cyclic rows only (matches the peptide pools regime)")
    ap.add_argument("--tag", default="")
    args = ap.parse_args()

    df, n0, n_cens = load_and_clean(args.csv)
    print(f"loaded {n0} rows; after clean+dedup {len(df)}; censored removed {n_cens}", flush=True)
    cache = os.path.join(RESULTS, "binding_feature_cache.npz")
    fp, desc = build_features(df, cache)
    fp, desc, onehot = assemble_X(df, fp, desc)
    df = df.reset_index(drop=True)

    if args.cyclic_only:
        mask = df["cyclic_bool"].astype(bool).values
        df = df[mask].reset_index(drop=True); fp = fp[mask]; desc = desc[mask]; onehot = onehot[mask]
        print(f"cyclic-only subset: {len(df)} rows", flush=True)

    X = np.hstack([fp, desc, onehot])
    # sanitize: a handful of pathological SMILES yield non-finite / extreme descriptors
    X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)
    # clip the descriptor block (cols fp..fp+16) to robust ranges to stop float32 variance overflow
    d0 = fp.shape[1]
    X[:, d0:d0 + desc.shape[1]] = np.clip(X[:, d0:d0 + desc.shape[1]], -1e6, 1e6)
    y = df["pAff"].values.astype(np.float32)
    held = (df["is_pdl1"].astype(bool) | df["is_avb6"].astype(bool)).values
    print(f"feature dim {X.shape[1]}; PD-L1/avb6 held rows in this subset: {int(held.sum())}", flush=True)

    report = {"dataset": {"raw_rows": n0, "clean_dedup_rows": int(len(df)),
                          "censored_removed": int(n_cens),
                          "cyclic_only": bool(args.cyclic_only),
                          "n_pdl1_avb6": int(held.sum()),
                          "target_transform": "pAff = 9 - log10(affinity_nM)",
                          "features": f"ECFP4(2048)+{len(DESC_NAMES)} physchem+assay_onehot(4)",
                          "assay_types": ASSAY_TYPES,
                          "note_assay_mix": "IC50/Ki/EC50/Kd pooled; assay encoded as one-hot feature"},
              "splits": {}}

    # ---------- RANDOM split (on non-held + held mixed, standard 80/20) ----------
    rng = np.random.default_rng(42)
    idx = rng.permutation(len(df)); cut = int(0.8 * len(df))
    tr, te = idx[:cut], idx[cut:]
    print(f"\n== RANDOM split: train {len(tr)} / test {len(te)} ==", flush=True)
    models = fit_models(X[tr], y[tr])
    report["splits"]["random"] = {name: metrics(y[te], predict(m, X[te])) for name, m in models.items()}
    for n, r in report["splits"]["random"].items():
        print(f"  {n:13s} RMSE {r['rmse']:.3f}  Spearman {r['spearman']:.3f}  R2 {r['r2']:.3f}  within1 {r['within_1_log']:.2f}", flush=True)

    # ---------- NOVEL-TARGET held-out: PD-L1/avb6 OUT of train ----------
    if held.sum() >= 20:
        tr2 = np.where(~held)[0]; te2 = np.where(held)[0]
        print(f"\n== NOVEL-TARGET split: train {len(tr2)} (no PD-L1/avb6) / test {len(te2)} (PD-L1+avb6) ==", flush=True)
        models2 = fit_models(X[tr2], y[tr2])
        report["splits"]["novel_target_pdl1_avb6"] = {name: metrics(y[te2], predict(m, X[te2])) for name, m in models2.items()}
        for n, r in report["splits"]["novel_target_pdl1_avb6"].items():
            print(f"  {n:13s} RMSE {r['rmse']:.3f}  Spearman {r['spearman']:.3f}  R2 {r['r2']:.3f}  within1 {r['within_1_log']:.2f}", flush=True)
        # per-target breakdown for XGB
        bd = {}
        for tgt, m in (("PD-L1", df["is_pdl1"].astype(bool).values),
                       ("avb6", df["is_avb6"].astype(bool).values)):
            te_t = np.where(m)[0]
            if len(te_t) >= 10:
                bd[tgt] = metrics(y[te_t], predict(models2["XGBoost"], X[te_t]))
        report["splits"]["novel_target_breakdown_xgb"] = bd
        for tgt, r in bd.items():
            print(f"    [{tgt}] XGB RMSE {r['rmse']:.3f} Spearman {r['spearman']:.3f} true_mean {r['true_mean']:.2f} pred_mean {r['pred_mean']:.2f}", flush=True)
    else:
        print("  (too few held rows for novel-target split in this subset)", flush=True)

    # ---------- production model: XGB on ALL usable rows (for A3 scoring) ----------
    if not args.cyclic_only:
        import xgboost as xgb
        prod = xgb.XGBRegressor(n_estimators=600, max_depth=8, learning_rate=0.05,
                                subsample=0.8, colsample_bytree=0.6, tree_method="hist",
                                n_jobs=-1, random_state=0, reg_lambda=1.0)
        prod.fit(X, y)
        with open(os.path.join(RESULTS, "binding_model_prod.pkl"), "wb") as fh:
            pickle.dump({"model": prod, "assay_types": ASSAY_TYPES,
                         "desc_names": DESC_NAMES, "feat_dim": X.shape[1]}, fh)
        report["production_model"] = {"file": "binding_model_prod.pkl",
                                      "trained_on_rows": int(len(df)),
                                      "note": "XGB on ALL usable rows incl PD-L1/avb6; used by A3 to score pools"}
        print("\nsaved production model -> results/binding_model_prod.pkl", flush=True)

    out = os.path.join(RESULTS, f"binding_model_metrics{('_'+args.tag) if args.tag else ''}.json")
    with open(out, "w") as fh:
        json.dump(report, fh, indent=2)
    print(f"\nwrote {out}", flush=True)


if __name__ == "__main__":
    main()
