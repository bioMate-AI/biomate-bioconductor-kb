#!/usr/bin/env python3
"""C2 — retrospective closed-loop LEARNING on REAL measured affinity (self-contained).

Question (program moat claim): does the closed loop LEARN — does model-guided acquisition that
RETRAINS each round find high-affinity cyclic peptides faster than (a) RANDOM (no learning) and
(b) a FIXED (never-updated) model? And does the LEARN>RANDOM margin SURVIVE a cluster-disjoint
cut (genuine SAR generalization, not analog hit-expansion)?

v2 (all-targets + acquisition sweep): scales from the 10 largest targets to ALL targets with
>= N_MIN measured cyclic rows (env C2_MAX_TARGETS, default 200 -> effectively all ~106), adds
UNCERTAINTY-AWARE acquisition (UCB and Thompson) on top of greedy LEARN, and PARALLELISES the
per-target loop across all vCPUs (each target is independent) so the full sweep fits the spot
self-terminate window. UCB/Thompson use a K-member bootstrap HistGBM ensemble for a per-point
(mean, std); UCB picks mean+kappa*std, Thompson picks top of one N(mean,std) draw.

Within-target active learning; oracle = measured pAff (NON-circular; not display enrichment).
Runs LEAN from a staged npz (fp + desc + pAff + target + flags) — no CSV/rdkit/pandas needed,
only numpy/scikit-learn/scipy. Fail-loud; fresh results only.
"""
import json, os, sys, time, zlib
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed


def _stable_offset(t):
    """Deterministic per-target seed offset (independent of PYTHONHASHSEED / worker process)."""
    return zlib.crc32(t.encode()) % 97

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
MAX_TARGETS = int(os.environ.get("C2_MAX_TARGETS", "200"))   # v2: default = all >= N_MIN
K_ENS = int(os.environ.get("C2_K_ENS", "4"))                 # bootstrap members for UCB/Thompson uncertainty
UCB_KAPPA = float(os.environ.get("C2_UCB_KAPPA", "1.0"))
N_WORKERS = int(os.environ.get("C2_WORKERS", str(os.cpu_count() or 4)))
MODES = ["learn", "fixed", "random", "ucb", "thompson"]


def model(seed=0):
    from sklearn.ensemble import HistGradientBoostingRegressor
    return HistGradientBoostingRegressor(max_iter=200, learning_rate=0.06, max_depth=8,
                                         l2_regularization=1.0, random_state=seed)


def _ensemble_mean_std(Xtr, ytr, Xq, rng):
    """K bootstrap-resampled HistGBMs -> (mean, std) prediction over Xq."""
    n = len(ytr)
    preds = np.empty((K_ENS, len(Xq)), float)
    for k in range(K_ENS):
        bi = rng.integers(0, n, n)                       # bootstrap resample
        preds[k] = model(seed=k).fit(Xtr[bi], ytr[bi]).predict(Xq)
    return preds.mean(0), preds.std(0)


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
        elif mode in ("learn", "fixed"):
            m = (model().fit(np.vstack([Xbg, Xt[acq]]), np.concatenate([ybg, yt[acq]]))
                 if mode == "learn" else fixed_m)
            pick = [pool[j] for j in np.argsort(-m.predict(Xt[pool]))[:BATCH]]
        else:  # uncertainty-aware: ucb / thompson (retrain ensemble each round)
            Xtr = np.vstack([Xbg, Xt[acq]]); ytr = np.concatenate([ybg, yt[acq]])
            mu, sd = _ensemble_mean_std(Xtr, ytr, Xt[pool], r)
            score = mu + UCB_KAPPA * sd if mode == "ucb" else r.normal(mu, sd)
            pick = [pool[j] for j in np.argsort(-score)[:BATCH]]
        acq += pick; ps = set(pick); pool = [i for i in pool if i not in ps]
        hits.append(int(hit_mask[acq].sum())); nov.append(novel_hits(acq))
    return np.array(hits, float), np.array(nov, float)


def run_target(args):
    """Full per-target simulation across all seeds x modes. Parallel-safe (pure numpy/sklearn)."""
    t, Xt, yt, fpt, Xbg, ybg = args
    thr = np.quantile(yt, HIT_Q); hit_mask = yt >= thr; n_hits = int(hit_mask.sum())
    if n_hits < 3:
        return t, None, f"skip {t}: {n_hits} hits"
    clusters = tanimoto_clusters(fpt)
    tc = {m: {"raw": [], "nov": []} for m in MODES}
    for s in range(SEEDS):
        for m in MODES:
            h, nv = sim_one(Xbg, ybg, Xt, yt, hit_mask, clusters, m, seed=1000 * s + _stable_offset(t))
            tc[m]["raw"].append(h / n_hits)
            tc[m]["nov"].append(nv)
    raw = {m: np.vstack(tc[m]["raw"]).mean(0) for m in MODES}
    nov = {m: np.vstack(tc[m]["nov"]).mean(0) for m in MODES}
    meta = {"n": int(len(yt)), "n_hits": n_hits, "n_clusters": int(clusters.max() + 1),
            "raw_final": {m: float(raw[m][-1]) for m in MODES},
            "novel_final": {m: float(nov[m][-1]) for m in MODES}}
    line = (f"  {t} n={len(yt)} hits={n_hits} clust={clusters.max()+1}: " +
            " ".join(f"{m} raw{meta['raw_final'][m]:.2f}/nov{meta['novel_final'][m]:.1f}" for m in MODES))
    return t, {"raw": {m: raw[m] for m in MODES}, "nov": {m: nov[m] for m in MODES}, "meta": meta}, line


