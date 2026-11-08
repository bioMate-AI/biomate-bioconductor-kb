#!/usr/bin/env python3
"""TRAIN-ONLY CV of the contrastive selector S3 vs the logistic candidates (PREREG A8). Never reads test. usage: stageB_cv_contrastive.py train.jsonl manifest.csv out.json"""
import sys, os, json, csv
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import selector as SEL, stageB_eval as E, selector_contrastive as SC
from stageB_cv import cv
from stageB_cv_features import SETS
LAMS = [0.01, 0.1, 1.0, 10.0]
if __name__ == "__main__":
    tr = E.load(sys.argv[1]); man = {r["complex_id"]: r for r in csv.DictReader(open(sys.argv[2]))}
    cl = {c: man[c]["receptor_cluster40"] for c in tr if c in man}
    res = {"S1_logistic_F_all_C0.1": round(sum(cv(tr, cl, lambda: SEL.Selector(C=0.1, mixed_only=True), s) for s in range(5)) / 5, 3),
           "S2_logistic_F_pl_C1.0": round(sum(cv(tr, cl, lambda: SEL.Selector(C=1.0, feats=SETS["F_pl"], mixed_only=True), s) for s in range(5)) / 5, 3)}
    for name in ("F_pl", "F_all"):
        for lam in LAMS:
            res[f"S3_contrastive_{name}_lam{lam}"] = round(sum(cv(tr, cl, lambda n=name, l=lam: SC.ContrastiveSelector(lam=l, feats=SETS[n]), s) for s in range(5)) / 5, 3)
    best = max((k for k in res if k.startswith("S3_")), key=lambda k: res[k]); res["S3_best_config"] = best; res["S3_best_CV"] = res[best]
    json.dump(res, open(sys.argv[3], "w"), indent=1); print(json.dumps(res, indent=1))
