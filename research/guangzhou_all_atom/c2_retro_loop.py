#!/usr/bin/env python3
"""C2 — retrospective closed-loop LEARNING on REAL measured affinity.

Question (the program's central moat claim): does the closed loop LEARN — i.e. does
model-guided acquisition that RETRAINS each round find high-affinity cyclic peptides
faster than (a) random (no-learning) and (b) a FIXED model that never updates?

Within-target active-learning simulation (the realistic design setting: optimize binders
for ONE target). Oracle = measured pAff (binding_affinity_v1) — the NON-CIRCULAR oracle
(NOT display enrichment; abundance-null does not apply). Reuses the benchmark loader +
cached ECFP+physchem features. CPU only. Honest: LEARN vs FIXED vs RANDOM, CIs over
seeds x targets; reports the learning curves (hit-recall and best-pAff-found vs budget)
and whether the LEARNING (model updating) adds value over a static model and over random.
"""
import json, os, time
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from benchmark_binding_models import load_and_clean, CSV, RESULTS

CACHE = os.path.join(RESULTS, "binding_feature_cache.npz")
ASSAY = ["IC50", "Ki", "EC50", "Kd"]
N_MIN = 60       # min compounds/target to simulate
N_SEED = 5       # initial random labeled set
BATCH = 5        # acquired per round
N_ROUNDS = 10
N_BG = 2500      # background prior subsample
SEEDS = 4
HIT_Q = 0.80     # top-20% pAff within the target = "hits" (hit-finding recall metric)


def model():
    return HistGradientBoostingRegressor(max_iter=200, learning_rate=0.06, max_depth=8,
                                         l2_regularization=1.0, random_state=0)


def sim_one(Xbg, ybg, Xt, yt, hit_mask, mode, seed):
    """mode in {learn, fixed, random}. Returns (hits_found_per_step, bestpaff_per_step)
    over acquisition steps 0..N_ROUNDS (step 0 = the seed set)."""
    r = np.random.default_rng(seed)
    n = len(yt)
    acq = list(r.choice(n, N_SEED, replace=False))
    pool = [i for i in range(n) if i not in set(acq)]
    hits = [int(hit_mask[acq].sum())]
    best = [float(yt[acq].max())]
    fixed_m = None
    if mode == "fixed":
        fixed_m = model().fit(np.vstack([Xbg, Xt[acq]]), np.concatenate([ybg, yt[acq]]))
    for _ in range(N_ROUNDS):
        if not pool:
            hits.append(hits[-1]); best.append(best[-1]); continue
        if mode == "random":
            pick = list(r.choice(pool, min(BATCH, len(pool)), replace=False))
        else:
            m = (model().fit(np.vstack([Xbg, Xt[acq]]), np.concatenate([ybg, yt[acq]]))
                 if mode == "learn" else fixed_m)
            preds = m.predict(Xt[pool])
            pick = [pool[j] for j in np.argsort(-preds)[:BATCH]]
        acq += pick
        ps = set(pick); pool = [i for i in pool if i not in ps]
        hits.append(int(hit_mask[acq].sum()))
        best.append(float(yt[acq].max()))
    return np.array(hits, float), np.array(best, float)


