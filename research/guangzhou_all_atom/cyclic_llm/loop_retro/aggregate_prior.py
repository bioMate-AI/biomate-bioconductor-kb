#!/usr/bin/env python3
"""Aggregate L2 results (PREREG_LOOP.md amendment L2): paired vs fp over seeds, 98.75 % percentile intervals (4 knowledge arms). usage: aggregate_prior.py DIR out.json"""
import sys, glob, json, collections
import numpy as np
LO, HI = 0.5, 99.5   # 5 knowledge comparisons -> 99 % intervals (PREREG_LOOP L3)
def ci(v): return [round(float(np.percentile(v, LO)), 1), round(float(np.percentile(v, HI)), 1)]      # NOTE: central range (spread) of the per-seed paired differences, NOT a CI of the mean
_RNG = np.random.default_rng(20261030)
def ci_mean(v, lo=LO, hi=HI, B=10000):
    v = np.asarray(v, float); bs = np.array([_RNG.choice(v, len(v)).mean() for _ in range(B)]); return [round(float(np.percentile(bs, lo)), 1), round(float(np.percentile(bs, hi)), 1)]    # bootstrap CI of the MEAN paired difference over seeds
def analyse(R, gk, rk):
    res = {}
    REGS = [g for g in ("A", "B", "C") if ("fp", g) in R]
    for reg in REGS:
        base = R[("fp", reg)]; res[f"fp_{reg}"] = dict(n_seeds=len(base), total=round(float(np.mean([r[gk] for r in base.values()])), 1), first200=round(float(np.mean([sum(r[rk][:4]) for r in base.values()])), 1))
        for arm in ("kn", "resid_nme", "resid_z", "fuse_nme", "fuse_z"):
            if (arm, reg) not in R: continue
            seeds = sorted(set(R[(arm, reg)]) & set(base)); a = R[(arm, reg)]
            dt = [a[s][gk] - base[s][gk] for s in seeds]; d2 = [sum(a[s][rk][:4]) - sum(base[s][rk][:4]) for s in seeds]
            res[f"{arm}_{reg}"] = dict(n_seeds=len(seeds), total=round(float(np.mean([a[s][gk] for s in seeds])), 1), first200=round(float(np.mean([sum(a[s][rk][:4]) for s in seeds])), 1),
                                       d_total=dict(mean=round(float(np.mean(dt)), 1), ci=ci(dt), ci_mean=ci_mean(dt), lower_gt0=bool(ci(dt)[0] > 0), lower_mean_gt0=bool(ci_mean(dt)[0] > 0)), d_first200=dict(mean=round(float(np.mean(d2)), 1), ci=ci(d2), lower_gt0=bool(ci(d2)[0] > 0)))
    for reg in REGS:                                          # zero-learning rule arms (PREREG_LOOP L5), descriptive: fp minus rule, paired by seed, 95 % interval
        for rule in ("rule_nme", "rule_z"):
            if (rule, reg) in R:
                seeds = sorted(set(R[(rule, reg)]) & set(R[("fp", reg)])); dd = [R[("fp", reg)][s][gk] - R[(rule, reg)][s][gk] for s in seeds]
                res[f"fp_minus_{rule}_{reg}"] = dict(n_seeds=len(seeds), rule_total=round(float(np.mean([R[(rule, reg)][s][gk] for s in seeds])), 1), mean=round(float(np.mean(dd)), 1),
                                                     ci95=[round(float(np.percentile(dd, 2.5)), 1), round(float(np.percentile(dd, 97.5)), 1)], ci95_mean=ci_mean(dd, 2.5, 97.5))
    for reg in REGS:                                          # greedy loop vs random, 95 % interval (PREREG_LOOP L3 outcome a)
        if ("random", reg) in R:
            seeds = sorted(set(R[("random", reg)]) & set(R[("fp", reg)])); dd = [R[("fp", reg)][s][gk] - R[("random", reg)][s][gk] for s in seeds]
            res[f"fp_minus_random_{reg}"] = dict(n_seeds=len(seeds), random=round(float(np.mean([R[("random", reg)][s][gk] for s in seeds])), 1), mean=round(float(np.mean(dd)), 1),
                                                 ci95=[round(float(np.percentile(dd, 2.5)), 1), round(float(np.percentile(dd, 97.5)), 1)], ci95_mean=ci_mean(dd, 2.5, 97.5), lower_gt0=bool(np.percentile(dd, 2.5) > 0), lower_mean_gt0=bool(ci_mean(dd, 2.5, 97.5)[0] > 0))
    res["CLAIM_loop_beats_random_both_regimes"] = bool(res.get("fp_minus_random_A", {}).get("lower_gt0") and res.get("fp_minus_random_B", {}).get("lower_gt0"))
    res["CLAIM_knowledge_prior_or_fusion_helps_both_regimes"] = bool(any(res.get(f"{a}_A", {}).get("d_total", {}).get("lower_gt0") and res.get(f"{a}_B", {}).get("d_total", {}).get("lower_gt0") for a in ("kn", "resid_nme", "resid_z", "fuse_nme", "fuse_z")))
    return res


def main(d, out):
    R = collections.defaultdict(dict)
    for f in glob.glob(f"{d}/*.json"):
        r = json.load(open(f)); R[(r["arm"], r["regime"])][r["seed"]] = r
    res = analyse(R, "greedy", "rounds")
    if any("greedy_g" in r for v in R.values() for r in v.values()):
        res["SENSITIVITY_hit_within_group_top10"] = analyse(R, "greedy_g", "rounds_g")
        ps = collections.defaultdict(lambda: collections.defaultdict(list))
        for (arm, reg), v in R.items():
            for r in v.values():
                if "pick_src" in r: ps[(arm, reg)]["townsend"].append(r["pick_src"]["2020_Townsend"]); ps[(arm, reg)]["kelly"].append(r["pick_src"]["2021_Kelly"]); ps[(arm, reg)]["other"].append(r["pick_src"]["other"])
        res["PICK_SOURCE_MEANS"] = {f"{a}_{g}": {k: round(float(np.mean(x)), 1) for k, x in d_.items()} for (a, g), d_ in sorted(ps.items())}
    json.dump(res, open(out, "w"), indent=1); print(json.dumps(res, indent=1))


if __name__ == "__main__": main(sys.argv[1], sys.argv[2])
