#!/usr/bin/env python3
"""EXPLORATORY (not pre-registered): zero-learning rule baselines on the same seeds/pools as the loop. A rule ranks the whole pool by ONE literature descriptor and takes the top 500.
usage: rule_baseline.py CycPeptMPDB.csv out.json"""
import sys, json, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R, run_loop_par as P
from rdkit import Chem
from rdkit.Chem import Crippen, rdMolDescriptors
recs = R.load(sys.argv[1]); y = np.array([r["y"] for r in recs]); srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]; thr = float(np.quantile(y, .9))
NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])")
M = [Chem.MolFromSmiles(r["smiles"]) for r in recs]
feat = {"low_TPSA": -np.array([rdMolDescriptors.CalcTPSA(m) for m in M]), "high_logP": np.array([Crippen.MolLogP(m) for m in M]),
        "many_N_methyl": np.array([len(m.GetSubstructMatches(NME)) for m in M], float), "low_HBD": -np.array([rdMolDescriptors.CalcNumHBD(m) for m in M], float)}
out = {}
for reg in ("A", "B"):
    for name, s in feat.items():
        hits = []
        for seed in range(30):
            init, pool = P.setup(reg, seed, srcs, scaf, 100); pool = np.array(pool)
            pick = pool[np.argsort(-s[pool], kind="stable")[:500]]; hits.append(int((y[pick] >= thr).sum()))
        out[f"{reg}_{name}"] = dict(mean=round(float(np.mean(hits)), 1), ci95=[round(float(np.percentile(hits, 2.5)), 1), round(float(np.percentile(hits, 97.5)), 1)])
json.dump(out, open(sys.argv[2], "w"), indent=1); print(json.dumps(out, indent=1))
