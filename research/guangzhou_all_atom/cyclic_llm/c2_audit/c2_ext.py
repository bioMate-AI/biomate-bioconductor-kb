#!/usr/bin/env python3
"""Part A-ext of docs/20261030_C2_RERUN_AND_ANCHOR_TEST.md (pre-registered 074293728). Reuses the committed c2_retro_loop.py
(imported unchanged) and adds: background conditions full / famdisjoint / none; arms learn, fixed, random, nn, desc; controls shuffled, planted.
usage: c2_ext.py STAGED.npz C2_RETRO_LOOP.py TARGET_FAMILY.json OUTDIR  (env EXT_TARGETS=n_random_extra, EXT_SEEDS, EXT_WORKERS, EXT_NBG, EXT_ROUNDS)"""
import importlib.util, json, os, sys, time, zlib
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed

STAGE, C2PY, FAM, OUT = sys.argv[1:5]
spec = importlib.util.spec_from_file_location("c2", C2PY); c2 = importlib.util.module_from_spec(spec); spec.loader.exec_module(c2)
FAMILY = json.load(open(FAM))
SEEDS = int(os.environ.get("EXT_SEEDS", "3")); NBG = int(os.environ.get("EXT_NBG", str(c2.N_BG))); ROUNDS = int(os.environ.get("EXT_ROUNDS", str(c2.N_ROUNDS)))
N_EXTRA = int(os.environ.get("EXT_TARGETS", "30")); WORKERS = int(os.environ.get("EXT_WORKERS", str(os.cpu_count() or 4)))
N_DESC = 16


def sim_ext(Xbg, ybg, Xt, yt, hit_mask, clusters, mode, seed):
    """Same random stream as c2.sim_one (paired seeds). Xbg may be empty (condition 'none')."""
    r = np.random.default_rng(seed); n = len(yt)
    acq = list(r.choice(n, c2.N_SEED, replace=False)); seed_cl = set(clusters[acq].tolist())
    pool = [i for i in range(n) if i not in set(acq)]
    B = (Xt[:, :2048] > 0).astype(np.float32); card = B.sum(1)
    nov = lambda idx: int(sum(1 for i in idx if hit_mask[i] and clusters[i] not in seed_cl))
    hits = [int(hit_mask[acq].sum())]; nv = [nov(acq)]
    def fit(cols, acq_):
        Xtr = np.vstack([Xbg[:, cols], Xt[acq_][:, cols]]) if len(Xbg) else Xt[acq_][:, cols]
        ytr = np.concatenate([ybg, yt[acq_]]) if len(Xbg) else yt[acq_]
        return c2.model().fit(Xtr, ytr)
    allc = slice(None); descc = slice(Xt.shape[1] - N_DESC, Xt.shape[1])
    fixed_m = fit(allc, acq) if mode == "fixed" else None
    for _ in range(ROUNDS):
        if not pool: hits.append(hits[-1]); nv.append(nv[-1]); continue
        if mode == "random": pick = list(r.choice(pool, min(c2.BATCH, len(pool)), replace=False))
        elif mode in ("learn", "fixed", "desc"):
            m = fit(descc if mode == "desc" else allc, acq) if mode != "fixed" else fixed_m
            Xq = Xt[pool][:, descc] if mode == "desc" else Xt[pool]
            pick = [pool[j] for j in np.argsort(-m.predict(Xq))[:c2.BATCH]]
        elif mode == "nn":   # similarity-weighted mean pAff of the 3 nearest REVEALED compounds (analog lookup)
            inter = B[pool] @ B[acq].T; tani = inter / (card[pool][:, None] + card[acq][None, :] - inter + 1e-9)
            top = np.argsort(-tani, axis=1)[:, :3]; w = np.take_along_axis(tani, top, 1); yy = yt[acq][top]
            pick = [pool[j] for j in np.argsort(-((w * yy).sum(1) / (w.sum(1) + 1e-9)))[:c2.BATCH]]
        else: raise ValueError(mode)
        acq += pick; ps = set(pick); pool = [i for i in pool if i not in ps]
        hits.append(int(hit_mask[acq].sum())); nv.append(nov(acq))
    return np.array(hits, float), np.array(nv, float)


