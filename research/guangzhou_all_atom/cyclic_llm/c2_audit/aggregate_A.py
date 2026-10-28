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
# ---- stdout parser (the committed script crashes at its summary step when C2_MODES omits ucb/thompson: KeyError 'ucb' -> no c2_result.json)
LINE = re.compile(r"\s+(\S+) n=(\d+) hits=(\d+) clust=(\d+): learn raw([\d.]+)/nov([\d.]+) fixed raw([\d.]+)/nov([\d.]+) random raw([\d.]+)/nov([\d.]+)")
def parse(path):
    d = {}
    for l in open(path):
        m = LINE.search(l.split("]", 1)[-1] if "]" in l[:12] else l)
        if m: d[m.group(1)] = dict(learn=float(m.group(5)), fixed=float(m.group(7)), random=float(m.group(9)), nov=dict(learn=float(m.group(6)), fixed=float(m.group(8)), random=float(m.group(10))))
    return d
logged = parse(LOGGED)
try:
    rr = parse(f"{RES}/A_repro10/stdout.txt"); ts = [t for t in rr if t in logged]
    diff = {m: float(max(abs(rr[t][m] - logged[t][m]) for t in ts)) for m in ("learn", "fixed", "random")}
    agg = {m: float(np.mean([rr[t][m] for t in ts])) for m in ("learn", "fixed", "random")}
    out["A_repro10"] = dict(aggregate_rerun=agg, aggregate_logged={m: float(np.mean([logged[t][m] for t in ts])) for m in ("learn", "fixed", "random")}, per_target_max_abs_diff=diff, n_targets=len(ts),
        reproduces=bool(all(v <= 0.02 for v in diff.values()) and all(abs(agg[m] - float(np.mean([logged[t][m] for t in ts]))) <= 0.01 for m in agg)),
        per_target=[dict(target=t, rerun={m: rr[t][m] for m in ("learn", "fixed", "random")}, logged={m: logged[t][m] for m in ("learn", "fixed", "random")}) for t in ts])
except FileNotFoundError: out["A_repro10"] = "missing"
try:
    ff = parse(f"{RES}/A_full106/stdout.txt"); T = list(ff); fams = [FAM.get(t, "NA") for t in T]
    d = {m: np.array([ff[t][m] for t in T]) for m in ("learn", "fixed", "random")}
    out["A_full106"] = {c: cboot(a - b, fams) for c, (a, b) in dict(learn_minus_random=(d["learn"], d["random"]), fixed_minus_random=(d["fixed"], d["random"]), learn_minus_fixed=(d["learn"], d["fixed"])).items()}
    out["A_full106"]["means"] = {m: float(v.mean()) for m, v in d.items()}; out["A_full106"]["n_targets"] = len(T)
    non = [i for i, t in enumerate(T) if FAM.get(t) != "F997e29c2"]
    out["A_full106"]["learn_minus_fixed_excluding_GPCR_family"] = cboot((d["learn"] - d["fixed"])[non], [fams[i] for i in non]) if non else None
    out["A_full106"]["source"] = "per-target stdout lines (script crashes before writing c2_result.json)"
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
