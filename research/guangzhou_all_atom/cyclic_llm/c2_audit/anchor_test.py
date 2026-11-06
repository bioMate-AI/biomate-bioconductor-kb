#!/usr/bin/env python3
"""Part B of docs/20261030_C2_RERUN_AND_ANCHOR_TEST.md (pre-registered 074293728): lab-offset anchor calibration, leave-one-source-out.
usage: anchor_test.py anchor_data.npz OUTDIR   (env AT_WORKERS, AT_SEEDS=5, AT_MIN_ROWS=30)
Tasks = held-out source x world in {real, planted, null}. Per task: GBM trained on all other sources with label variants
raw / z (within-source z, reference) / cal_k{3,5} x seeds; metric = within-held-out-source Spearman (offset-invariant) of predictions vs raw labels,
plus pooled-practical metric with the held-out source's anchor-estimated offset added to predictions."""
import json, os, sys, time, collections
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor as H

DATA, OUT = sys.argv[1:3]
SEEDS = int(os.environ.get("AT_SEEDS", "5")); MIN_ROWS = int(os.environ.get("AT_MIN_ROWS", "30")); KS = (3, 5, 10)
WORKERS = int(os.environ.get("AT_WORKERS", str(os.cpu_count() or 4)))
z = np.load(DATA, allow_pickle=True); FP = z["fp"].astype(np.float32); Y = z["y"].astype(np.float64); SRC = z["src"].astype(str); N = len(Y)
ANCH = json.load(open(DATA.replace(".npz", "_anchors.json")))
by_src = collections.defaultdict(list)
for a in ANCH: by_src[a["source"]].append(a)


def zscore_by_source(y, src, min_n=20):
    cnt = collections.Counter(src); grp = np.array([s if cnt[s] >= min_n else "__other__" for s in src]); out = np.zeros(len(y))
    for g in set(grp.tolist()):
        m = grp == g; sd = y[m].std(); out[m] = (y[m] - y[m].mean()) / (sd if sd > 0 else 1.0)
    return out


def estimate_offsets(k, seed, anchors_by_src, y_self=None, y_oth=None):
    """b_s from k seeded anchors per source (needs >= k anchors); returns dict source -> b_s and list of excluded sources."""
    rng = np.random.default_rng(1000 * k + seed); b = {}; excl = []
    for s, lst in sorted(anchors_by_src.items()):
        if len(lst) < k: excl.append(s); continue
        pick = rng.choice(len(lst), k, replace=False)
        b[s] = float(np.mean([(lst[i]["y_self"] if y_self is None else y_self[(s, i)]) - (lst[i]["y_others"] if y_oth is None else y_oth[(s, i)]) for i in pick]))
    return b, excl


def restrict(ab, banned):
    """P-B2: rebuild anchors with partners restricted to sources != banned (the held-out source); drop anchors left without a partner."""
    out = collections.defaultdict(list)
    for s_, lst in ab.items():
        if s_ == banned: continue
        for a in lst:
            keep = {o: v for o, v in a["other_vals"].items() if o != banned}
            if keep: out[s_].append(dict(a, y_others=float(np.mean(list(keep.values()))), other_sources=list(keep), other_vals=keep))
    return out


def world(name, seed=0):
    """Return (labels y, anchors_by_src, true offsets or None)."""
    if name == "real": return Y.copy(), by_src, None
    rng = np.random.default_rng(777); bits = rng.choice(2048, 40, replace=False); w = rng.normal(0, 1, 40)
    g = (FP[:, bits] > 0) @ w; g = (g - g.mean()) / g.std()
    srcs = sorted(set(SRC)); off = {s: (float(rng.normal(0, 1)) if name in ("planted", "planted_full") else 0.0) for s in srcs}
    y = g + np.array([off[s] for s in SRC]) + rng.normal(0, 0.3, N)
    ab = collections.defaultdict(list)
    if name == "planted_full":   # anchors in EVERY source (8 rows each; other-source means from 2 random other sources): tests the method when coverage exists
        for s in srcs:
            rows = np.where(SRC == s)[0]
            for i in rng.choice(rows, min(8, len(rows)), replace=False):
                oth = [x for x in rng.choice([q for q in srcs if q != s], 2, replace=False)]
                ov = {o: float(g[i] + off[o] + rng.normal(0, 0.1)) for o in oth}
                ab[s].append(dict(row=int(i), source=s, y_self=float(y[i]), y_others=float(np.mean(list(ov.values()))), other_sources=list(oth), other_vals=ov))
        return y, ab, off
    for a in ANCH:   # same anchor structure as the real data; synthetic labels for the anchor rows and the other-source mean
        gi = g[a["row"]]; ov = {s: float(gi + off.get(s, 0.0) + rng.normal(0, 0.1)) for s in a["other_sources"]}
        ab[a["source"]].append(dict(row=a["row"], source=a["source"], y_self=float(y[a["row"]]), y_others=float(np.mean(list(ov.values()))), other_sources=a["other_sources"], other_vals=ov))
    return y, ab, off


