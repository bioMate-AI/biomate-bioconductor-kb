#!/usr/bin/env python3
"""Knowledge-as-prior arms of the retrospective loop (PREREG_LOOP.md amendment L2). Per-task, checkpointed, parallel; reuses run_loop / run_loop_par.
usage: run_loop_prior.py CycPeptMPDB.csv OUTDIR [procs=30]   (OMP_NUM_THREADS=1)"""
import os, sys, json, multiprocessing as mp
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R, run_loop_par as P

SEEDS = 30
ARMS = ("random", "fp", "kn", "resid_nme", "resid_z", "fuse_nme", "fuse_z")
_G = {}


def zs(v):
    v = np.asarray(v, float); s = v.std()
    return (v - v.mean()) / (s if s > 0 else 1.0)


def source_normalize(y, srcs, min_n=20):
    """PREREG_LOOP L3: z-score permeability within each literature source; sources with < min_n peptides are z-scored together as one group."""
    y = np.asarray(y, float); srcs = np.asarray(srcs); out = np.zeros(len(y))
    cnt = {s: int((srcs == s).sum()) for s in set(srcs.tolist())}; grp = np.array([s if cnt[s] >= min_n else "__other__" for s in srcs.tolist()])
    for g in set(grp.tolist()):
        m = grp == g; sd = y[m].std(); out[m] = (y[m] - y[m].mean()) / (sd if sd > 0 else 1.0)
    return out


def k_z(nme, hbd, tpsa):
    """K_z = z(N-methyl count) - z(H-bond donors) - z(TPSA); equal weights; label-free."""
    return zs(zs(nme) - zs(hbd) - zs(tpsa))


def run_prior_policy(mode, X, y, K, init, pool, thr, seed):
    """Greedy loop with knowledge integration. mode: fp | resid | fuse. Returns (total hits, per-round hits)."""
    rng = np.random.default_rng(seed); labeled = list(init); unl = list(pool); per = []
    for _ in range(R.ROUNDS):
        L = np.array(labeled); U = np.array(unl)
        if mode == "random":
            score = rng.random(len(U))
        elif mode == "fp":
            ms = R.fit_ens(X[L], y[L], rng); score = np.mean([m.predict(X[U]) for m in ms], 0)
        elif mode == "resid":
            kk = K[L]; v = kk.var(); a = float(np.cov(kk, y[L])[0, 1] / v) if v > 0 else 0.0; b = float(y[L].mean() - a * kk.mean())
            ms = R.fit_ens(X[L], y[L] - (a * kk + b), rng); score = a * K[U] + b + np.mean([m.predict(X[U]) for m in ms], 0)
        else:   # fuse
            ms = R.fit_ens(X[L], y[L], rng); pred = np.mean([m.predict(X[U]) for m in ms], 0); w = 100.0 / (100.0 + len(labeled))
            score = (1 - w) * zs(pred) + w * zs(K[U])
        pick = [unl[j] for j in np.argsort(-score, kind="stable")[:R.BATCH]]
        s = set(pick); unl = [i for i in unl if i not in s]; labeled += pick; per.append(int(sum(y[i] >= thr for i in pick)))
    return sum(per), per


def run_task(task, X, y, Ks, srcs, scaf, thr):
    arm, regime, seed = task; init, pool = P.setup(regime, seed, srcs, scaf, R.N_INIT)
    mode = arm if arm in ("random", "fp", "kn") else arm.split("_")[0]; K = Ks[arm.split("_")[1]] if "_" in arm else None
    Xa = _G["Xkn"] if arm == "kn" else X
    tot, per = run_prior_policy("fp" if mode == "kn" else mode, Xa, y, K if K is not None else np.zeros(len(y)), init, pool, thr, seed)
    return {"arm": arm, "regime": regime, "seed": seed, "n_pool": len(pool), "greedy": tot, "rounds": per}


def _work(task): return run_task(task, _G["X"], _G["y"], _G["Ks"], _G["srcs"], _G["scaf"], _G["thr"])


def run_all(tasks, X, y, Ks, srcs, scaf, thr, outdir, procs=30):
    os.makedirs(outdir, exist_ok=True)
    todo = [t for t in tasks if not os.path.exists(f"{outdir}/{t[0]}_{t[1]}_{t[2]}.json")]
    _G.update(X=X, y=y, Ks=Ks, srcs=srcs, scaf=scaf, thr=thr)   # _G['Xkn'] may be pre-set by main
    with mp.get_context("fork").Pool(min(procs, max(1, len(todo)))) as p:
        for r in p.imap_unordered(_work, todo):
            tmp = f"{outdir}/.{r['arm']}_{r['regime']}_{r['seed']}.tmp"; json.dump(r, open(tmp, "w")); os.replace(tmp, f"{outdir}/{r['arm']}_{r['regime']}_{r['seed']}.json")
            print("done", r["arm"], r["regime"], r["seed"], r["greedy"], r["rounds"][:4], flush=True)


if __name__ == "__main__":
    from rdkit import Chem
    from rdkit.Chem import rdMolDescriptors
    recs = R.load(sys.argv[1]); outdir = sys.argv[2]; procs = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); M = [Chem.MolFromSmiles(r["smiles"]) for r in recs]
    nme = np.array([len(m.GetSubstructMatches(NME)) for m in M], float); hbd = np.array([rdMolDescriptors.CalcNumHBD(m) for m in M], float)
    tpsa = np.array([rdMolDescriptors.CalcTPSA(m) for m in M], float)
    Ks = {"nme": zs(nme), "z": k_z(nme, hbd, tpsa)}
    X = np.stack([r["x"] for r in recs]); y_raw = np.array([r["y"] for r in recs]); srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]
    y = source_normalize(y_raw, srcs); thr = float(np.quantile(y, 0.90))        # PREREG_LOOP L3: within-source labels
    from rdkit.Chem import Descriptors, Crippen
    desc = np.array([[Descriptors.MolWt(m), tpsa[i], hbd[i], rdMolDescriptors.CalcNumHBA(m), Crippen.MolLogP(m), rdMolDescriptors.CalcNumRotatableBonds(m), nme[i],
                      max((len(r_) for r_ in m.GetRingInfo().AtomRings()), default=0), m.GetNumHeavyAtoms(), rdMolDescriptors.CalcFractionCSP3(m)] for i, m in enumerate(M)], np.float32)
    _G["Xkn"] = np.hstack([X, desc])
    print("n", len(recs), "y_norm threshold", round(thr, 3), flush=True)
    run_all([(a, g, s) for s in range(SEEDS) for g in ("A", "B") for a in ARMS], X, y, Ks, srcs, scaf, thr, outdir, procs)
