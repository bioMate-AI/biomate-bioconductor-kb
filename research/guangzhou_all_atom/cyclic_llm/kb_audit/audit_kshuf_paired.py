"""Read-only audit of workstream 6's knowledge-shuffled control. Uses their per-seed result files (loop_retro/results/l7_collect/small/*) and computes, in this
file, (a) the E-AUROC gain of every true-label arm, (b) PAIRED contrasts that actually isolate the rule content: K_phys vs K_shuffled, K_shuffled vs no knowledge,
K_phys vs no knowledge, for yield and E-AUROC gain, with seed-bootstrap CIs. No file of theirs is modified."""
import glob, json, os, re
import numpy as np
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "loop_retro", "results", "l7_collect", "small")
def load(dirname):
    out = {}
    for f in sorted(glob.glob(os.path.join(BASE, dirname, "*.json"))):
        m = re.search(r"_([A-Z])_(\d+)\.json$", os.path.basename(f))
        if not m: continue
        out.setdefault(m.group(1), {})[int(m.group(2))] = json.load(open(f))
    return out
def hits(a): return float(sum(a["hits"]))
def gain(a): return float(a["auroc_E"][-1] - a["auroc_E0"])
def boot(v, B=10000, seed=0):
    """Percentile bootstrap CI of the MEAN over seeds (resample seeds with replacement), at 95 % and 99 %; plus a paired-t 99 % interval as a small-n check.
    These are intervals for the mean paired difference, NOT the spread (SD) of per-seed differences."""
    from scipy import stats
    v = np.asarray(v, float); rng = np.random.default_rng(seed); b = np.array([v[rng.integers(0, len(v), len(v))].mean() for _ in range(B)])
    se = v.std(ddof=1) / np.sqrt(len(v)); t99 = stats.t.ppf(0.995, len(v) - 1)
    return dict(n=len(v), mean=round(float(v.mean()), 4), sd_per_seed=round(float(v.std(ddof=1)), 4), ci95=[round(float(np.percentile(b, 2.5)), 4), round(float(np.percentile(b, 97.5)), 4)],
                ci99=[round(float(np.percentile(b, 0.5)), 4), round(float(np.percentile(b, 99.5)), 4)], t99=[round(float(v.mean() - t99 * se), 4), round(float(v.mean() + t99 * se), 4)])
res = {}
for dn in sorted(os.listdir(BASE)):
    D = load(dn)
    for reg, seeds in D.items():
        arms = ["loop_sub", "loop_kphys_sub", "loop_kshuf_sub", "frozen_sub", "shuffled_sub"]
        S = [s for s, r in seeds.items() if all(a in r for a in arms)]
        if len(S) < 3: continue
        o = {"n_seeds": len(S), "E_gain_mean": {a: round(float(np.mean([gain(seeds[s][a]) for s in S])), 4) for a in arms}}
        for nm, x, y in (("kphys - kshuf", "loop_kphys_sub", "loop_kshuf_sub"), ("kshuf - none", "loop_kshuf_sub", "loop_sub"), ("kphys - none", "loop_kphys_sub", "loop_sub")):
            o[nm + " [yield]"] = boot([hits(seeds[s][x]) - hits(seeds[s][y]) for s in S]); o[nm + " [E_auroc_gain]"] = boot([gain(seeds[s][x]) - gain(seeds[s][y]) for s in S])
        res[f"{dn}|{reg}"] = o
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "kshuf_paired_audit.json"), "w"), indent=1)
import collections
print("configurations:", len(res), list(res)); fam = 3 * 2 * len(res); print("multiplicity family size (3 contrasts x 2 metrics x configurations):", fam)
for lvl in ("ci95", "ci99", "t99"):
    print("== interval:", lvl)
    for nm in ("kphys - kshuf", "kphys - none", "kshuf - none"):
        for f in ("yield", "E_auroc_gain"):
            k = f"{nm} [{f}]"; pos = [c for c, o in res.items() if o[k][lvl][0] > 0]; neg = [c for c, o in res.items() if o[k][lvl][1] < 0]
            print("  %-26s CI>0: %d  CI<0: %d  includes 0: %d   %s%s" % (k, len(pos), len(neg), len(res) - len(pos) - len(neg), ("pos=" + ",".join(p.replace("res7f_", "") for p in pos)) if pos else "", ("  neg=" + ",".join(p.replace("res7f_", "") for p in neg)) if neg else ""))
for k, o in res.items():
    print(k, "n=%d" % o["n_seeds"], "E-gain:", o["E_gain_mean"])
    for nm in ("kphys - kshuf", "kphys - none", "kshuf - none"):
        print("    %-14s yield %+.1f [99%%: %.1f, %.1f]   E-gain %+.4f [99%%: %.4f, %.4f]" % (nm, o[nm + " [yield]"]["mean"], *o[nm + " [yield]"]["ci99"], o[nm + " [E_auroc_gain]"]["mean"], *o[nm + " [E_auroc_gain]"]["ci99"]))