def agg(mat):
    mat = np.vstack(mat)
    return {"mean": mat.mean(0).round(4).tolist(), "sem": (mat.std(0) / np.sqrt(len(mat))).round(4).tolist()}


def main():
    t0 = time.time()
    print(f"C2_START {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} stage={STAGE} "
          f"max_targets={MAX_TARGETS} K_ens={K_ENS} workers={N_WORKERS} modes={MODES}", flush=True)
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
    print(f"targets ({len(sel)}) >= {N_MIN} rows; largest: " +
          ", ".join(f"{t}:{counts[t]}" for t in sel[:12]) + (" ..." if len(sel) > 12 else ""), flush=True)

    # build independent per-target work items (each carries its own bg subsample for reproducibility)
    rng = np.random.default_rng(0)
    work = []
    for t in sel:
        ti = np.where(tgt == t)[0]
        if len(ti) > MAX_POOL:
            ti = rng.choice(ti, MAX_POOL, replace=False)
        bg = np.where(tgt != t)[0]
        if len(bg) > N_BG:
            bg = rng.choice(bg, N_BG, replace=False)
        work.append((t, X[ti], y[ti], fp[ti], X[bg], y[bg]))

    raw = {m: [] for m in MODES}; novel = {m: [] for m in MODES}; per_target = {}
    done = 0
    with ProcessPoolExecutor(max_workers=N_WORKERS) as ex:
        futs = {ex.submit(run_target, w): w[0] for w in work}
        for fut in as_completed(futs):
            t, res, line = fut.result()
            done += 1
            print(f"[{done}/{len(work)}] {line}  ({time.time()-t0:.0f}s)", flush=True)
            if res is None:
                continue
            for m in MODES:
                raw[m].append(res["raw"][m]); novel[m].append(res["nov"][m])
            per_target[t] = res["meta"]

    budget = [N_SEED + i * BATCH for i in range(N_ROUNDS + 1)]
    out = {"question": "does the closed loop LEARN on real measured affinity, surviving a cluster-disjoint cut? "
                       "(v2: all targets + UCB/Thompson acquisition)",
           "oracle": "measured pAff (binding_affinity_v1 cyclic) — non-circular (NOT display enrichment)",
           "protocol": f"within-target AL; seed {N_SEED} batch {BATCH} rounds {N_ROUNDS}; bg {N_BG}; pool cap {MAX_POOL}; "
                       f"hit=top-{int((1-HIT_Q)*100)}%; {SEEDS} seeds x targets; LEARN/UCB/THOMPSON retrain each round "
                       f"(UCB/Thompson: {K_ENS}-member bootstrap ensemble, kappa={UCB_KAPPA}), FIXED once, RANDOM none; "
                       f"novel=hits in Tanimoto clusters (>={TAN_THR}) NOT in the seed set",
           "budget_tested": budget, "n_targets": len(raw["learn"]), "modes": MODES,
           "raw_hit_recall": {m: agg(raw[m]) for m in MODES},
           "novel_cluster_hits": {m: agg(novel[m]) for m in MODES},
           "per_target": per_target}
    # final margins + significance (each learning mode vs RANDOM and vs FIXED)
    from scipy.stats import wilcoxon
    def wp(a, b):
        try: return float(wilcoxon(a, b).pvalue)
        except Exception: return float("nan")
    for metric, store in (("raw", raw), ("novel", novel)):
        fin = {m: np.vstack(store[m])[:, -1] for m in MODES}
        rf = fin["random"]; ff = fin["fixed"]
        summ = {"random": float(rf.mean()), "fixed": float(ff.mean())}
        for m in ("learn", "ucb", "thompson"):
            summ[m] = {"mean": float(fin[m].mean()),
                       "margin_vs_random": float((fin[m] - rf).mean()), "p_vs_random": wp(fin[m], rf),
                       "margin_vs_fixed": float((fin[m] - ff).mean()), "p_vs_fixed": wp(fin[m], ff)}
        out[f"{metric}_final"] = summ
        print(f"FINAL[{metric}] random {rf.mean():.3f} fixed {ff.mean():.3f} | " +
              " ".join(f"{m} {summ[m]['mean']:.3f}(+{summ[m]['margin_vs_random']:.3f} p={summ[m]['p_vs_random']:.3g})"
                       for m in ("learn", "ucb", "thompson")) + f"  [n_tgt={len(rf)}]", flush=True)
    json.dump(out, open(OUT, "w"), indent=2)
    print(f"C2_DONE wrote {OUT} ({time.time()-t0:.0f}s)", flush=True)


if __name__ == "__main__":
    main()
