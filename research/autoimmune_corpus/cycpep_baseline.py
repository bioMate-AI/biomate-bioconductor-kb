#!/usr/bin/env python3
"""Cyclic-peptide permeability BASELINE GATE. Uses CycPeptMPDB's OWN precomputed
numeric descriptor columns as features (robust; rdkit macrocycle SMILES sanitization
is unreliable), with an rdkit fallback. Predicts membrane permeability; the go/no-go
for a learned macrocycle model.

Usage: python3 cycpep_baseline.py --csv CycPeptMPDB_Peptide_All.csv --out out/
"""
import argparse, json, os, sys
import numpy as np, pandas as pd


def find_col(cols, keys):
    for c in cols:
        cl = str(c).lower()
        if any(k in cl for k in keys):
            return c
    return None


def rdkit_features(smiles_series):
    from rdkit import Chem
    from rdkit.Chem import Descriptors, Crippen, rdMolDescriptors
    rows = []
    for s in smiles_series:
        m = Chem.MolFromSmiles(str(s))
        if m is None:
            m = Chem.MolFromSmiles(str(s), sanitize=False)
            if m is not None:
                try:
                    Chem.SanitizeMol(m, Chem.SanitizeFlags.SANITIZE_ALL ^
                                     Chem.SanitizeFlags.SANITIZE_KEKULIZE)
                except Exception:
                    m = None
        if m is None:
            rows.append(None); continue
        rows.append({"MolWt": Descriptors.MolWt(m), "TPSA": rdMolDescriptors.CalcTPSA(m),
                     "MolLogP": Crippen.MolLogP(m), "NumHDonors": rdMolDescriptors.CalcNumHBD(m),
                     "NumHAcceptors": rdMolDescriptors.CalcNumHBA(m),
                     "NumRotatableBonds": rdMolDescriptors.CalcNumRotatableBonds(m),
                     "RingCount": rdMolDescriptors.CalcNumRings(m)})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--out", default="out")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    df = pd.read_csv(args.csv, low_memory=False)
    smi = find_col(df.columns, ["smiles"])
    # among permeability-like columns, pick the one with the MOST numeric values
    perm_cands = [c for c in df.columns if "permeab" in str(c).lower() or "papp" in str(c).lower()]
    perm, best = None, -1
    for c in perm_cands:
        nn = pd.to_numeric(df[c], errors="coerce").notna().sum()
        if nn > best:
            best, perm = nn, c
    sys.stderr.write(f"rows={len(df)} smiles_col={smi} perm_col={perm} (non_null={best}) "
                     f"candidates={perm_cands}\n")
    df[perm] = pd.to_numeric(df[perm], errors="coerce")

    # PRIMARY: CycPeptMPDB's own numeric descriptor columns
    num = df.select_dtypes(include=[np.number])
    drop_kw = ["permeab", "papp", "unnamed", "index", "_id", "year", "cycpep_id"]
    feat_cols = [c for c in num.columns if c != perm and not any(k in str(c).lower() for k in drop_kw)]
    used = "cycpeptmpdb_numeric"

    data = num[feat_cols].copy()
    data["_perm"] = pd.to_numeric(df[perm], errors="coerce")
    data = data[data["_perm"].notna()].reset_index(drop=True)   # require only the target
    # keep informative feature columns (>=50% present and non-constant)
    feat_cols = [c for c in feat_cols
                 if data[c].notna().sum() >= 0.5 * len(data) and data[c].nunique(dropna=True) > 1]

    if len(feat_cols) < 3 and smi:          # FALLBACK: rdkit
        used = "rdkit"
        rk = rdkit_features(df[smi])
        keep = [i for i, r in enumerate(rk) if r is not None]
        fr = pd.DataFrame([rk[i] for i in keep])
        fr["_perm"] = pd.to_numeric(df[perm], errors="coerce").to_numpy()[keep]
        data = fr.dropna(subset=["_perm"]).reset_index(drop=True)
        feat_cols = [c for c in data.columns if c != "_perm"]

    sys.stderr.write(f"features={used} n_feat={len(feat_cols)} n_rows={len(data)}\n")
    data[feat_cols + ["_perm"]].to_csv(os.path.join(args.out, "cycpep_features.csv"), index=False)

    try:
        from sklearn.linear_model import Ridge
    except ImportError:
        import subprocess; subprocess.run([sys.executable, "-m", "pip", "install", "-q", "scikit-learn"])
    from sklearn.model_selection import train_test_split
    from sklearn.linear_model import Ridge
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.preprocessing import StandardScaler
    from sklearn.metrics import r2_score, mean_squared_error, mean_absolute_error

    X = data[feat_cols].to_numpy(dtype=float); y = data["_perm"].to_numpy(dtype=float)
    # clean non-finite (inf -> nan), then median-impute
    X[~np.isfinite(X)] = np.nan
    col_med = np.nanmedian(X, axis=0); col_med = np.where(np.isfinite(col_med), col_med, 0.0)
    ii = np.where(np.isnan(X)); X[ii] = np.take(col_med, ii[1])
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=0)
    res = {"n_peptides": int(len(data)), "target": perm, "feature_source": used,
           "n_features": len(feat_cols), "perm_range": [float(y.min()), float(y.max())]}
    sc = StandardScaler().fit(Xtr)
    for name, mdl in [("ridge", Ridge(alpha=1.0)),
                      ("random_forest", RandomForestRegressor(n_estimators=300, n_jobs=-1, random_state=0))]:
        Xt, Xv = (sc.transform(Xtr), sc.transform(Xte)) if name == "ridge" else (Xtr, Xte)
        mdl.fit(Xt, ytr); yp = mdl.predict(Xv)
        res[name] = {"r2": float(r2_score(yte, yp)),
                     "rmse": float(mean_squared_error(yte, yp) ** 0.5),
                     "mae": float(mean_absolute_error(yte, yp))}
    if hasattr(mdl, "feature_importances_"):
        imp = sorted(zip(feat_cols, [float(x) for x in mdl.feature_importances_]),
                     key=lambda kv: -kv[1])[:12]
        res["rf_top_features"] = dict(imp)

    mwc, tpsac, hbdc = (find_col(feat_cols, ["molwt", "molecular_weight", "mol_wt"]),
                        find_col(feat_cols, ["tpsa", "psa"]),
                        find_col(feat_cols, ["hbd", "donor"]))
    if mwc and tpsac and hbdc:
        yud = data[mwc].between(500, 2000) & (data[tpsac] < 250) & (data[hbdc] <= 5)
        res["yudin_pass_rate"] = float(yud.mean())

    json.dump(res, open(os.path.join(args.out, "cycpep_baseline_metrics.json"), "w"), indent=2)
    print(json.dumps(res, indent=2))
    print("\nGATE HINT: high descriptor R2 => a learned macrocycle model must beat it; "
          "low R2 => headroom for a learned permeability model + wet-lab active learning.")


if __name__ == "__main__":
    main()
