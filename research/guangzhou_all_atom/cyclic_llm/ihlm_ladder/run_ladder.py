#!/usr/bin/env python3
"""T-LADDER runner (pre-registration docs/20261030_IHLM_LADDER_PREREG.md). One task = (regime, seed, scheme, k_anchor); every arm of the task runs on the SAME world (init, anchors, pool, eval slice E, per-round candidate subsets).
usage: run_ladder.py CycPeptMPDB.csv OUTDIR --regimes ABL --seeds 0-9 --scheme zc --k-anchor 5 [--arms R0,R1,...] [--slice i/N] [--smoke]
Arms: R0..R4 (cumulative ladder), R1_kshuf, R4_shuf, R4_frozen, gbm_aware, knn, gp, random_fb, rule_kphys.  Results written per task, arm by arm (resumable)."""
import os, sys, json, random, argparse, collections, time
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "loop_retro"))
import run_loop as R, run_loop_par as P, run_loop_prior as K, run_l7a as L, loop_models as LM
import adapter as AD

PARAMS = dict(L.PARAMS)                                    # n_init 100, rounds 10, batch 50, n_eval 800, steps0 100, steps_round 30, n_cand 150, n_flat_groups 60
ARMS = ("R0", "R1", "R2", "R3", "R4", "R1_kshuf", "R4_shuf", "R4_frozen", "gbm_aware", "knn", "gp", "random_fb", "rule_kphys")
TOP = L.TOP


def world(recs, d, reg, seed, k_anchor, p):
    """Same slice order as L7 (E, E_f, E_s) so pool and E are those of the L7 task; anchors then moved to the revealed set for EVERY arm (equal information)."""
    srcs, flat = d["srcs"], d["flat"]; cnt = collections.Counter(srcs); anchors = []
    if reg in ("L", "M"):
        init, pool, test, held = L.setup_L(seed, srcs, p["n_init"], max_labs=(9 if reg == "M" else None)); E, rest = L.make_eval_slice(test, seed, p["n_eval"])
        Ef, Efg, Efs, rest = L.make_flat_slice(rest, flat, seed, p["n_flat_groups"], d["y"]); Es, rest = L.make_source_slice(rest, srcs, seed)
        assert all(srcs[i] in set(held) for i in E + Ef + Efs + Es) and all(srcs[i] not in set(held) for i in list(pool) + list(init)), "regime L leakage between training and held-out labs"
        anchor_src = {i: srcs[i] for i in rest}; elig = collections.defaultdict(list)
        for i in rest: elig[srcs[i]].append(i)
        anchor_pool = rest
    else:
        init, pool = P.setup(reg, seed, srcs, d["scaf"], p["n_init"], flat); E, pool = L.make_eval_slice(pool, seed, p["n_eval"])
        Ef, Efg, Efs, pool = L.make_flat_slice(pool, flat, seed, p["n_flat_groups"], d["y"]); Es, pool = L.make_source_slice(pool, srcs, seed); elig = collections.defaultdict(list)
        for i in pool: elig[srcs[i]].append(i)
        held = []
    if k_anchor > 0:
        rng = random.Random(900000 + seed)
        for s in sorted(elig):
            if cnt[s] < 20: continue
            if reg in ("L", "M") and s not in set(held): continue
            anchors += rng.sample(sorted(elig[s]), min(k_anchor, len(elig[s])))
    aset = set(anchors); excl = [set(E), set(Ef), set(Efs), set(Es)]
    assert not aset & set(init) and all(not aset & x for x in excl), "anchors overlap an evaluation slice or the initial set"
    if reg not in ("L", "M"): pool = [i for i in pool if i not in aset]
    assert all(not x & set(pool) and not x & set(init) for x in excl)
    return dict(init=list(init), anchors=anchors, rev0=list(init) + anchors, pool=list(pool), E=list(E), held=list(held))


