"""Property-directed generation via generate-and-select (Phase-2 Bet-1, step 3, tractable form).

The stability predictor is a fingerprint HistGBM — not differentiable through the generator's
latent, so gradient guidance (as used for closure) is not available. The achievable-now form of
property-directed generation is best-of-N selection: generate multiple candidates per target,
score them, keep the best. This shifts the OUTPUT developability distribution toward stable
designs, and is exactly the acquisition step of the DMTA loop.

Here we quantify the selection lift on the existing designs (4 attempts / target): best-of-k vs
random-pick predicted stability, and the best-of-N curve. Honest limit: selecting by the same
predictor we report is proxy, not ground truth — the lift shows the generator produces a
selectable spread of developability; only a wet-lab assay proves real stability. True
differentiable sampler-guidance needs a latent property surrogate (scoped as the next step).
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from sklearn.ensemble import HistGradientBoostingClassifier

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)


def fp(mol):
    return np.asarray(_FP.GetFingerprint(mol), dtype=np.float32) if mol else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train-csv", type=Path, default=ROOT / "data/processed/pepmsnd_stability_folds.csv")
    ap.add_argument("--attempts", type=Path, default=ROOT / "results/cyclic_eval/attempts_none.json")
    ap.add_argument("--out", type=Path, default=ROOT / "results/property_guided_selection.json")
    args = ap.parse_args()

    # train stability ensemble on all non-conflict PepMSND
    X, y = [], []
    for r in csv.DictReader(open(args.train_csv)):
        if r["label_conflict"] == "True":
            continue
        f = fp(Chem.MolFromSmiles(r["canonical_smiles"]))
        if f is not None:
            X.append(f); y.append(int(r["label"]))
    X, y = np.array(X), np.array(y)
    rng = np.random.default_rng(0)
    models = []
    for s in range(10):
        idx = rng.integers(0, len(y), len(y))
        if len(set(y[idx].tolist())) < 2:
            idx = np.arange(len(y))
        m = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.05, max_leaf_nodes=15,
                                           l2_regularization=1.0, random_state=s)
        m.fit(X[idx], y[idx]); models.append(m)
    score = lambda feats: np.vstack([m.predict_proba(feats)[:, 1] for m in models]).mean(0)

    # group designs by target, score
    by_target = defaultdict(list)
    for r in json.load(open(args.attempts)):
        if r.get("status") == "serialized" and r.get("sequence"):
            f = fp(Chem.MolFromSequence(r["sequence"]))
            if f is not None:
                by_target[r["complex_id"]].append(r["sequence"])
    # score all, per target
    tgt_scores = {}
    for t, seqs in by_target.items():
        feats = np.array([fp(Chem.MolFromSequence(s)) for s in seqs])
        tgt_scores[t] = score(feats)

    # best-of-k curve (mean over targets with >=k designs), vs random-pick (mean of the group)
    max_k = max(len(v) for v in tgt_scores.values())
    curve = {}
    rng2 = np.random.default_rng(1)
    for k in range(1, max_k + 1):
        best_vals, rand_vals = [], []
        for t, sc in tgt_scores.items():
            if len(sc) >= k:
                # average best-of-k over random subsets of size k (unbiased)
                trials = [float(np.max(rng2.choice(sc, size=k, replace=False))) for _ in range(50)]
                best_vals.append(float(np.mean(trials)))
                rand_vals.append(float(np.mean(sc)))  # expected single random pick
        curve[str(k)] = {"mean_best_of_k": round(float(np.mean(best_vals)), 4),
                         "mean_random_pick": round(float(np.mean(rand_vals)), 4),
                         "n_targets": len(best_vals)}

    all_sc = np.concatenate(list(tgt_scores.values()))
    report = {
        "n_targets": len(tgt_scores),
        "n_designs": int(len(all_sc)),
        "endpoint": "predicted blood-stability P[stable] (ranking-grade AUROC~0.84)",
        "select_mechanism": "generate-and-select best-of-k per target (no sampler guidance)",
        "best_of_k_curve": curve,
        "lift_best_of_maxk_vs_random": round(
            curve[str(max_k)]["mean_best_of_k"] - curve["1"]["mean_random_pick"], 4),
        "designs_pred_stability_all": {"mean": round(float(all_sc.mean()), 4),
                                       "q90": round(float(np.quantile(all_sc, .9)), 4)},
        "limits": ["proxy: selecting by the same predictor we report (needs wet-lab for ground truth)",
                   "only 4 attempts/target — larger N needs a GPU generation run",
                   "differentiable sampler-guidance needs a latent property surrogate (next step)"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