def fit_pred(ytrain, tr, te):
    return H(max_iter=150, learning_rate=0.1, random_state=0).fit(FP[tr], ytrain[tr]).predict(FP[te])


def task(args):
    h, wname = args
    y, ab, off = world(wname); te = np.where(SRC == h)[0]; tr = np.where(SRC != h)[0]; res = dict(source=h, world=wname, n_test=int(len(te)), variants={})
    sp = lambda p: float(spearmanr(p, y[te])[0]) if np.std(p) > 0 and np.std(y[te]) > 0 else float("nan")
    p_raw = fit_pred(y, tr, te); res["variants"]["raw"] = dict(within=sp(p_raw))
    if wname == "real":
        yz = zscore_by_source(y, SRC); res["variants"]["z"] = dict(within=sp(fit_pred(yz, tr, te)))
    for k in KS:
        if k == 10 and wname != "real": continue
        if wname != "real" and k == 3: continue   # controls at k=5 only
        gains, pooled, rec = [], [], []
        for s in range(SEEDS):
            b, excl = estimate_offsets(k, s, restrict(ab, h))
            if not b: continue
            ycal = y.copy()
            for src_, bb in b.items(): ycal[SRC == src_] -= bb
            p_cal = fit_pred(ycal, tr, te); w = sp(p_cal); gains.append(w - res["variants"]["raw"]["within"])
            ab_h = {h: [dict(a, y_others=float(np.mean(list(kv.values()))), other_vals=kv) for a in ab.get(h, []) for kv in [{o: v for o, v in a["other_vals"].items() if o != h}] if kv]}
            bh, _ = estimate_offsets(k, s, ab_h) if len(ab_h[h]) >= k else ({}, [h])
            if h in bh: pooled.append((p_cal + bh[h], p_raw))
            if off is not None: rec.append(float(np.corrcoef([b[s_] for s_ in b], [off[s_] for s_ in b])[0, 1]) if len(b) > 2 else float("nan"))
        res["variants"][f"cal_k{k}"] = dict(n_cal_sources=len(b) if gains else 0, gain_mean=float(np.nanmean(gains)) if gains else None, gains=gains,
                                           n_pairs_pooled=len(pooled), offset_recovery_r=(float(np.nanmean(rec)) if rec else None))
        if pooled:
            np.savez_compressed(f"{OUT}/pooled_{wname}_{h.replace('/', '_')}_k{k}.npz", y=y[te], cal=np.array([a for a, _ in pooled]), raw=np.array([r for _, r in pooled]))
    return res


def main():
    t0 = time.time(); os.makedirs(OUT, exist_ok=True)
    cnt = collections.Counter(SRC); held = sorted([s for s, c in cnt.items() if c >= MIN_ROWS])
    print(f"AT_START held-out sources={len(held)} (>= {MIN_ROWS} rows); anchor sources>=k: " + str({k: sum(len(l) >= k for l in by_src.values()) for k in KS}), flush=True)
    tasks = [(h, w) for w in ("real", "planted", "planted_full", "null") for h in held]
    todo = [t for t in tasks if not os.path.exists(f"{OUT}/{t[1]}__{t[0].replace('/', '_')}.json")]
    with ProcessPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(task, t): t for t in todo}
        for f in as_completed(futs):
            r = f.result(); json.dump(r, open(f"{OUT}/{r['world']}__{r['source'].replace('/', '_')}.json", "w"))
            print(f"done {r['world']} {r['source']} n={r['n_test']} ({time.time()-t0:.0f}s)", flush=True)
    print(f"AT_DONE {time.time()-t0:.0f}s", flush=True)


if __name__ == "__main__": main()
