#!/usr/bin/env python3
"""Parallel, checkpointed runner for the retrospective loop (PREREG_LOOP.md + amendment L1). One task = (arm, regime, seed); each finished task is written to
<outdir>/<arm>_<regime>_<seed>.json immediately and skipped on resume, so a spot reclaim loses at most the tasks in flight.
usage: run_loop_par.py CycPeptMPDB.csv OUTDIR [procs=15]      (set OMP_NUM_THREADS=1 so each process is single-threaded)"""
import os, sys, json, random, collections, multiprocessing as mp
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R

SEEDS = 30
POLICIES = ("random", "greedy", "ucb", "oracle")
_G = {}


def setup(regime, seed, srcs, scaf, n_init):
    rng = random.Random(seed); n = len(srcs)
    if regime == "A":
        ids = list(range(n)); rng.shuffle(ids); return ids[:n_init], ids[n_init:]
    top2 = {s for s, _ in collections.Counter(srcs).most_common(2)}
    cand = [i for i in range(n) if srcs[i] in top2]; rng.shuffle(cand); init = cand[:n_init]
    sc = {scaf[i] for i in init}; ini = set(init)
    return init, [i for i in range(n) if i not in ini and scaf[i] not in sc]


def run_task(task, X, y, srcs, scaf, thr):
    arm, regime, seed = task
    init, pool = setup(regime, seed, srcs, scaf, R.N_INIT)
    out = {"arm": arm, "regime": regime, "seed": seed, "n_pool": len(pool)}
    for pol in POLICIES: out[pol] = R.run_policy(pol, X, y, init, pool, thr, seed)[0]
    return out


def _work(task):
    X = _G["X"][task[0]]; return run_task(task, X, _G["y"], _G["srcs"], _G["scaf"], _G["thr"])


def run_all(tasks, X, y, srcs, scaf, thr, outdir, procs=15):
    os.makedirs(outdir, exist_ok=True)
    todo = [t for t in tasks if not os.path.exists(f"{outdir}/{t[0]}_{t[1]}_{t[2]}.json")]
    _G.update(X=X if isinstance(X, dict) else {t[0]: X for t in tasks}, y=y, srcs=srcs, scaf=scaf, thr=thr)
    with mp.get_context("fork").Pool(min(procs, max(1, len(todo)))) as p:
        for r in p.imap_unordered(_work, todo):
            tmp = f"{outdir}/.{r['arm']}_{r['regime']}_{r['seed']}.tmp"; json.dump(r, open(tmp, "w")); os.replace(tmp, f"{outdir}/{r['arm']}_{r['regime']}_{r['seed']}.json")
            print("done", r["arm"], r["regime"], r["seed"], {k: r[k] for k in POLICIES}, flush=True)


if __name__ == "__main__":
    import rdkit
    from rdkit import Chem
    from rdkit.Chem import Descriptors, Crippen, rdMolDescriptors
    recs = R.load(sys.argv[1]); outdir = sys.argv[2]; procs = int(sys.argv[3]) if len(sys.argv) > 3 else 15
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])")
    def desc(smi):                        # literature permeability descriptors (PREREG_LOOP amendment L1)
        m = Chem.MolFromSmiles(smi); ri = m.GetRingInfo()
        return [Descriptors.MolWt(m), rdMolDescriptors.CalcTPSA(m), rdMolDescriptors.CalcNumHBD(m), rdMolDescriptors.CalcNumHBA(m), Crippen.MolLogP(m),
                rdMolDescriptors.CalcNumRotatableBonds(m), len(m.GetSubstructMatches(NME)), max((len(r) for r in ri.AtomRings()), default=0), m.GetNumHeavyAtoms(), rdMolDescriptors.CalcFractionCSP3(m)]
    Xfp = np.stack([r["x"] for r in recs]); Xkn = np.hstack([Xfp, np.array([desc(r["smiles"]) for r in recs], np.float32)])
    y = np.array([r["y"] for r in recs]); srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]; thr = float(np.quantile(y, 0.90))
    print("n", len(recs), "threshold", round(thr, 3), "features fp/kn", Xfp.shape[1], Xkn.shape[1], flush=True)
    tasks = [(a, g, s) for s in range(SEEDS) for g in ("A", "B") for a in ("fp", "kn")]
    run_all(tasks, {"fp": Xfp, "kn": Xkn}, y, srcs, scaf, thr, outdir, procs)
