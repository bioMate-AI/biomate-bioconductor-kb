#!/usr/bin/env python3
"""EXPLORATORY validation of the in-repo medchem knowledge-base rules against MEASURED cyclic-peptide permeability (CycPeptMPDB PAMPA rows).
For each computable KB rule: hit rate (top 10 % permeability) among peptides that PASS vs FAIL, odds ratio, 95 % interval from resampling literature SOURCES.
usage: kb_rule_validation.py CycPeptMPDB.csv out.json"""
import sys, os, json, random, collections
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R
from rdkit import Chem
from rdkit.Chem import Descriptors, Crippen, rdMolDescriptors
from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
recs = R.load(sys.argv[1]); y = np.array([r["y"] for r in recs]); src = np.array([r["source"] for r in recs]); hit = y >= float(np.quantile(y, .9))
M = [Chem.MolFromSmiles(r["smiles"]) for r in recs]
NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); nme = np.array([len(m.GetSubstructMatches(NME)) for m in M])
mw = np.array([Descriptors.MolWt(m) for m in M]); logp = np.array([Crippen.MolLogP(m) for m in M]); hbd = np.array([rdMolDescriptors.CalcNumHBD(m) for m in M]); hba = np.array([rdMolDescriptors.CalcNumHBA(m) for m in M])
rot = np.array([rdMolDescriptors.CalcNumRotatableBonds(m) for m in M]); tpsa = np.array([rdMolDescriptors.CalcTPSA(m) for m in M])
def free(cat):
    p = FilterCatalogParams(); p.AddCatalog(cat); fc = FilterCatalog(p); return np.array([not fc.HasMatch(m) for m in M])
rules = {"Lipinski Ro5 (MW<=500, logP<=5, HBD<=5, HBA<=10)": (mw <= 500) & (logp <= 5) & (hbd <= 5) & (hba <= 10),
         "Veber (rot<=10, TPSA<=140)": (rot <= 10) & (tpsa <= 140),
         "N-methylated (>=1 N-Me amide) [KB: N-methylation heuristic]": nme >= 1,
         "N-methylated (>=2)": nme >= 2,
         "PAINS-free [KB liability domain]": free(FilterCatalogParams.FilterCatalogs.PAINS),
         "BRENK-free [KB liability domain]": free(FilterCatalogParams.FilterCatalogs.BRENK)}
srcs = sorted(set(src)); idx = {s: np.where(src == s)[0] for s in srcs}; rng = random.Random(0)
def odds(p):
    a = (p & hit).sum() + .5; b = (p & ~hit).sum() + .5; c = (~p & hit).sum() + .5; d = (~p & ~hit).sum() + .5; return float(a * d / (b * c))
out = {"n": len(recs), "n_sources": len(srcs), "base_hit_rate": round(float(hit.mean()), 3)}
for name, p in rules.items():
    boots = []
    for _ in range(1000):
        ii = np.concatenate([idx[rng.choice(srcs)] for _ in srcs]); pp, hh = p[ii], hit[ii]
        a = (pp & hh).sum() + .5; b = (pp & ~hh).sum() + .5; c = (~pp & hh).sum() + .5; d = (~pp & ~hh).sum() + .5; boots.append(a * d / (b * c))
    out[name] = dict(pass_n=int(p.sum()), pass_frac=round(float(p.mean()), 3), hit_rate_pass=round(float(hit[p].mean()), 3) if p.any() else None,
                     hit_rate_fail=round(float(hit[~p].mean()), 3) if (~p).any() else None, odds_ratio=round(odds(p), 2), or_ci95=[round(float(np.percentile(boots, 2.5)), 2), round(float(np.percentile(boots, 97.5)), 2)])
json.dump(out, open(sys.argv[2], "w"), indent=1)
for k, v in out.items(): print(k, v)
