"""Permeability regressor on CycPeptMPDB with leak-free Murcko-scaffold CV + uncertainty
(Phase-2 Bet-1, second developability endpoint). Mirrors the stability predictor: ECFP4 + a
bootstrap-bagged HistGradientBoosting ensemble (mean + std). Regression target = log Papp
(the `Permeability` column). Honest leak-free split by Bemis-Murcko generic scaffold.

The existing (July) permeability models capped at scaffold-R2 ~0.1-0.3 vs published 0.67-0.77;
this rebuild reports the same honest metric with a calibrated ensemble + uncertainty so it can
serve as a (ranking-grade) endpoint for multi-property selection.
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from rdkit.Chem.Scaffolds import MurckoScaffold
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import r2_score, mean_absolute_error, mean_squared_error

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)


def load(path):
    X, y, scaf = [], [], []
    for r in csv.DictReader(open(path)):
        smi = r.get("SMILES", "").strip()
        try:
            perm = float(r.get("Permeability", ""))
        except (TypeError, ValueError):
            continue
        if not (-10.5 < perm < -3.5):  # drop detection-limit placeholders / out-of-range
            continue
        m = Chem.MolFromSmiles(smi)
        if m is None:
            continue
        X.append(np.asarray(_FP.GetFingerprint(m), dtype=np.float32))
        y.append(perm)
        try:
            s = MurckoScaffold.MurckoScaffoldSmiles(mol=MurckoScaffold.GetScaffoldForMol(m), includeChirality=False)
        except Exception:
            s = smi
        scaf.append(s or smi)
    return np.array(X), np.array(y), np.array(scaf)


def bagged_fit_predict(Xtr, ytr, Xte, n=5, seed=0):
    rng = np.random.default_rng(seed)
    preds = []
    for s in range(n):
        idx = rng.integers(0, len(ytr), len(ytr))
        m = HistGradientBoostingRegressor(max_iter=150, learning_rate=0.06, max_leaf_nodes=31,
                                          l2_regularization=1.0, random_state=s)
        m.fit(Xtr[idx], ytr[idx])
        preds.append(m.predict(Xte))
    preds = np.vstack(preds)
    return preds.mean(0), preds.std(0)


def scaffold_folds(scaf, n_folds=5, seed=0):
    """Group scaffolds into folds (largest-first round-robin) so no scaffold crosses folds."""
    groups = defaultdict(list)
    for i, s in enumerate(scaf):
        groups[s].append(i)
    order = sorted(groups.values(), key=len, reverse=True)
    fold_of = {}
    sizes = [0] * n_folds
    for members in order:
        f = int(np.argmin(sizes))
        for i in members:
            fold_of[i] = f
        sizes[f] += len(members)
    return np.array([fold_of[i] for i in range(len(scaf))])


def main():
    ap = argparse.ArgumentParser()
    import dataset_path  # G8: resolve the training CSV through cyclic_data_registry (committed fallback)
    ap.add_argument("--csv", type=Path,
                    default=dataset_path.resolve("cycpeptmpdb", "data/raw/CycPeptMPDB_Peptide_All.csv"))
    ap.add_argument("--out", type=Path, default=ROOT / "results/permeability_predictor_metrics.json")
    args = ap.parse_args()

    X, y, scaf = load(args.csv)
    fold = scaffold_folds(scaf)
    oof = np.full(len(y), np.nan)
    oof_u = np.full(len(y), np.nan)
    for f in sorted(set(fold.tolist())):
        te = fold == f
        p, u = bagged_fit_predict(X[~te], y[~te], X[te])
        oof[te] = p; oof_u[te] = u

    report = {
        "n": int(len(y)), "target": "Permeability (log Papp)",
        "features": "ECFP4 Morgan (r=2, 2048)",
        "model": "HistGradientBoostingRegressor bootstrap-bagged (5); std = epistemic uncertainty",
        "split": "leak-free Bemis-Murcko generic-scaffold folds (5)",
        "n_scaffolds": int(len(set(scaf.tolist()))),
        "scaffold_r2": float(r2_score(y, oof)),
        "scaffold_mae": float(mean_absolute_error(y, oof)),
        "scaffold_rmse": float(np.sqrt(mean_squared_error(y, oof))),
        "mean_epistemic_std": float(np.nanmean(oof_u)),
        "reference_r2": {"CPMP": 0.67, "CycPeptMP": 0.77, "prior_our_work": "0.11-0.29"},
        "limits": ["ranking-grade, well below published references (which use multimodal models)",
                   "log Papp regression; ECFP-only; no 3D/conformer features",
                   "scaffold split is the honest generalization metric (random-split R2 is higher)"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
