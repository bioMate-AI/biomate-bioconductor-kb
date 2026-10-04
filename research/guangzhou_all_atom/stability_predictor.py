"""Peptide blood-stability predictor on the PepMSND leak-free folds (Phase-2 Bet-1, developability).

Binary stability label. Uses the structure-disjoint 10-fold splits rebuilt in
rebuild_stability_folds.py (results/pepmsnd_fold_rebuild.json). Features are ECFP4 Morgan
fingerprints; an ensemble of HistGradientBoosting models gives calibrated probabilities plus an
epistemic-uncertainty estimate (std across the ensemble) for uncertainty-aware acquisition later.

Reports leak-free cross-fold AUROC + calibration (Brier, ECE). The 3 label-conflict structures
(same molecule labelled both 0 and 1) are excluded — flagged, not silently kept.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score, brier_score_loss

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
_FPGEN = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)


def featurize(smiles):
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    return np.asarray(_FPGEN.GetFingerprint(mol), dtype=np.float32)


def load(csv_path):
    import csv
    rows = [r for r in csv.DictReader(open(csv_path)) if r["label_conflict"] != "True"]
    X, y, fold = [], [], []
    for r in rows:
        f = featurize(r["canonical_smiles"])
        if f is None:
            continue
        X.append(f); y.append(int(r["label"])); fold.append(int(r["fold"]))
    return np.array(X), np.array(y), np.array(fold)


def ensemble_fit_predict(Xtr, ytr, Xte, n_models=10, seed=0):
    """Bootstrap-bagged HistGBM ensemble -> mean proba + epistemic std. Bagging (resample the
    training rows per member) is what creates ensemble diversity; seed-only variation on the
    same data is near-deterministic for HistGBM and gives ~0 uncertainty."""
    rng = np.random.default_rng(seed)
    n = len(ytr)
    probs = []
    for s in range(n_models):
        idx = rng.integers(0, n, size=n)  # bootstrap sample
        if len(set(ytr[idx].tolist())) < 2:  # guard degenerate resample
            idx = np.arange(n)
        m = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.05,
                                           max_leaf_nodes=15, l2_regularization=1.0,
                                           random_state=s)
        m.fit(Xtr[idx], ytr[idx])
        probs.append(m.predict_proba(Xte)[:, 1])
    probs = np.vstack(probs)
    return probs.mean(0), probs.std(0)


def ece(y, p, n_bins=10):
    bins = np.linspace(0, 1, n_bins + 1)
    e = 0.0
    for i in range(n_bins):
        m = (p >= bins[i]) & (p < bins[i + 1] if i < n_bins - 1 else p <= bins[i + 1])
        if m.sum():
            e += m.mean() * abs(y[m].mean() - p[m].mean())
    return float(e)


def main():
    ap = argparse.ArgumentParser()
    import dataset_path  # G8: resolve via cyclic_data_registry (committed fallback)
    ap.add_argument("--csv", type=Path,
                    default=dataset_path.resolve("pepmsnd_stability_folds",
                                                 "data/processed/pepmsnd_stability_folds.csv"))
    ap.add_argument("--out", type=Path, default=ROOT / "results/stability_predictor_metrics.json")
    args = ap.parse_args()

    X, y, fold = load(args.csv)
    folds = sorted(set(fold.tolist()))
    oof_p = np.full(len(y), np.nan)
    oof_u = np.full(len(y), np.nan)
    per_fold = {}
    for f in folds:
        te = fold == f
        tr = ~te
        p, u = ensemble_fit_predict(X[tr], y[tr], X[te])
        oof_p[te] = p
        oof_u[te] = u
        yte = y[te]
        per_fold[str(f)] = {"n": int(te.sum()),
                            "auroc": (roc_auc_score(yte, p) if len(set(yte)) > 1 else None)}

    report = {
        "n": int(len(y)),
        "n_pos": int(y.sum()),
        "n_folds": len(folds),
        "features": "ECFP4 Morgan (r=2, 2048 bits)",
        "model": "HistGradientBoosting bootstrap-bagged ensemble (10 members); std = epistemic uncertainty",
        "split": "structure-disjoint leak-free folds (rebuild_stability_folds.py)",
        "oof_auroc": float(roc_auc_score(y, oof_p)),
        "oof_brier": float(brier_score_loss(y, oof_p)),
        "oof_ece": ece(y, oof_p),
        "mean_epistemic_std": float(np.nanmean(oof_u)),
        "per_fold_auroc": per_fold,
        "baseline_auroc_majority": 0.5,
        "limits": ["ECFP-only features; no 3D/assay-condition modeling",
                   "leak-free folds remove structure leakage but are a modest set (~602 mols)",
                   "ranking-grade, not a calibrated clinical stability oracle"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "per_fold_auroc"}, indent=2))


if __name__ == "__main__":
    main()
