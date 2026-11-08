#!/usr/bin/env python3
"""LEVER — clean FEW-SHOT sweep: the realistic regime (train on all OTHER targets + k shots
of the held-out target; eval on remaining held-out-target compounds). Does the model become
STRONG at a realistic k, and does the gain survive removing ANALOG leakage?

CRITICAL: the k shots and the eval compounds are ANALOG-DISJOINT (clustered by ECFP Tanimoto;
shots from some clusters, eval from others) — so "strong at k" is genuine within-target
generalization, not memorizing near-duplicates. The naive (random, analog-leaky) curve is
reported alongside; the gap = the honest cost of the leakage the random-split 0.71 hid.
ECFP+physchem features, HistGBM (fast; ~ the 0.42 RF baseline). CPU only, no spend.
"""
import json, os, time
import numpy as np
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor
from benchmark_binding_models import load_and_clean, CSV, RESULTS

LIG_CACHE = os.path.join(RESULTS, "binding_feature_cache.npz")
ASSAY = ["IC50", "Ki", "EC50", "Kd"]
KS = [0, 5, 10, 20, 50]
N_BG = 6000          # background subsample (speed)
REPEATS = 3
TANIMOTO_THR = 0.5   # cluster compounds >= this similarity together
rng = np.random.default_rng(0)


def tanimoto_clusters(fp):
    """Greedy ECFP-Tanimoto clustering of one target's compounds (fp: n x 2048 bits)."""
    n = len(fp); b = (fp > 0)
    card = b.sum(1).astype(np.float32)
    assigned = -np.ones(n, int); cid = 0
    order = np.argsort(-card)  # seed from largest
    for i in order:
        if assigned[i] >= 0:
            continue
        inter = (b & b[i]).sum(1).astype(np.float32)
        tani = inter / (card + card[i] - inter + 1e-9)
        members = np.where((tani >= TANIMOTO_THR) & (assigned < 0))[0]
        assigned[members] = cid; cid += 1
    return assigned


def model():
    return HistGradientBoostingRegressor(max_iter=200, learning_rate=0.06, max_depth=8,
                                         l2_regularization=1.0, random_state=0)


def spear(y, p):
    return float(spearmanr(y, p).correlation) if len(y) > 2 and np.std(p) > 0 else float("nan")


def run_target(Xbg, ybg, Xt, yt, clusters):
    """Return {k: {clean:[spearmans], leaky:[spearmans]}} for this held-out target."""
    out = {}
    ncl = clusters.max() + 1
    for k in KS:
        clean, leaky = [], []
        for r in range(REPEATS if k > 0 else 1):
            # ---- clean: shots vs eval from DISJOINT clusters ----
            cl_order = rng.permutation(ncl)
            shots, i = [], 0
            while len(shots) < k and i < ncl:
                shots += list(np.where(clusters == cl_order[i])[0]); i += 1
            shots = shots[:k]
            shot_cl = set(clusters[shots].tolist()) if shots else set()
            eval_idx = np.array([j for j in range(len(yt)) if clusters[j] not in shot_cl])
            if k == 0:
                eval_idx = np.arange(len(yt))
            if len(eval_idx) >= 8:
                Xtr = np.vstack([Xbg] + ([Xt[shots]] if shots else []))
                ytr = np.concatenate([ybg] + ([yt[shots]] if shots else []))
                m = model().fit(Xtr, ytr)
                clean.append(spear(yt[eval_idx], m.predict(Xt[eval_idx])))
            # ---- leaky: random shots vs remaining (analog near-dups may span both) ----
            if k > 0:
                perm = rng.permutation(len(yt)); sh = perm[:k]; ev = perm[k:]
                if len(ev) >= 8:
                    Xtr = np.vstack([Xbg, Xt[sh]]); ytr = np.concatenate([ybg, yt[sh]])
                    m = model().fit(Xtr, ytr)
                    leaky.append(spear(yt[ev], m.predict(Xt[ev])))
            else:
                leaky = clean[:]  # k=0 identical
        out[k] = {"clean": clean, "leaky": leaky}
    return out


def agg(vals):
    v = np.array([x for x in vals if x == x])
    return {"mean": float(v.mean()) if len(v) else float("nan"),
            "std": float(v.std()) if len(v) else float("nan"), "n": int(len(v))}


