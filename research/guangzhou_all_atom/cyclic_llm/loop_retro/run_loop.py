#!/usr/bin/env python3
"""Retrospective closed loop on real measured permeability. Implements PREREG_LOOP.md exactly. usage: run_loop.py CycPeptMPDB.csv out.json"""
import csv, os, sys, json, random, collections
import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
from rdkit.Chem.Scaffolds import MurckoScaffold
from sklearn.ensemble import HistGradientBoostingRegressor
RDLogger.DisableLog("rdApp.*")
N_INIT, ROUNDS, BATCH, SEEDS, ENS, UCB_W = 100, 10, 50, 30, 5, 1.0


def morgan_counts(m, chiral=False):
    """2,048-bin Morgan count fingerprint, radius 2. chiral=True encodes stereochemistry (PREREG_LOOP L5)."""
    fp = np.zeros(2048, np.float32)
    for i, c in AllChem.GetMorganFingerprint(m, 2, useChirality=bool(chiral)).GetNonzeroElements().items(): fp[i % 2048] += c
    return fp


def flat_key(m):
    return Chem.MolToSmiles(m, isomericSmiles=False)


def load(path, label_col=None, chiral=None):
    label_col = label_col or os.environ.get("LABEL_COL", "Permeability")           # L5: PAMPA
    chiral = (os.environ.get("FP_CHIRAL") == "1") if chiral is None else chiral        # L5: True
    rows = list(csv.DictReader(open(path, encoding="utf-8-sig", errors="replace")))
    by = collections.defaultdict(list)
    for r in rows:
        try: y = float(r[label_col])
        except (ValueError, KeyError): continue
        if y <= -9.99 or not r.get("PAMPA", "").strip() or not r.get("SMILES"): continue
        by[r["Structurally_Unique_ID"]].append(r)
    recs = []
    for k, rs in by.items():
        m = Chem.MolFromSmiles(rs[0]["SMILES"])
        if m is None: continue
        fp = morgan_counts(m, chiral)
        try: scaf = MurckoScaffold.MurckoScaffoldSmiles(mol=m)
        except Exception: scaf = rs[0]["SMILES"]
        recs.append(dict(y=float(np.mean([float(r[label_col]) for r in rs])), x=fp, source=rs[0]["Source"], scaf=scaf, smiles=rs[0]["SMILES"], flat=flat_key(m)))
    return recs


def fit_ens(X, y, rng):
    ms = []
    for _ in range(ENS):
        idx = rng.integers(0, len(y), len(y))
        ms.append(HistGradientBoostingRegressor(max_iter=150, learning_rate=0.1, random_state=int(rng.integers(1 << 30))).fit(X[idx], y[idx]))
    return ms


def run_policy(policy, X, y, init, pool, thr, seed):
    rng = np.random.default_rng(seed)
    labeled = list(init); unl = list(pool); hits = []
    for _ in range(ROUNDS):
        if policy == "random": pick = list(rng.choice(unl, BATCH, replace=False))
        elif policy == "oracle": pick = sorted(unl, key=lambda i: -y[i])[:BATCH]
        else:
            ms = fit_ens(X[labeled], y[labeled], rng); P = np.stack([m.predict(X[unl]) for m in ms])
            score = P.mean(0) + (UCB_W * P.std(0) if policy == "ucb" else 0)
            pick = [unl[j] for j in np.argsort(-score)[:BATCH]]
        s = set(pick); unl = [i for i in unl if i not in s]; labeled += pick
        hits.append(int(sum(y[i] >= thr for i in pick)))
    return int(sum(hits)), hits


def ci(v): v = sorted(v); n = len(v); return [round(v[int(.025 * n)], 2), round(v[min(n - 1, int(.975 * n))], 2)]


def regime(name, recs, X, y, thr):
    src = collections.Counter(r["source"] for r in recs); top2 = {s for s, _ in src.most_common(2)}
    out = {}
    for seed in range(SEEDS):
        rng = random.Random(seed)
        if name == "A":
            ids = list(range(len(recs))); rng.shuffle(ids); init, pool = ids[:N_INIT], ids[N_INIT:]
        else:
            cand = [i for i, r in enumerate(recs) if r["source"] in top2]; rng.shuffle(cand); init = cand[:N_INIT]
            sc = {recs[i]["scaf"] for i in init}; pool = [i for i in range(len(recs)) if i not in set(init) and recs[i]["scaf"] not in sc]
        for pol in ("random", "greedy", "ucb", "oracle"):
            out.setdefault(pol, []).append(run_policy(pol, X, y, init, pool, thr, seed)[0])
        out.setdefault("n_pool", []).append(len(pool))
    res = {p: dict(mean=round(float(np.mean(v)), 2), ci95=ci(v)) for p, v in out.items() if p != "n_pool"}
    for p in ("greedy", "ucb"):
        d = [a - b for a, b in zip(out[p], out["random"])]
        res[f"{p}_minus_random"] = dict(mean=round(float(np.mean(d)), 2), ci95=ci(d), lower_gt0=bool(ci(d)[0] > 0))
    res["pool_size_mean"] = int(np.mean(out["n_pool"])); res["n_seeds"] = SEEDS
    return res


if __name__ == "__main__":
    recs = load(sys.argv[1]); X = np.stack([r["x"] for r in recs]); y = np.array([r["y"] for r in recs])
    thr = float(np.quantile(y, 0.90)); print("n", len(recs), "hit threshold (top 10%)", round(thr, 3), flush=True)
    res = dict(n_peptides=len(recs), hit_threshold=thr, regime_A_iid=regime("A", recs, X, y, thr), regime_B_shift=regime("B", recs, X, y, thr))
    res["CLAIM_loop_beats_random_both_regimes"] = bool(any(res[f"regime_{k}"][f"{p}_minus_random"]["lower_gt0"] for p in ("greedy", "ucb") for k in ("A_iid",))
        and any(res["regime_B_shift"][f"{p}_minus_random"]["lower_gt0"] for p in ("greedy", "ucb")))
    json.dump(res, open(sys.argv[2], "w"), indent=1); print(json.dumps(res, indent=1))
