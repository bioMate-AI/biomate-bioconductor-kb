#!/usr/bin/env python3
"""Part B data prep (docs/20261030_C2_RERUN_AND_ANCHOR_TEST.md §2). One record per raw CycPeptMPDB PAMPA row
(PAMPA column, > -10 floor removed) — NOT collapsed by Structurally_Unique_ID, so the same peptide measured in several
sources stays as several (source, label) records. Chirality-aware Morgan count fingerprint (radius 2, 2048).
Anchors: rows whose Same_Peptides_* lists give PAMPA values from at least one OTHER source.
usage: prep_anchor_data.py CycPeptMPDB_Peptide_All.csv out.npz"""
import ast, json, sys
import numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")

d = pd.read_csv(sys.argv[1], low_memory=False)
d = d[d["PAMPA"].notna() & (d["PAMPA"] > -9.99) & d["SMILES"].notna()].reset_index(drop=True)
fp = np.zeros((len(d), 2048), np.uint8); ok = np.ones(len(d), bool)
for i, s in enumerate(d["SMILES"]):
    m = Chem.MolFromSmiles(s)
    if m is None: ok[i] = False; continue
    for b, c in AllChem.GetMorganFingerprint(m, 2, useChirality=True).GetNonzeroElements().items(): fp[i, b % 2048] = min(255, fp[i, b % 2048] + c)
d = d[ok].reset_index(drop=True); fp = fp[ok]
anchors = []
for i, r in d.iterrows():
    if not isinstance(r.Same_Peptides_Source, str): continue
    try:
        srcs = ast.literal_eval(r.Same_Peptides_Source); perm = ast.literal_eval(r.Same_Peptides_Permeability); assay = ast.literal_eval(r.Same_Peptides_Assay)
    except Exception: continue
    oth_src, oth_val = [], []
    for s, pv, av in zip(srcs, perm, assay):
        if s == r.Source: continue
        v = [float(x) for x, a in zip(pv, av) if a == "PAMPA" and float(x) > -9.99]
        if v: oth_src.append(s); oth_val.append(float(np.mean(v)))
    if oth_src: anchors.append(dict(row=int(i), source=r.Source, y_self=float(r.PAMPA), y_others=float(np.mean(oth_val)), other_sources=oth_src))
np.savez_compressed(sys.argv[2], fp=fp, y=d["PAMPA"].values.astype(np.float32), src=d["Source"].values.astype(str), rid=d["ID"].values.astype(int))
json.dump(anchors, open(sys.argv[2].replace(".npz", "_anchors.json"), "w"))
import collections
cnt = collections.Counter(d["Source"]); an = collections.Counter(a["source"] for a in anchors)
print("rows", len(d), "sources", len(cnt), "sources>=30 rows", sum(v >= 30 for v in cnt.values()), "anchor rows", len(anchors), "sources with >=3/5/10 anchors", [sum(v >= k for v in an.values()) for k in (3, 5, 10)])