def run_target(args):
    t, Xt, yt, fpt, bg_full, bg_fam, ctrl_ok = args
    out = []
    thr = np.quantile(yt, c2.HIT_Q); hit0 = yt >= thr
    if hit0.sum() < 3: return t, []
    clusters = c2.tanimoto_clusters(fpt)
    # controls (same pool, labels replaced)
    rng = np.random.default_rng(zlib.crc32(t.encode()) ^ 77)
    y_shuf = rng.permutation(yt)
    bits = np.where((fpt > 0).mean(0) > 0.2)[0]; bits = bits[(fpt[:, bits] > 0).mean(0) < 0.6]
    pl = rng.choice(bits, 3, replace=False) if len(bits) >= 3 else None
    y_pl = None if pl is None else ((fpt[:, pl] > 0).sum(1) + rng.normal(0, 0.3, len(yt))).astype(np.float32)
    for s in range(SEEDS):
        seed = 1000 * s + c2._stable_offset(t)
        jobs = []   # (ctrl, bgname, bgdata, mode, labels)
        for bgname, bg in (("full", bg_full), ("famdisjoint", bg_fam), ("none", (np.zeros((0, Xt.shape[1]), np.float32), np.zeros(0, np.float32)))):
            for mode in (("learn", "fixed") if bgname != "none" else ("learn", "fixed")): jobs.append(("real", bgname, bg, mode, yt))
        for bgname, bg in (("full", bg_full), ("famdisjoint", bg_fam)): jobs.append(("real", bgname, bg, "desc", yt))
        jobs += [("real", "any", bg_fam, "random", yt), ("real", "any", bg_fam, "nn", yt)]
        if ctrl_ok:
            for cn, ylab in (("shuffled", y_shuf), ("planted", y_pl)):
                if ylab is None: continue
                for mode in ("learn", "fixed", "random", "nn"): jobs.append((cn, "famdisjoint", bg_fam, mode, ylab))
        for cn, bgname, bg, mode, ylab in jobs:
            thr_c = np.quantile(ylab, c2.HIT_Q); hm = ylab >= thr_c
            h, nv = sim_ext(bg[0], bg[1], Xt, ylab, hm, clusters, mode, seed)
            out.append(dict(target=t, family=FAMILY.get(t, "NA"), seed=s, ctrl=cn, bg=bgname, mode=mode, n_hits=int(hm.sum()),
                            curve=(h / hm.sum()).round(4).tolist(), novel_final=float(nv[-1])))
    return t, out


def main():
    t0 = time.time(); z = np.load(STAGE, allow_pickle=True)
    fp = z["fp"].astype(np.float32); desc = z["desc"].astype(np.float32); y = z["pAff"].astype(np.float32); tgt = z["target"].astype(str)
    X = np.nan_to_num(np.hstack([fp, desc]), nan=0.0, posinf=0.0, neginf=0.0)
    counts = {t: int((tgt == t).sum()) for t in set(tgt) if t}
    sel = sorted([t for t, c in counts.items() if c >= c2.N_MIN], key=lambda t: -counts[t])
    for flag in ("is_avb6", "is_pdl1"):
        for t in set(tgt[z[flag].astype(bool)]):
            if t and counts.get(t, 0) >= c2.N_MIN and t not in sel: sel.append(t)
    sel = sel[:200]
    logged10 = sel[:10]; rest = [t for t in sel if t not in logged10]
    extra = list(np.random.default_rng(0).choice(rest, min(N_EXTRA, len(rest)), replace=False))
    run_set = logged10 + extra; ctrl_set = set(logged10 + extra[:10])
    print(f"EXT_START targets={len(sel)} run={len(run_set)} (10 logged + {len(extra)} seeded random) seeds={SEEDS} nbg={NBG} rounds={ROUNDS}", flush=True)
    rng = np.random.default_rng(0); work = []   # same rng stream as c2_retro_loop.main -> identical pools/bg for the logged targets
    fp_bytes = None
    for t in sel:
        ti = np.where(tgt == t)[0]
        if len(ti) > c2.MAX_POOL: ti = rng.choice(ti, c2.MAX_POOL, replace=False)
        bg = np.where(tgt != t)[0]
        if len(bg) > c2.N_BG: bg = rng.choice(bg, c2.N_BG, replace=False)
        if t not in run_set: continue
        fam = FAMILY.get(t)
        pool_fp = {fp[i].tobytes() for i in ti}
        okrows = np.array([i for i in np.where(tgt != t)[0] if (FAMILY.get(tgt[i]) != fam or fam is None) and fp[i].tobytes() not in pool_fp])
        r2 = np.random.default_rng(zlib.crc32(t.encode()) ^ 1)
        bgf = r2.choice(okrows, min(NBG, len(okrows)), replace=False)
        work.append((t, X[ti], y[ti], fp[ti], (X[bg][: NBG], y[bg][: NBG]), (X[bgf], y[bgf]), t in ctrl_set))
        print(f"  {t} fam={fam} pool={len(ti)} bg_full={len(bg)} bg_famdisjoint_avail={len(okrows)}", flush=True)
    os.makedirs(OUT, exist_ok=True); done = 0
    todo = [w for w in work if not os.path.exists(f"{OUT}/{w[0]}.json")]
    with ProcessPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(run_target, w): w[0] for w in todo}
        for f in as_completed(futs):
            t, rows = f.result(); json.dump(rows, open(f"{OUT}/.{t}.tmp", "w")); os.replace(f"{OUT}/.{t}.tmp", f"{OUT}/{t}.json")
            done += 1; print(f"[{done}/{len(todo)}] {t} {len(rows)} rows ({time.time()-t0:.0f}s)", flush=True)
    print(f"EXT_DONE {time.time()-t0:.0f}s", flush=True)


if __name__ == "__main__": main()