def run_arm(W, arm, B, kind, scheme, seed, p, ctx):
    y_raw, y_t, hit, srcs, K = ctx["y_raw"], ctx["y_t"], ctx["hit"], ctx["srcs"], ctx["Kp"]; rng = np.random.default_rng(seed); t0 = time.time()
    revealed = list(W["rev0"]); yseen = [float(y_raw[i]) for i in revealed]; E = np.array(W["E"]); pool0 = W["pool"]; picked = list(revealed)
    zl = lambda: AD.causal_labels(revealed, yseen, srcs, scheme, y_transductive=[y_t[i] for i in revealed])
    state0 = None if kind == "rule" else B.fit(B.init_state(), revealed, zl(), p["steps0"], seed)
    pred = (lambda st, idx: K[np.asarray(idx, int)]) if kind == "rule" else (lambda st, idx: B.predict(st, idx))
    ef0, au0 = L.ef5_auroc(pred(state0, E), hit[E]); rec = dict(hits=[], src=[], picks=[], ef5_E0=ef0, auroc_E0=au0, n_revealed0=len(revealed)); state = state0
    for r in range(p["rounds"]):
        U = np.array(L.subset(pool0, seed, r, picked, p["n_cand"]), dtype=int)
        if kind == "random": pick = [int(i) for i in rng.choice(U, p["batch"], replace=False)]
        else:
            s = pred(state0 if kind == "frozen" else state, U); pick = [int(i) for i in U[np.argsort(-s, kind="stable")[:p["batch"]]]]
        rec["picks"].append(pick); rec["hits"].append(int(sum(hit[i] for i in pick))); c = collections.Counter(srcs[i] for i in pick)
        rec["src"].append({TOP[0]: c.get(TOP[0], 0), TOP[1]: c.get(TOP[1], 0), "other": len(pick) - c.get(TOP[0], 0) - c.get(TOP[1], 0)}); picked += pick
        if kind in ("frozen", "rule"): continue
        new = y_raw[pick].copy()
        if kind == "shuffled": new = rng.choice(y_raw[np.array(pool0)], len(pick), replace=False)          # global draw: no item/batch association (L7d)
        revealed += pick; yseen += [float(v) for v in new]; state = B.fit(state, revealed, zl(), p["steps_round"], seed * 1000 + r)
    ef, au = L.ef5_auroc(pred(state if kind not in ("frozen", "rule") else state0, E), hit[E]); rec.update(ef5_E=ef, auroc_E=au, seconds=round(time.time() - t0, 1), n_revealed=len(revealed))
    return rec


def make_backend(arm, ctx, seed):
    smiles, srcs, X = ctx["smiles"], ctx["srcs"], ctx["X"]
    if arm in ("R0", "R1", "R2", "R3", "R4", "R4_shuf", "R4_frozen"): return AD.IHLMBackend(arm.split("_")[0], smiles, srcs, ctx["Kp"], seed), {"R4_shuf": "shuffled", "R4_frozen": "frozen"}.get(arm, "loop")
    if arm == "R1_kshuf": return AD.IHLMBackend("R1", smiles, srcs, ctx["Kshuf"], seed), "loop"
    if arm in ("gbm_aware", "random_fb"): return LM.GBM(X), ("random" if arm == "random_fb" else "loop")
    if arm == "knn": return LM.KNN(X), "loop"
    if arm == "gp": return LM.GP(X), "loop"
    if arm == "rule_kphys": return None, "rule"
    raise SystemExit("unknown arm " + arm)


def kshuf(Kp, srcs, seed):
    out = Kp.copy(); rr = np.random.default_rng(seed + 7); by = collections.defaultdict(list)
    for i, s in enumerate(srcs): by[s].append(i)
    for s in sorted(by): ix = np.array(sorted(by[s])); out[ix] = Kp[ix[rr.permutation(len(ix))]]          # sorted iteration: reproducible across PYTHONHASHSEED
    return out


def parse_seeds(s):
    if "-" in s: a, b = s.split("-"); return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]


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
        if out is None: out = dict(seed=seed, regime=reg, scheme=a.scheme, k_anchor=a.k_anchor, params=p, n_pool=len(W["pool"]), n_E=len(W["E"]), anchors=W["anchors"], held=W["held"], E_hit_rate=float(ctx["hit"][W["E"]].mean()), arms={})
        ctx["Kshuf"] = kshuf(ctx["Kp"], ctx["srcs"], seed)
        for arm in arms:
            if arm in out["arms"]: continue
            B, kind = make_backend(arm, ctx, seed)
            out["arms"][arm] = run_arm(W, arm, B, kind, a.scheme, seed, p, ctx); tmp = f + ".tmp"; json.dump(out, open(tmp, "w")); os.replace(tmp, f)
            print("done", reg, seed, arm, sum(out["arms"][arm]["hits"]), "auroc_E", round(out["arms"][arm]["auroc_E"], 3), "s", out["arms"][arm]["seconds"], flush=True)


if __name__ == "__main__":
    main()