def main():
    t0 = time.time()
    df = load_and_clean(CSV).reset_index(drop=True)
    z = np.load(LIG_CACHE, allow_pickle=True); assert bool((z["smiles"] == df["smiles"].values).all())
    fp, desc = z["fp"].astype(np.float32), z["desc"].astype(np.float32)
    mask = df["cyclic_bool"].astype(bool).values
    df = df[mask].reset_index(drop=True); fp, desc = fp[mask], desc[mask]
    onehot = np.zeros((len(df), 4), np.float32)
    for j, a in enumerate(ASSAY):
        onehot[:, j] = (df["affinity_type"].values == a).astype(np.float32)
    X = np.nan_to_num(np.hstack([fp, desc, onehot]), nan=0.0, posinf=0.0, neginf=0.0)
    y = df["pAff"].values.astype(np.float32)
    tgt = df["target_uniprot"].fillna("").astype(str).str.split(",").str[0].values

    # select held-out targets: enough compounds for k=20+eval; always include avb6/PD-L1
    counts = {t: int((tgt == t).sum()) for t in set(tgt) if t}
    big = sorted([t for t, c in counts.items() if c >= 45], key=lambda t: -counts[t])
    pdl1 = df[df["is_pdl1"].astype(bool)]["target_uniprot"].str.split(",").str[0].mode()
    avb6 = df[df["is_avb6"].astype(bool)]["target_uniprot"].str.split(",").str[0].mode()
    sel = []
    for t in list(avb6) + list(pdl1):
        if t and t not in sel and counts.get(t, 0) >= 30: sel.append(t)
    for t in big:
        if len(sel) >= 10: break
        if t not in sel: sel.append(t)
    print(f"held-out targets ({len(sel)}): " + ", ".join(f"{t}:{counts[t]}" for t in sel), flush=True)

    per_target = {}
    for t in sel:
        ti = np.where(tgt == t)[0]
        bg = np.where(tgt != t)[0]
        if len(bg) > N_BG: bg = rng.choice(bg, N_BG, replace=False)
        clusters = tanimoto_clusters(fp[ti])
        res = run_target(X[bg], y[bg], X[ti], y[ti], clusters)
        per_target[t] = {"n": len(ti), "n_clusters": int(clusters.max() + 1),
                         "by_k": {k: {"clean": agg(v["clean"]), "leaky": agg(v["leaky"])} for k, v in res.items()}}
        print(f"  {t} n={len(ti)} clusters={clusters.max()+1}: " +
              " ".join(f"k{k}[c{per_target[t]['by_k'][k]['clean']['mean']:.2f}/l{per_target[t]['by_k'][k]['leaky']['mean']:.2f}]" for k in KS) +
              f"  ({time.time()-t0:.0f}s)", flush=True)

    # aggregate curve across targets
    curve = {}
    for k in KS:
        cm = [per_target[t]["by_k"][k]["clean"]["mean"] for t in sel if per_target[t]["by_k"][k]["clean"]["mean"] == per_target[t]["by_k"][k]["clean"]["mean"]]
        lm = [per_target[t]["by_k"][k]["leaky"]["mean"] for t in sel if per_target[t]["by_k"][k]["leaky"]["mean"] == per_target[t]["by_k"][k]["leaky"]["mean"]]
        curve[k] = {"clean": agg(cm), "leaky": agg(lm)}
    print("== AGGREGATE clean vs leaky Spearman by k ==", flush=True)
    for k in KS:
        print(f"  k={k:3d}  clean {curve[k]['clean']['mean']:.3f}±{curve[k]['clean']['std']:.3f}  leaky {curve[k]['leaky']['mean']:.3f}±{curve[k]['leaky']['std']:.3f}  (n_targets {curve[k]['clean']['n']})", flush=True)

    rep = {"protocol": "few-shot: train all-other-targets (bg subsample %d) + k shots of held-out; eval remaining held-out compounds; CLEAN=analog-disjoint clusters (Tanimoto>=%.1f) shots/eval; LEAKY=random" % (N_BG, TANIMOTO_THR),
           "model": "HistGBM ECFP+physchem+assay", "ks": KS, "repeats": REPEATS,
           "aggregate": curve, "per_target": per_target,
           "avb6": list(avb6), "pdl1": list(pdl1)}
    mj = os.path.join(RESULTS, "binding_model_benchmark_cyclic.json")
    d = json.load(open(mj)); d["fewshot_sweep"] = rep; json.dump(d, open(mj, "w"), indent=2)
    print(f"appended fewshot_sweep  ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
