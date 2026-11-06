"""Multi-property developability selection (Phase-2 Bet-1): score generated cyclic designs on BOTH
permeability (log Papp regressor) and stability (classifier), and report the jointly-developable
set + a combined-rank top-k. Realistic screen: a useful peptide must be both permeable and stable.

Honest weighting: stability is reliable (AUROC ~0.84 leak-free); permeability is ranking-grade
(scaffold-R2 ~0.23), so the permeability axis is noisy — reported, not trusted as precise. All
lifts are predicted (select-by-model); wet lab is the missing ground truth.
"""
import argparse
import csv
import json
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
PERM_CUTOFF = -6.0  # log Papp > -6 ~ "permeable" (common PAMPA threshold)


def fp(mol):
    return np.asarray(_FP.GetFingerprint(mol), dtype=np.float32) if mol else None


def train_stability(csv_path, n=10, seed=0):
    X, y = [], []
    for r in csv.DictReader(open(csv_path)):
        if r["label_conflict"] == "True":
            continue
        f = fp(Chem.MolFromSmiles(r["canonical_smiles"]))
        if f is not None:
            X.append(f); y.append(int(r["label"]))
    X, y = np.array(X), np.array(y)
    rng = np.random.default_rng(seed); models = []
    for s in range(n):
        idx = rng.integers(0, len(y), len(y))
        if len(set(y[idx].tolist())) < 2:
            idx = np.arange(len(y))
        m = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.05, max_leaf_nodes=15,
                                           l2_regularization=1.0, random_state=s)
        m.fit(X[idx], y[idx]); models.append(m)
    return lambda F: np.vstack([m.predict_proba(F)[:, 1] for m in models]).mean(0)


def train_permeability(csv_path, n=5, seed=0):
    X, y = [], []
    for r in csv.DictReader(open(csv_path)):
        try:
            p = float(r.get("Permeability", ""))
        except (TypeError, ValueError):
            continue
        if not (-10.5 < p < -3.5):
            continue
        m = Chem.MolFromSmiles(r.get("SMILES", "").strip())
        f = fp(m)
        if f is not None:
            X.append(f); y.append(p)
    X, y = np.array(X), np.array(y)
    rng = np.random.default_rng(seed); models = []
    for s in range(n):
        idx = rng.integers(0, len(y), len(y))
        r = HistGradientBoostingRegressor(max_iter=150, learning_rate=0.06, max_leaf_nodes=31,
                                          l2_regularization=1.0, random_state=s)
        r.fit(X[idx], y[idx]); models.append(r)
    return lambda F: np.vstack([m.predict(F) for m in models]).mean(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stab-csv", type=Path, default=ROOT / "data/processed/pepmsnd_stability_folds.csv")
    ap.add_argument("--perm-csv", type=Path, default=ROOT / "data/raw/CycPeptMPDB_Peptide_All.csv")
    ap.add_argument("--attempts", type=Path, default=ROOT / "results/cyclic_eval/attempts_none_n16.json")
    ap.add_argument("--out", type=Path, default=ROOT / "results/multi_property_selection.json")
    args = ap.parse_args()

    stab = train_stability(args.stab_csv)
    perm = train_permeability(args.perm_csv)

    seqs = [r["sequence"] for r in json.load(open(args.attempts))
            if r.get("status") == "serialized" and r.get("sequence")]
    feats, kept = [], []
    for s in seqs:
        f = fp(Chem.MolFromSequence(s))
        if f is not None:
            feats.append(f); kept.append(s)
    F = np.array(feats)
    ps = stab(F)            # P(stable)
    pp = perm(F)            # log Papp (higher = more permeable)

    stable = ps > 0.5
    permeable = pp > PERM_CUTOFF
    dual = stable & permeable
    # combined rank score (rank-normalized sum of both, equal weight)
    rank_s = ps.argsort().argsort() / len(ps)
    rank_p = pp.argsort().argsort() / len(pp)
    combined = rank_s + rank_p
    order = np.argsort(-combined)
    top = [{"sequence": kept[j], "pred_stability": round(float(ps[j]), 3),
            "pred_logPapp": round(float(pp[j]), 3)} for j in order[:10]]

    report = {
        "n_designs": len(kept),
        "perm_cutoff_logPapp": PERM_CUTOFF,
        "endpoints": {"stability": "P(stable), AUROC~0.84 (reliable)",
                      "permeability": "log Papp, scaffold-R2~0.23 (ranking-grade / noisy)"},
        "frac_pred_stable": round(float(stable.mean()), 3),
        "frac_pred_permeable": round(float(permeable.mean()), 3),
        "frac_dual_developable": round(float(dual.mean()), 3),
        "n_dual_developable": int(dual.sum()),
        "pred_logPapp": {"mean": round(float(pp.mean()), 3),
                         "q90": round(float(np.quantile(pp, .9)), 3)},
        "pred_stability": {"mean": round(float(ps.mean()), 3),
                           "q90": round(float(np.quantile(ps, .9)), 3)},
        "top10_combined": top,
        "limits": ["permeability is ranking-grade (R2~0.23) — the joint screen is dominated by the "
                   "reliable stability axis; permeability adds noisy signal",
                   "select-by-model proxy; wet lab is the missing ground truth",
                   "designs scored as linear peptide SMILES (macrocyclic closure not achieved)"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "top10_combined"}, indent=2))
    print("top dual candidate:", top[0])


if __name__ == "__main__":
    main()
