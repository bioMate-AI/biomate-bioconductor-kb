"""Developability-scored generation (Phase-2 Bet-1, step 2): score the cyclic generator's designs
with the stability predictor + uncertainty, and rank. The in-silico generate -> verify loop.

Takes generated peptide sequences (from generate_validation attempts.json), builds peptide mols,
scores predicted blood-stability (bootstrap-bagged HistGBM ensemble trained on PepMSND leak-free
data) with epistemic uncertainty, and reports the developability distribution + top candidates.

Honest limits: designs are scored as LINEAR peptide SMILES (RDKit MolFromSequence) — an
approximation, since the generator's macrocyclic closure is not yet achieved; the stability model
is ranking-grade (AUROC ~0.84 leak-free), not a calibrated clinical oracle. Permeability scoring
is deferred (its model uses a different, CycPeptMPDB-descriptor featurization).
"""
import argparse
import csv
import json
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import HistGradientBoostingClassifier

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)


def fp_from_smiles(smi):
    m = Chem.MolFromSmiles(smi)
    return np.asarray(_FP.GetFingerprint(m), dtype=np.float32) if m else None


def fp_from_seq(seq):
    m = Chem.MolFromSequence(seq)
    return np.asarray(_FP.GetFingerprint(m), dtype=np.float32) if m else None


def train_ensemble(X, y, n=10, seed=0):
    rng = np.random.default_rng(seed)
    models = []
    for s in range(n):
        idx = rng.integers(0, len(y), len(y))
        if len(set(y[idx].tolist())) < 2:
            idx = np.arange(len(y))
        m = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.05, max_leaf_nodes=15,
                                           l2_regularization=1.0, random_state=s)
        m.fit(X[idx], y[idx]); models.append(m)
    return models


def predict(models, X):
    p = np.vstack([m.predict_proba(X)[:, 1] for m in models])
    return p.mean(0), p.std(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train-csv", type=Path, default=ROOT / "data/processed/pepmsnd_stability_folds.csv")
    ap.add_argument("--attempts", type=Path, default=ROOT / "results/cyclic_eval/attempts_none.json")
    ap.add_argument("--out", type=Path, default=ROOT / "results/generation_developability.json")
    args = ap.parse_args()

    # train stability model on all non-conflict PepMSND
    Xtr, ytr = [], []
    for r in csv.DictReader(open(args.train_csv)):
        if r["label_conflict"] == "True":
            continue
        f = fp_from_smiles(r["canonical_smiles"])
        if f is not None:
            Xtr.append(f); ytr.append(int(r["label"]))
    Xtr, ytr = np.array(Xtr), np.array(ytr)
    models = train_ensemble(Xtr, ytr)
    ref_p, _ = predict(models, Xtr)  # predicted-stability distribution of the reference set

    # score generated designs
    attempts = json.load(open(args.attempts))
    designs = [r for r in attempts if r.get("status") == "serialized" and r.get("sequence")]
    seqs = [r["sequence"] for r in designs]
    feats, kept = [], []
    for i, s in enumerate(seqs):
        f = fp_from_seq(s)
        if f is not None:
            feats.append(f); kept.append(i)
    Xg = np.array(feats)
    pg, ug = predict(models, Xg)

    order = np.argsort(-pg)
    top = [{"sequence": seqs[kept[j]], "pred_stability": round(float(pg[j]), 3),
            "uncertainty": round(float(ug[j]), 3), "length": len(seqs[kept[j]])} for j in order[:10]]

    def q(a, x):
        return round(float(np.quantile(a, x)), 3)
    report = {
        "n_designs_scored": len(kept),
        "train_n": int(len(ytr)), "train_pos_rate": round(float(ytr.mean()), 3),
        "endpoint": "predicted blood-stability (P[stable]); ranking-grade AUROC~0.84 leak-free",
        "designs_pred_stability": {"mean": round(float(pg.mean()), 3),
                                   "q10": q(pg, .1), "median": q(pg, .5), "q90": q(pg, .9)},
        "reference_pred_stability": {"mean": round(float(ref_p.mean()), 3),
                                     "median": q(ref_p, .5)},
        "frac_designs_pred_stable(>0.5)": round(float((pg > 0.5).mean()), 3),
        "mean_uncertainty": round(float(ug.mean()), 3),
        "top10_designs": top,
        "limits": ["designs scored as LINEAR peptide SMILES (macrocyclic closure not achieved) — "
                   "an approximation; permeability deferred (different featurization); "
                   "ranking-grade model, not a calibrated oracle; no wet-lab validation"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "top10_designs"}, indent=2))
    print("top design:", top[0])


if __name__ == "__main__":
    main()