def main():
    t0 = time.time()
    df = load_and_clean(CSV).reset_index(drop=True)
    z = np.load(CACHE, allow_pickle=True)
    assert bool((z["smiles"] == df["smiles"].values).all()), "cache/smiles mismatch"
    fp, desc = z["fp"].astype(np.float32), z["desc"].astype(np.float32)
    mask = df["cyclic_bool"].astype(bool).values
    df = df[mask].reset_index(drop=True); fp, desc = fp[mask], desc[mask]
    onehot = np.zeros((len(df), 4), np.float32)
    for j, a in enumerate(ASSAY):
        onehot[:, j] = (df["affinity_type"].values == a).astype(np.float32)
    X = np.nan_to_num(np.hstack([fp, desc, onehot]), nan=0.0, posinf=0.0, neginf=0.0)
    y = df["pAff"].values.astype(np.float32)
    tgt = df["target_uniprot"].fillna("").astype(str).str.split(",").str[0].values

    counts = {t: int((tgt == t).sum()) for t in set(tgt) if t}
    sel = sorted([t for t, c in counts.items() if c >= N_MIN], key=lambda t: -counts[t])
    # always include avb6 / PD-L1 if they qualify
    for flag in ("is_avb6", "is_pdl1"):
        mm = df[df[flag].astype(bool)]["target_uniprot"].str.split(",").str[0]
        for t in mm.mode().tolist():
            if t and counts.get(t, 0) >= N_MIN and t not in sel:
                sel.append(t)
    sel = sel[:8]
    print(f"targets ({len(sel)}): " + ", ".join(f"{t}:{counts[t]}" for t in sel), flush=True)

    rng = np.random.default_rng(0)
    modes = ["learn", "fixed", "random"]
    # per (target, mode, seed) curves -> stack
    curves = {m: [] for m in modes}       # hit-recall fraction
    bestc = {m: [] for m in modes}        # best pAff found
    per_target = {}
    for t in sel:
        ti = np.where(tgt == t)[0]
        bg = np.where(tgt != t)[0]
        if len(bg) > N_BG:
            bg = rng.choice(bg, N_BG, replace=False)
        Xt, yt = X[ti], y[ti]
        thr = np.quantile(yt, HIT_Q)
        hit_mask = yt >= thr
        n_hits = int(hit_mask.sum())
        if n_hits < 3:
            print(f"  skip {t}: only {n_hits} hits", flush=True); continue
        tgt_curves = {m: {"hit_recall": [], "best": []} for m in modes}
        for s in range(SEEDS):
            for m in modes:
                h, b = sim_one(X[bg], y[bg], Xt, yt, hit_mask, m, seed=1000 * s + hash(t) % 97)
                tgt_curves[m]["hit_recall"].append(h / n_hits)
                tgt_curves[m]["best"].append(b)
        for m in modes:
            hr = np.array(tgt_curves[m]["hit_recall"])      # seeds x steps
            bb = np.array(tgt_curves[m]["best"])
            curves[m].append(hr.mean(0)); bestc[m].append(bb.mean(0))
        per_target[t] = {"n": len(ti), "n_hits": n_hits,
                         "hit_recall_final": {m: float(np.mean([c[-1] for c in [np.array(tgt_curves[m]["hit_recall"]).mean(0)]])) for m in modes}}
        print(f"  {t} n={len(ti)} hits={n_hits}: " +
              " ".join(f"{m}={per_target[t]['hit_recall_final'][m]:.2f}" for m in modes) +
              f"  ({time.time()-t0:.0f}s)", flush=True)

    # aggregate across targets (mean of per-target curves) + CI across targets
    steps = N_ROUNDS + 1
    budget = [N_SEED + i * BATCH for i in range(steps)]
    agg = {}
    for m in modes:
        M = np.vstack(curves[m])          # n_targets x steps
        B = np.vstack(bestc[m])
        agg[m] = {"hit_recall_mean": M.mean(0).round(4).tolist(),
                  "hit_recall_sem": (M.std(0) / np.sqrt(len(M))).round(4).tolist(),
                  "best_paff_mean": B.mean(0).round(3).tolist()}
    # margins at final budget
    lf = np.vstack(curves["learn"])[:, -1]; rf = np.vstack(curves["random"])[:, -1]; ff = np.vstack(curves["fixed"])[:, -1]
    margin_lr = float((lf - rf).mean()); margin_lf = float((lf - ff).mean())
    from scipy.stats import wilcoxon
    try:
        p_lr = float(wilcoxon(lf, rf).pvalue)
    except Exception:
        p_lr = float("nan")
    try:
        p_lf = float(wilcoxon(lf, ff).pvalue)
    except Exception:
        p_lf = float("nan")

    print("\n== AGGREGATE hit-recall vs budget (mean over targets) ==", flush=True)
    for i, bud in enumerate(budget):
        print(f"  tested={bud:3d}  learn {agg['learn']['hit_recall_mean'][i]:.3f}  "
              f"fixed {agg['fixed']['hit_recall_mean'][i]:.3f}  random {agg['random']['hit_recall_mean'][i]:.3f}", flush=True)
    print(f"\nFINAL (budget {budget[-1]}): learn {lf.mean():.3f} vs random {rf.mean():.3f} (margin +{margin_lr:.3f}, p={p_lr:.3g}) "
          f"| vs fixed {ff.mean():.3f} (margin +{margin_lf:.3f}, p={p_lf:.3g})  [n_targets={len(lf)}]", flush=True)

    rep = {"question": "does the closed loop LEARN on real measured affinity (beat no-learning)?",
           "oracle": "measured pAff (binding_affinity_v1 cyclic) — non-circular, NOT display enrichment",
           "protocol": f"within-target active learning; seed {N_SEED}, batch {BATCH}, {N_ROUNDS} rounds, "
                       f"bg prior {N_BG}; hit=top-{int((1-HIT_Q)*100)}% pAff; {SEEDS} seeds x {len(sel)} targets; "
                       "LEARN retrains on bg+acquired each round, FIXED trains once (bg+seed), RANDOM=no model",
           "budget_tested": budget, "aggregate": agg,
           "final_budget": budget[-1],
           "hit_recall_final": {"learn": float(lf.mean()), "fixed": float(ff.mean()), "random": float(rf.mean())},
           "margin_learn_minus_random": margin_lr, "p_learn_vs_random": p_lr,
           "margin_learn_minus_fixed": margin_lf, "p_learn_vs_fixed": p_lf,
           "per_target": per_target, "n_targets": len(lf)}
    out = os.path.join(RESULTS, "c2_retro_loop.json")
    json.dump(rep, open(out, "w"), indent=2)
    print(f"wrote {out}  ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
