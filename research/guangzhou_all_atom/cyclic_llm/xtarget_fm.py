"""xtarget_fm.py — the decisive cheap test of the new plan's core hypothesis:

Do SOTA foundation-model representations (ChemBERTa ligand + ESM target) break the CROSS-TARGET wall that the
sequence-composition approach hit (v3.1 NULL: 'target_features_matter: false')? This is the unsolved SOTA
problem (cross-target cyclic ~3-8%). Uses only PRECOMPUTED embeddings (CPU, no GPU).

Protocol — LEAVE-TARGETS-OUT (not leave-peptides-out): whole targets held out, so the test is genuine
cross-target generalization. Metric = mean per-HELD-OUT-target Spearman (can the model rank that unseen
target's binders?). Conditions:
  A. ligand-only (ChemBERTa)          — target-agnostic floor
  B. ligand + ESM target              — does protein-FM target conditioning TRANSFER to unseen targets?
If B >> A on held-out targets, FM/structure representation carries transferable cross-target signal — the
ceiling-break the plan bets on. If B ~ A, the wall is deeper than representation (honest).
"""
import os, numpy as np
from collections import defaultdict
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import GroupKFold

R = os.environ.get("XRES", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results"))
N_MIN = 60


def main():
    lig = np.load(os.path.join(R, "chemberta_emb_cyclic.npz"), allow_pickle=True)
    stg = np.load(os.path.join(R, "c2_staged.npz"), allow_pickle=True)
    esm = np.load(os.path.join(R, "target_esm_emb.npz"), allow_pickle=True)
    L = lig["emb"].astype(np.float32)                      # (28875, 384) ChemBERTa
    y = stg["pAff"].astype(np.float32); tgt = stg["target"].astype(str)
    assert len(L) == len(y), f"ligand/label misalignment {len(L)} vs {len(y)}"
    esm_map = {a: e for a, e in zip(esm["accs"].astype(str), esm["emb"].astype(np.float32))}
    T = np.array([esm_map.get(t, np.zeros(esm["emb"].shape[1], np.float32)) for t in tgt])  # (N, 480)
    has_esm = np.array([t in esm_map for t in tgt])

    # evaluable targets: >= N_MIN peptides AND an ESM embedding
    cnt = defaultdict(int)
    for t in tgt: cnt[t] += 1
    keep = np.array([has_esm[i] and cnt[tgt[i]] >= N_MIN for i in range(len(y))])
    L, T, y, tgt = L[keep], T[keep], y[keep], tgt[keep]
    utgt = sorted(set(tgt))
    print(f"evaluable: {len(y)} peptides across {len(utgt)} targets (>= {N_MIN} rows + ESM)", flush=True)

    groups = tgt
    gkf = GroupKFold(n_splits=5)
    conds = {"A. ligand-only (ChemBERTa)": L, "B. ligand + ESM-target": np.hstack([L, T])}

    def per_target_spearman(y_true, y_pred, tg, held):
        rs = []
        for t in set(tg[held]):
            m = held & (tg == t)
            if m.sum() >= 10 and np.std(y_true[m]) > 1e-6:
                r = spearmanr(y_true[m], y_pred[m]).correlation
                if np.isfinite(r): rs.append(r)
        return rs

    results = {}
    for name, X in conds.items():
        X = np.nan_to_num(X)
        oof = np.full(len(y), np.nan); per = []
        for tr, te in gkf.split(X, y, groups):
            held = np.zeros(len(y), bool); held[te] = True
            m = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.05, max_depth=8, random_state=0)
            m.fit(X[tr], y[tr]); oof[te] = m.predict(X[te])
            per += per_target_spearman(y, oof, tgt, held)
        per = np.array(per)
        results[name] = {"mean_per_target_spearman": round(float(per.mean()), 4),
                         "sem": round(float(per.std(ddof=1) / np.sqrt(len(per))), 4),
                         "n_targets_scored": len(per), "frac_positive": round(float((per > 0).mean()), 3)}
        print(f"{name:28s} cross-target Spearman={results[name]['mean_per_target_spearman']:+.3f} "
              f"±{results[name]['sem']:.3f}  (n_tgt={len(per)}, frac>0={results[name]['frac_positive']})", flush=True)

    a = results["A. ligand-only (ChemBERTa)"]["mean_per_target_spearman"]
    b = results["B. ligand + ESM-target"]["mean_per_target_spearman"]
    verdict = ("ESM TARGET CONDITIONING TRANSFERS (B>A): FM/structure reps carry cross-target signal — ceiling-break candidate"
               if b - a > 0.03 else
               "no transfer (B~A): cross-target wall is deeper than representation — honest NULL, informs GPU/structure phases")
    import json
    json.dump({"what": "cross-target affinity via FM reps (ChemBERTa ligand + ESM target), leave-TARGETS-out",
               "sota_context": "cross-target cyclic ~3-8% (unsolved); v3.1 composition-target was NULL",
               "results": results, "delta_B_minus_A": round(b - a, 4), "verdict": verdict},
              open(os.path.join(R, "xtarget_fm.json"), "w"), indent=2)
    print(f"\nΔ(B−A) = {b-a:+.4f}\nVERDICT: {verdict}\nwrote results/xtarget_fm.json")


if __name__ == "__main__":
    main()
