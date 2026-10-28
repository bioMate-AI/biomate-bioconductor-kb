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
def boot(v, B=5000, seed=0):
    v = np.asarray(v, float); rng = np.random.default_rng(seed); b = [v[rng.integers(0, len(v), len(v))].mean() for _ in range(B)]
    return dict(n=len(v), mean=round(float(v.mean()), 4), ci=[round(float(np.percentile(b, 2.5)), 4), round(float(np.percentile(b, 97.5)), 4)])
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
for k, o in res.items():
    print(k, "n=%d" % o["n_seeds"], "E-gain:", o["E_gain_mean"])
    for nm in ("kphys - kshuf", "kshuf - none", "kphys - none"):
        print("    %-14s yield %+.1f [%.1f, %.1f]   E-AUROC-gain %+.4f [%.4f, %.4f]" % (nm, o[nm + " [yield]"]["mean"], *o[nm + " [yield]"]["ci"], o[nm + " [E_auroc_gain]"]["mean"], *o[nm + " [E_auroc_gain]"]["ci"]))
