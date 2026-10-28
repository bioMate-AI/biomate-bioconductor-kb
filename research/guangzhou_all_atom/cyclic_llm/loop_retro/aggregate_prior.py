#!/usr/bin/env python3
"""Aggregate L2 results (PREREG_LOOP.md amendment L2): paired vs fp over seeds, 98.75 % percentile intervals (4 knowledge arms). usage: aggregate_prior.py DIR out.json"""
import sys, glob, json, collections
import numpy as np
LO, HI = 0.5, 99.5   # 5 knowledge comparisons -> 99 % intervals (PREREG_LOOP L3)
def ci(v): return [round(float(np.percentile(v, LO)), 1), round(float(np.percentile(v, HI)), 1)]
def main(d, out):
    R = collections.defaultdict(dict)
    for f in glob.glob(f"{d}/*.json"):
        r = json.load(open(f)); R[(r["arm"], r["regime"])][r["seed"]] = r
    res = {}
    REGS = [g for g in ("A", "B", "C") if ("fp", g) in R]
    for reg in REGS:
        base = R[("fp", reg)]; res[f"fp_{reg}"] = dict(n_seeds=len(base), total=round(float(np.mean([r["greedy"] for r in base.values()])), 1), first200=round(float(np.mean([sum(r["rounds"][:4]) for r in base.values()])), 1))
        for arm in ("kn", "resid_nme", "resid_z", "fuse_nme", "fuse_z"):
            if (arm, reg) not in R: continue
            seeds = sorted(set(R[(arm, reg)]) & set(base)); a = R[(arm, reg)]
            dt = [a[s]["greedy"] - base[s]["greedy"] for s in seeds]; d2 = [sum(a[s]["rounds"][:4]) - sum(base[s]["rounds"][:4]) for s in seeds]
            res[f"{arm}_{reg}"] = dict(n_seeds=len(seeds), total=round(float(np.mean([a[s]["greedy"] for s in seeds])), 1), first200=round(float(np.mean([sum(a[s]["rounds"][:4]) for s in seeds])), 1),
                                       d_total=dict(mean=round(float(np.mean(dt)), 1), ci=ci(dt), lower_gt0=bool(ci(dt)[0] > 0)), d_first200=dict(mean=round(float(np.mean(d2)), 1), ci=ci(d2), lower_gt0=bool(ci(d2)[0] > 0)))
    for reg in REGS:                                          # zero-learning rule arms (PREREG_LOOP L5), descriptive: fp minus rule, paired by seed, 95 % interval
        for rule in ("rule_nme", "rule_z"):
            if (rule, reg) in R:
                seeds = sorted(set(R[(rule, reg)]) & set(R[("fp", reg)])); dd = [R[("fp", reg)][s]["greedy"] - R[(rule, reg)][s]["greedy"] for s in seeds]
                res[f"fp_minus_{rule}_{reg}"] = dict(n_seeds=len(seeds), rule_total=round(float(np.mean([R[(rule, reg)][s]["greedy"] for s in seeds])), 1), mean=round(float(np.mean(dd)), 1),
                                                     ci95=[round(float(np.percentile(dd, 2.5)), 1), round(float(np.percentile(dd, 97.5)), 1)])
    for reg in REGS:                                          # greedy loop vs random, 95 % interval (PREREG_LOOP L3 outcome a)
        if ("random", reg) in R:
            seeds = sorted(set(R[("random", reg)]) & set(R[("fp", reg)])); dd = [R[("fp", reg)][s]["greedy"] - R[("random", reg)][s]["greedy"] for s in seeds]
            res[f"fp_minus_random_{reg}"] = dict(n_seeds=len(seeds), random=round(float(np.mean([R[("random", reg)][s]["greedy"] for s in seeds])), 1), mean=round(float(np.mean(dd)), 1),
                                                 ci95=[round(float(np.percentile(dd, 2.5)), 1), round(float(np.percentile(dd, 97.5)), 1)], lower_gt0=bool(np.percentile(dd, 2.5) > 0))
    res["CLAIM_loop_beats_random_both_regimes"] = bool(res.get("fp_minus_random_A", {}).get("lower_gt0") and res.get("fp_minus_random_B", {}).get("lower_gt0"))
    res["CLAIM_knowledge_prior_or_fusion_helps_both_regimes"] = bool(any(res.get(f"{a}_A", {}).get("d_total", {}).get("lower_gt0") and res.get(f"{a}_B", {}).get("d_total", {}).get("lower_gt0") for a in ("kn", "resid_nme", "resid_z", "fuse_nme", "fuse_z")))
    json.dump(res, open(out, "w"), indent=1); print(json.dumps(res, indent=1))
if __name__ == "__main__": main(sys.argv[1], sys.argv[2])
