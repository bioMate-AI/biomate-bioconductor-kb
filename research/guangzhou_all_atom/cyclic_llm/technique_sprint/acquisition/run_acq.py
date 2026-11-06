#!/usr/bin/env python3
"""Parallel, per-task-checkpointed runner for the T2 acquisition study (pre-registration df9f89e00).
usage: run_acq.py CSV OUTDIR --arms prov,greedy --regimes A,B,L --seeds 0-29 [--lam 0.5 --cap-src 25 --cap-flat 5 | --cfg frozen_config.json] [--tag NAME]
       [--labels real|planted1|planted2|shuffle] [--procs 30] [--cache /w/acq_cache.pkl]   (set OMP_NUM_THREADS=1)
One task = (arm[@tag], regime, seed) -> OUTDIR/<arm>[@tag]_<regime>_<seed>.json written atomically; finished tasks are skipped on resume (spot-safe)."""
import os, sys, json, argparse, multiprocessing as mp
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import acq as A

_G = {}


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if "-" in part: a, b = part.split("-"); out += list(range(int(a), int(b) + 1))
        else: out.append(int(part))
    return out


def planted_labels(D, mode):
    """Synthetic labels on the real fingerprints (pre-registration 1.9 C1). P1: one series in the largest source; P2: three series in three different sources. Fixed construction seed."""
    rng = np.random.default_rng(12345); n = len(D["y"]); Bin = D["B"] > 0; srcs = np.array(D["srcs"]); import collections
    big = [s for s, _ in collections.Counter(D["srcs"]).most_common()]
    def series_in(src, lo, hi, avoid=()):
        idx = np.where(srcs == src)[0]; freq = Bin[idx].mean(0); cand = [b for b in np.argsort(np.abs(freq - 0.15)) if lo <= Bin[idx, b].sum() <= hi and b not in avoid]
        b = int(cand[0]); return idx[Bin[idx, b]], b
    masks = []; used = []
    if mode == "planted1":
        m, b = series_in(big[0], 200, 700); masks.append(m)
    else:
        for s in (big[1], big[2], big[3]):
            m, b = series_in(s, 80, 400, used); masks.append(m); used.append(b)
    y = rng.standard_normal(n); allm = np.zeros(n, bool)
    for m in masks: allm[m] = True
    y = y + 3.0 * allm
    return y, float(np.quantile(y, 0.9)), [np.isin(np.arange(n), m) for m in masks]


def shuffled_labels(D, seed=31337):
    """Labels permuted within source (breaks every peptide->label link, keeps per-source distributions)."""
    rng = np.random.default_rng(seed); y = D["y"].copy(); srcs = np.array(D["srcs"])
    for s in sorted(set(D["srcs"])):                       # sorted: set iteration order depends on PYTHONHASHSEED (review finding m1)
        ix = np.where(srcs == s)[0]; y[ix] = D["y"][rng.permutation(ix)]
    return y, float(np.quantile(y, 0.9))


def _work(task):
    import time; t0 = time.time(); arm, regime, seed, label, cfg = task; D = _G["D"]; kw = {}
    if _G["labels"] == "real": kw = dict(thr_g=D["thr_g"])
    else: kw = dict(y=_G["y"], thr=_G["thr"], thr_g=None)
    out = A.run_task(arm, regime, seed, D, cfg, with_transfer=(_G["labels"] == "real"), ymode=_G["ymode"], **kw); out["label"] = label; out["labels_mode"] = _G["labels"]; out["cfg"] = cfg; out["seconds"] = round(time.time() - t0, 1)
    if _G.get("masks") is not None: out["planted_found"] = [int(m[out["picks"]].sum()) for m in _G["masks"]]; out["planted_size"] = [int(m.sum()) for m in _G["masks"]]
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("out"); ap.add_argument("--arms", required=True); ap.add_argument("--regimes", default="A,B,L"); ap.add_argument("--seeds", default="0-29")
    ap.add_argument("--lam", type=float, default=0.0); ap.add_argument("--cap-src", type=int, default=50); ap.add_argument("--cap-flat", type=int, default=A.BIG); ap.add_argument("--cfg"); ap.add_argument("--tag", default="")
    ap.add_argument("--labels", default="real", choices=("real", "planted1", "planted2", "shuffle")); ap.add_argument("--procs", type=int, default=30); ap.add_argument("--cache"); ap.add_argument("--ymode", default="trans", choices=("trans", "causal")); ap.add_argument("--grid", action="store_true", help="pre-registered development grid for prov/div (1.6): 12 configurations"); ap.add_argument("--grid6", action="store_true", help="amendment A3 reduced grid: 6 configurations")
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    cfg = json.load(open(a.cfg))["config"] if a.cfg else dict(lam=a.lam, cap_src=a.cap_src, cap_flat=a.cap_flat)
    D = A.prepare(a.csv, a.cache); _G.update(D=D, labels=a.labels, masks=None, ymode=a.ymode)
    if a.labels.startswith("planted"): y, thr, masks = planted_labels(D, a.labels); _G.update(y=y, thr=thr, masks=masks)
    elif a.labels == "shuffle": y, thr = shuffled_labels(D); _G.update(y=y, thr=thr)
    import itertools
    grid = [(f"l{l}_s{cs}_f{'inf' if cf >= A.BIG else cf}", dict(lam=l, cap_src=cs, cap_flat=cf)) for l, cs, cf in itertools.product((0.0, 0.5, 1.0), (50, 25), (A.BIG, 5))]
    if a.grid6: grid = [(f"l{l}_s{cs}_f{'inf' if cf >= A.BIG else cf}", dict(lam=l, cap_src=cs, cap_flat=cf)) for l, cs, cf in ((0.0, 50, A.BIG), (0.5, 50, A.BIG), (1.0, 50, A.BIG), (0.0, 25, 5), (0.5, 25, 5), (1.0, 25, 5))]
    tasks = []
    for s in parse_seeds(a.seeds):
        for g in a.regimes.split(","):
            for arm in a.arms.split(","):
                if (a.grid or a.grid6) and arm in ("prov", "div"): tasks += [(arm, g, s, f"{arm}@{tag}", c) for tag, c in grid]
                else: tasks.append((arm, g, s, arm + (("@" + a.tag) if a.tag and arm in ("prov", "div") else ""), cfg))
    todo = [t for t in tasks if not os.path.exists(f"{a.out}/{t[3]}_{t[1]}_{t[2]}.json")]
    print(f"n={len(D['y'])} thr={D['thr']:.3f} cfg={cfg} labels={a.labels} ymode={a.ymode} tasks={len(tasks)} todo={len(todo)}", flush=True)
    with mp.get_context("fork").Pool(min(a.procs, max(1, len(todo)))) as p:
        for r in p.imap_unordered(_work, todo):
            f = f"{a.out}/{r['label']}_{r['regime']}_{r['seed']}.json"; tmp = f"{a.out}/.{r['label']}_{r['regime']}_{r['seed']}.tmp"; json.dump(r, open(tmp, "w")); os.replace(tmp, f)
            print("done", r["label"], r["regime"], r["seed"], r["hits"], flush=True)


if __name__ == "__main__":
    main()
