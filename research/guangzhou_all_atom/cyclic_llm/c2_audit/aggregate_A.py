#!/usr/bin/env python3
"""Aggregate Part A (pre-registered contrasts, family-cluster bootstrap 2000). usage: aggregate_A.py RESDIR OUT.json LOGGED_STDOUT"""
import glob, json, re, sys, collections
import numpy as np
RES, OUT, LOGGED = sys.argv[1:4]
FAM = json.load(open(__file__.replace("aggregate_A.py", "target_family.json")))
rng = np.random.default_rng(0)

def cboot(vals, fams, B=2000):
    """mean over families of per-family means; bootstrap families."""
    f = collections.defaultdict(list)
    for v, fa in zip(vals, fams): f[fa].append(v)
    fm = np.array([np.mean(x) for x in f.values()]); n = len(fm)
    bs = [fm[rng.integers(0, n, n)].mean() for _ in range(B)]
    return dict(mean_over_targets=float(np.mean(vals)), mean_over_families=float(fm.mean()), ci95_family=[float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))], n_targets=len(vals), n_families=n)

out = {}
# ---- A-repro: compare per-target lines with the logged stdout
logged = {}
for l in open(LOGGED):
    m = re.match(r"\s+(\S+) n=\d+ hits=\d+ clust=\d+: learn raw([\d.]+)/nov([\d.]+) fixed raw([\d.]+)/nov([\d.]+) random raw([\d.]+)/nov([\d.]+)", l)
    if m: logged[m.group(1)] = dict(learn=float(m.group(2)), fixed=float(m.group(4)), random=float(m.group(6)))
rp = f"{RES}/A_repro10/c2_result.json"
try:
    R = json.load(open(rp)); rows = []
    for t, meta in R["per_target"].items():
        if t in logged:
            d = {m: abs(meta["raw_final"][m] - logged[t][m]) for m in ("learn", "fixed", "random")}; rows.append((t, d, meta["raw_final"], logged[t]))
    agg = {m: float(np.mean([meta["raw_final"][m] for meta in R["per_target"].values()])) for m in ("learn", "fixed", "random")}
    out["A_repro10"] = dict(aggregate_rerun=agg, aggregate_logged=dict(learn=0.299, fixed=0.249, random=0.118),
        per_target_max_abs_diff={m: float(max(r[1][m] for r in rows)) for m in ("learn", "fixed", "random")}, n_targets=len(rows),
        reproduces=bool(all(r[1][m] <= 0.02 for r in rows for m in r[1]) and all(abs(agg[m] - v) <= 0.01 for m, v in dict(learn=0.299, fixed=0.249, random=0.118).items())),
        per_target=[dict(target=r[0], rerun=r[2], logged=r[3]) for r in rows])
except FileNotFoundError: out["A_repro10"] = "missing"
# ---- A-full106 (launcher configuration)
fp = f"{RES}/A_full106/c2_result.json"
try:
    R = json.load(open(fp)); T = list(R["per_target"]); fams = [FAM.get(t, "NA") for t in T]
    d = {m: np.array([R["per_target"][t]["raw_final"][m] for t in T]) for m in ("learn", "fixed", "random")}
    out["A_full106"] = {c: cboot(a - b, fams) for c, (a, b) in dict(learn_minus_random=(d["learn"], d["random"]), fixed_minus_random=(d["fixed"], d["random"]), learn_minus_fixed=(d["learn"], d["fixed"])).items()}
    out["A_full106"]["means"] = {m: float(v.mean()) for m, v in d.items()}; out["A_full106"]["n_targets"] = len(T)
    non = [i for i, t in enumerate(T) if FAM.get(t) != "F997e29c2"]
    out["A_full106"]["learn_minus_fixed_excluding_GPCR_family"] = cboot((d["learn"] - d["fixed"])[non], [fams[i] for i in non]) if non else None
except FileNotFoundError: out["A_full106"] = "missing"
# ---- A-ext
rows = [r for f in glob.glob(f"{RES}/A_ext/*.json") for r in json.load(open(f))]
if rows:
    key = lambda r: (r["ctrl"], r["bg"], r["mode"])
    per = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in rows: per[key(r)][r["target"]].append(r["curve"][-1])
    tm = {k: {t: float(np.mean(v)) for t, v in d.items()} for k, d in per.items()}
    def contrast(a, b, only=None):
        ts = sorted(set(tm.get(a, {})) & set(tm.get(b, {})) & (set(only) if only else set(tm.get(a, {}))))
        return None if not ts else cboot(np.array([tm[a][t] - tm[b][t] for t in ts]), [FAM.get(t, "NA") for t in ts])
    ext = {"cell_means": {"|".join(k): float(np.mean(list(d.values()))) for k, d in tm.items()}, "n_targets": {"|".join(k): len(d) for k, d in tm.items()}}
    R_ = ("real", "any", "random"); N_ = ("real", "any", "nn")
    for bg in ("full", "famdisjoint", "none"):
        ext[f"learn-random|{bg}"] = contrast(("real", bg, "learn"), R_); ext[f"fixed-random|{bg}"] = contrast(("real", bg, "fixed"), R_)
        ext[f"learn-fixed|{bg}"] = contrast(("real", bg, "learn"), ("real", bg, "fixed")); ext[f"learn-nn|{bg}"] = contrast(("real", bg, "learn"), N_)
    for bg in ("full", "famdisjoint"): ext[f"desc-random|{bg}"] = contrast(("real", bg, "desc"), R_)
    ext["nn-random"] = contrast(N_, R_)
    for c in ("shuffled", "planted"):
        for m in ("learn", "fixed", "nn"): ext[f"{c}:{m}-random"] = contrast((c, "famdisjoint", m), (c, "famdisjoint", "random"))
    fx_full = ext["fixed-random|full"]; fx_fam = ext["fixed-random|famdisjoint"]
    if fx_full and fx_fam and fx_full["mean_over_targets"] != 0:
        ext["H_leak_ratio_fixed_margin_famdisjoint_over_full"] = fx_fam["mean_over_targets"] / fx_full["mean_over_targets"]
    out["A_ext"] = ext
json.dump(out, open(OUT, "w"), indent=1); print(json.dumps(out, indent=1)[:6000])
