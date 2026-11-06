#!/usr/bin/env python3
"""TRAIN-ONLY feature-set CV (PREREG A7). Never reads test scores. usage: stageB_cv_features.py train.jsonl manifest.csv out.json"""
import sys, os, json, csv
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import selector as SEL, stageB_eval as E
from stageB_cv import cv, GRID

ALL = list(SEL.FEATURES)
SETS = {"F_all": ALL,
        "F_noConsRing": [f for f in ALL if not f.startswith(("cons_", "ring_"))],
        "F_conf": ["confidence_score", "ptm", "iptm", "protein_iptm", "ligand_iptm", "complex_plddt", "complex_iplddt", "complex_pde", "complex_ipde", "iptm_pep_rec", "pep_plddt", "if_plddt", "pae_if", "pae_pep_to_rec"],
        "F_pl": ["pep_plddt", "if_plddt", "complex_iplddt"]}
if __name__ == "__main__":
    tr = E.load(sys.argv[1]); man = {r["complex_id"]: r for r in csv.DictReader(open(sys.argv[2]))}
    cl = {c: man[c]["receptor_cluster40"] for c in tr if c in man}; res = {"n_features": {k: len(v) for k, v in SETS.items()}}
    for name, feats in SETS.items():
        for C in GRID:
            res[f"{name}_C{C}"] = round(sum(cv(tr, cl, lambda feats=feats, C=C: SEL.Selector(C=C, feats=feats, mixed_only=True), s) for s in range(5)) / 5, 3)
    s1 = max(res[f"F_all_C{C}"] for C in GRID); best = max((k for k in res if k.startswith("F_") and "_C" in k), key=lambda k: res[k])
    res["S1_best_CV"] = s1; res["best_config"] = best; res["best_CV"] = res[best]; res["gain_over_S1_pp"] = round(100 * (res[best] - s1), 2)
    res["ADOPT_new_primary"] = bool(res[best] - s1 >= 0.015 - 1e-9)
    json.dump(res, open(sys.argv[3], "w"), indent=1); print(json.dumps(res, indent=1))
