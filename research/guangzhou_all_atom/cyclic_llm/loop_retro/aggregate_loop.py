#!/usr/bin/env python3
"""Aggregate per-task loop results (PREREG_LOOP.md + L1). usage: aggregate_loop.py DIR out.json
Paired over seeds; 95% percentile intervals. Claims follow the pre-registered rules exactly; incomplete seed sets are reported, not hidden."""
import sys, os, json, glob, collections
import numpy as np

def ci(v):
    v = sorted(v); n = len(v); return [round(float(v[int(.025 * n)]), 2), round(float(v[min(n - 1, int(.975 * n))]), 2)]

def main(d, out):
    R = collections.defaultdict(dict)
    for f in glob.glob(f"{d}/*.json"):
        r = json.load(open(f)); R[(r["arm"], r["regime"])][r["seed"]] = r
    res = {"n_tasks": sum(len(v) for v in R.values())}
    for (arm, reg), by in sorted(R.items()):
        seeds = sorted(by); blk = {"n_seeds": len(seeds), "pool_size_mean": int(np.mean([by[s]["n_pool"] for s in seeds]))}
        for p in ("random", "greedy", "ucb", "oracle"):
            v = [by[s][p] for s in seeds]; blk[p] = dict(mean=round(float(np.mean(v)), 2), ci95=ci(v))
        for p in ("greedy", "ucb"):
            dd = [by[s][p] - by[s]["random"] for s in seeds]; blk[f"{p}_minus_random"] = dict(mean=round(float(np.mean(dd)), 2), ci95=ci(dd), lower_gt0=bool(ci(dd)[0] > 0))
        res[f"{arm}_{reg}"] = blk
    # primary claim (fingerprint arm): greedy or ucb beats random in BOTH regimes
    def beats(arm, reg): return any(res.get(f"{arm}_{reg}", {}).get(f"{p}_minus_random", {}).get("lower_gt0", False) for p in ("greedy", "ucb"))
    res["CLAIM_loop_beats_random_both_regimes_fp"] = bool(beats("fp", "A") and beats("fp", "B"))
    # amendment L1: knowledge arm minus fingerprint arm (paired by seed), greedy / ucb
    for reg in ("A", "B"):
        if ("kn", reg) in R and ("fp", reg) in R:
            seeds = sorted(set(R[("kn", reg)]) & set(R[("fp", reg)]))
            for p in ("greedy", "ucb"):
                dd = [R[("kn", reg)][s][p] - R[("fp", reg)][s][p] for s in seeds]
                res[f"L1_kn_minus_fp_{p}_{reg}"] = dict(n_seeds=len(seeds), mean=round(float(np.mean(dd)), 2), ci95=ci(dd), lower_gt0=bool(ci(dd)[0] > 0))
    res["CLAIM_knowledge_helps_both_regimes"] = bool(all(any(res.get(f"L1_kn_minus_fp_{p}_{reg}", {}).get("lower_gt0", False) for p in ("greedy", "ucb")) for reg in ("A", "B")))
    json.dump(res, open(out, "w"), indent=1); print(json.dumps(res, indent=1))

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
