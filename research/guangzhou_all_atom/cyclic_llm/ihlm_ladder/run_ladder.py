#!/usr/bin/env python3
"""T-LADDER runner (pre-registration docs/20261030_IHLM_LADDER_PREREG.md). One task = (regime, seed, scheme, k_anchor); every arm of the task runs on the SAME world (init, anchors, pool, eval slice E, per-round candidate subsets).
usage: run_ladder.py CycPeptMPDB.csv OUTDIR --regimes ABL --seeds 0-9 --scheme zc --k-anchor 5 [--arms R0,R1,...] [--slice i/N] [--smoke]
Arms: R0..R4 (cumulative ladder), R1_kshuf, R4_shuf, R4_frozen, gbm_aware, knn, gp, random_fb, rule_kphys.  Results written per task, arm by arm (resumable)."""
import os, sys, json, random, argparse, collections, time
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "loop_retro"))
import run_l7a as L, loop_models as LM
from ladder_core import PARAMS, TOP, world, run_arm, kshuf, parse_seeds
import adapter as AD

ARMS = ("R0", "R1", "R2", "R3", "R4", "R1_kshuf", "R4_shuf", "R4_frozen", "gbm_aware", "knn", "gp", "random_fb", "rule_kphys")


def make_backend(arm, ctx, seed):
    smiles, srcs, X = ctx["smiles"], ctx["srcs"], ctx["X"]
    if arm in ("R0", "R1", "R2", "R3", "R4", "R4_shuf", "R4_frozen"): return AD.IHLMBackend(arm.split("_")[0], smiles, srcs, ctx["Kp"], seed), {"R4_shuf": "shuffled", "R4_frozen": "frozen"}.get(arm, "loop")
    if arm == "R1_kshuf": return AD.IHLMBackend("R1", smiles, srcs, ctx["Kshuf"], seed), "loop"
    if arm in ("gbm_aware", "random_fb"): return LM.GBM(X), ("random" if arm == "random_fb" else "loop")
    if arm == "knn": return LM.KNN(X), "loop"
    if arm == "gp": return LM.GP(X), "loop"
    if arm == "rule_kphys": return None, "rule"
    raise SystemExit("unknown arm " + arm)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("out"); ap.add_argument("--regimes", default="ABL"); ap.add_argument("--seeds", default="0-9"); ap.add_argument("--scheme", default="zc", choices=["zc", "gc", "zt"])
    ap.add_argument("--k-anchor", type=int, default=5); ap.add_argument("--arms", default=",".join(ARMS)); ap.add_argument("--slice", default="0/1"); ap.add_argument("--smoke", action="store_true"); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True); import torch; torch.set_num_threads(1); p = dict(PARAMS)
    if a.smoke: p.update(rounds=2, steps0=10, steps_round=5, n_eval=min(p["n_eval"], 100), n_init=min(p["n_init"], 40), batch=min(p["batch"], 20), n_cand=60, n_flat_groups=10)
    recs, d = L.build(a.csv, "gbm", "cpu"); y_raw = np.array([r["y"] for r in recs], float); smiles = [r["smiles"] for r in recs]
    ctx = dict(y_raw=y_raw, y_t=d["y"], hit=(d["y"] >= d["thr"]), srcs=d["srcs"], Kp=np.asarray(d["Kphys"], float), smiles=smiles, X=np.stack([r["x"] for r in recs]))
    arms = [x for x in ARMS if x in a.arms.split(",")]; i0, n = [int(v) for v in a.slice.split("/")]
    tasks = [(reg, seed) for reg in a.regimes for seed in parse_seeds(a.seeds)]; tasks = [t for j, t in enumerate(tasks) if j % n == i0]
    print("n", len(recs), "arms", arms, "tasks", tasks, "scheme", a.scheme, "k", a.k_anchor, "params", p, flush=True)
    for reg, seed in tasks:
        f = f"{a.out}/ladder_{reg}_{a.scheme}_k{a.k_anchor}_{seed}.json"; out = json.load(open(f)) if os.path.exists(f) else None
        W = world(recs, d, reg, seed, a.k_anchor, p)
        if out is None: out = dict(seed=seed, regime=reg, scheme=a.scheme, k_anchor=a.k_anchor, params=p, n_pool=len(W["pool"]), n_E=len(W["E"]), anchors=W["anchors"], held=W["held"], E_hit_rate=float(ctx["hit"][W["E"]].mean()), E=[int(i) for i in W["E"]], E_src=[ctx["srcs"][i] for i in W["E"]], E_hit=[bool(ctx["hit"][i]) for i in W["E"]], init=[int(i) for i in W["init"]], arms={})
        ctx["Kshuf"] = kshuf(ctx["Kp"], ctx["srcs"], seed)
        for arm in arms:
            if arm in out["arms"]: continue
            B, kind = make_backend(arm, ctx, seed)
            out["arms"][arm] = run_arm(W, arm, B, kind, a.scheme, seed, p, ctx); tmp = f + ".tmp"; json.dump(out, open(tmp, "w")); os.replace(tmp, f)
            print("done", reg, seed, arm, sum(out["arms"][arm]["hits"]), "auroc_E", round(out["arms"][arm]["auroc_E"], 3), "s", out["arms"][arm]["seconds"], flush=True)


if __name__ == "__main__":
    main()
