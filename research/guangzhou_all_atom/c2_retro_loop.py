#!/usr/bin/env python3
"""C2 — retrospective closed-loop LEARNING on REAL measured affinity (self-contained).

Question (program moat claim): does the closed loop LEARN — does model-guided acquisition that
RETRAINS each round find high-affinity cyclic peptides faster than (a) RANDOM (no learning) and
(b) a FIXED (never-updated) model? And does the LEARN>RANDOM margin SURVIVE a cluster-disjoint
cut (genuine SAR generalization, not analog hit-expansion)?

Within-target active learning; oracle = measured pAff (NON-circular; not display enrichment).
Runs LEAN from a staged npz (fp + desc + pAff + target + flags) — no CSV/rdkit/pandas needed,
only numpy/scikit-learn/scipy. Designed to run on a clean spot CPU box (local contention makes a
single HistGBM fit take ~230s; a clean box is ~1s). Fail-loud; fresh results only.
"""
import json, os, sys, time
import numpy as np

STAGE = os.environ.get("C2_STAGE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "results/c2_staged.npz"))
OUT = os.environ.get("C2_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "results/c2_retro_loop.json"))

N_MIN = 60        # min compounds/target
MAX_POOL = 600    # cap per-target pool (subsample) so clustering+sim stay fast
N_SEED = 5
BATCH = 5
N_ROUNDS = 12
N_BG = 3000
SEEDS = 6
HIT_Q = 0.80      # top-20% pAff within target = hits
TAN_THR = 0.5     # Tanimoto cluster threshold
MAX_TARGETS = 10


def model():
    from sklearn.ensemble import HistGradientBoostingRegressor
    return HistGradientBoostingRegressor(max_iter=200, learning_rate=0.06, max_depth=8,
                                         l2_regularization=1.0, random_state=0)


def tanimoto_clusters(fp_bits):
    n = len(fp_bits); b = fp_bits > 0
    card = b.sum(1).astype(np.float32)
    assigned = -np.ones(n, int); cid = 0
    for i in np.argsort(-card):
        if assigned[i] >= 0:
            continue
        inter = (b & b[i]).sum(1).astype(np.float32)
        tani = inter / (card + card[i] - inter + 1e-9)
        members = np.where((tani >= TAN_THR) & (assigned < 0))[0]
        assigned[members] = cid; cid += 1
    return assigned


def sim_one(Xbg, ybg, Xt, yt, hit_mask, clusters, mode, seed):
    """Returns (hits[], novelcluster_hits[]) cumulative over steps 0..N_ROUNDS.
    novelcluster_hits = hits whose Tanimoto cluster was NOT present in the initial seed set
    (genuine beyond-seed-chemotype discovery -> the analog-leakage-safe signal)."""
    r = np.random.default_rng(seed)
    n = len(yt)
    acq = list(r.choice(n, N_SEED, replace=False))
    seed_cl = set(clusters[acq].tolist())
    pool = [i for i in range(n) if i not in set(acq)]

    def novel_hits(idxs):
        return int(sum(1 for i in idxs if hit_mask[i] and clusters[i] not in seed_cl))

    hits = [int(hit_mask[acq].sum())]; nov = [novel_hits(acq)]
    fixed_m = model().fit(np.vstack([Xbg, Xt[acq]]), np.concatenate([ybg, yt[acq]])) if mode == "fixed" else None
    for _ in range(N_ROUNDS):
        if not pool:
            hits.append(hits[-1]); nov.append(nov[-1]); continue
        if mode == "random":
            pick = list(r.choice(pool, min(BATCH, len(pool)), replace=False))
        else:
            m = (model().fit(np.vstack([Xbg, Xt[acq]]), np.concatenate([ybg, yt[acq]]))
                 if mode == "learn" else fixed_m)
            pick = [pool[j] for j in np.argsort(-m.predict(Xt[pool]))[:BATCH]]
        acq += pick; ps = set(pick); pool = [i for i in pool if i not in ps]
        hits.append(int(hit_mask[acq].sum())); nov.append(novel_hits(acq))
    return np.array(hits, float), np.array(nov, float)


def agg(mat):
    mat = np.vstack(mat)
    return {"mean": mat.mean(0).round(4).tolist(), "sem": (mat.std(0) / np.sqrt(len(mat))).round(4).tolist()}


def main():
    t0 = time.time()
    print(f"C2_START {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} stage={STAGE}", flush=True)
    z = np.load(STAGE, allow_pickle=True)
    fp = z["fp"].astype(np.float32); desc = z["desc"].astype(np.float32)
    y = z["pAff"].astype(np.float32); tgt = z["target"].astype(str)
    X = np.nan_to_num(np.hstack([fp, desc]), nan=0.0, posinf=0.0, neginf=0.0)
    print(f"loaded {len(y)} cyclic rows, X {X.shape} ({time.time()-t0:.0f}s)", flush=True)

    counts = {t: int((tgt == t).sum()) for t in set(tgt) if t}
    sel = sorted([t for t, c in counts.items() if c >= N_MIN], key=lambda t: -counts[t])
    for flag in ("is_avb6", "is_pdl1"):
        if flag in z.files:
            for t in set(tgt[z[flag].astype(bool)]):
                if t and counts.get(t, 0) >= N_MIN and t not in sel:
                    sel.append(t)
    sel = sel[:MAX_TARGETS]
    print(f"targets ({len(sel)}): " + ", ".join(f"{t}:{counts[t]}" for t in sel), flush=True)

    rng = np.random.default_rng(0)
    modes = ["learn", "fixed", "random"]
    raw = {m: [] for m in modes}; novel = {m: [] for m in modes}; per_target = {}
    for t in sel:
        ti = np.where(tgt == t)[0]
        if len(ti) > MAX_POOL:
            ti = rng.choice(ti, MAX_POOL, replace=False)
        bg = np.where(tgt != t)[0]
        if len(bg) > N_BG:
            bg = rng.choice(bg, N_BG, replace=False)
        Xt, yt, fpt = X[ti], y[ti], fp[ti]
        thr = np.quantile(yt, HIT_Q); hit_mask = yt >= thr; n_hits = int(hit_mask.sum())
        if n_hits < 3:
            print(f"  skip {t}: {n_hits} hits", flush=True); continue
        clusters = tanimoto_clusters(fpt)
        tc = {m: {"raw": [], "nov": []} for m in modes}
        for s in range(SEEDS):
            for m in modes:
                h, nv = sim_one(X[bg], y[bg], Xt, yt, hit_mask, clusters, m, seed=1000 * s + (abs(hash(t)) % 97))
                tc[m]["raw"].append(h / n_hits)
                tc[m]["nov"].append(nv)
        n_novel_possible = int(sum(1 for i in range(len(yt)) if hit_mask[i]))  # upper bound; novel recall reported as count
        for m in modes:
            raw[m].append(np.vstack(tc[m]["raw"]).mean(0))
            novel[m].append(np.vstack(tc[m]["nov"]).mean(0))
        per_target[t] = {"n": int(len(ti)), "n_hits": n_hits, "n_clusters": int(clusters.max() + 1),
                         "raw_final": {m: float(np.vstack(tc[m]["raw"]).mean(0)[-1]) for m in modes},
                         "novel_final": {m: float(np.vstack(tc[m]["nov"]).mean(0)[-1]) for m in modes}}
        print(f"  {t} n={len(ti)} hits={n_hits} clust={clusters.max()+1}: " +
              " ".join(f"{m} raw{per_target[t]['raw_final'][m]:.2f}/nov{per_target[t]['novel_final'][m]:.1f}" for m in modes) +
              f"  ({time.time()-t0:.0f}s)", flush=True)

    budget = [N_SEED + i * BATCH for i in range(N_ROUNDS + 1)]
    out = {"question": "does the closed loop LEARN on real measured affinity, surviving a cluster-disjoint cut?",
           "oracle": "measured pAff (binding_affinity_v1 cyclic) — non-circular (NOT display enrichment)",
           "protocol": f"within-target AL; seed {N_SEED} batch {BATCH} rounds {N_ROUNDS}; bg {N_BG}; pool cap {MAX_POOL}; "
                       f"hit=top-{int((1-HIT_Q)*100)}%; {SEEDS} seeds x targets; LEARN retrains bg+acq/round, FIXED once, RANDOM none; "
                       f"novel=hits in Tanimoto clusters (>={TAN_THR}) NOT in the seed set",
           "budget_tested": budget, "n_targets": len(raw["learn"]),
           "raw_hit_recall": {m: agg(raw[m]) for m in modes},
           "novel_cluster_hits": {m: agg(novel[m]) for m in modes},
           "per_target": per_target}
    # final margins + significance
    from scipy.stats import wilcoxon
    for metric, store in (("raw", raw), ("novel", novel)):
        lf = np.vstack(store["learn"])[:, -1]; rf = np.vstack(store["random"])[:, -1]; ff = np.vstack(store["fixed"])[:, -1]
        def wp(a, b):
            try: return float(wilcoxon(a, b).pvalue)
            except Exception: return float("nan")
        out[f"{metric}_final"] = {"learn": float(lf.mean()), "fixed": float(ff.mean()), "random": float(rf.mean()),
                                  "margin_learn_minus_random": float((lf - rf).mean()), "p_learn_vs_random": wp(lf, rf),
                                  "margin_learn_minus_fixed": float((lf - ff).mean()), "p_learn_vs_fixed": wp(lf, ff)}
        print(f"FINAL[{metric}] learn {lf.mean():.3f} random {rf.mean():.3f} (margin +{(lf-rf).mean():.3f} p={out[f'{metric}_final']['p_learn_vs_random']:.3g}) "
              f"fixed {ff.mean():.3f} [n_tgt={len(lf)}]", flush=True)
    json.dump(out, open(OUT, "w"), indent=2)
    print(f"C2_DONE wrote {OUT} ({time.time()-t0:.0f}s)", flush=True)


if __name__ == "__main__":
    main()
