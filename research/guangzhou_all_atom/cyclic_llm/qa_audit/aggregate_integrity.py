"""T-QA independent aggregate-integrity check (does NOT import aggregate_l7).
1. counts raw res7* files per (dir, backend, regime) and arms; flags duplicate (backend,regime,seed) across dirs (the C1 key collision);
2. compares with l7_aggregate.json n_seeds / inputs.n_files;
3. recomputes headline numbers per directory straight from raw files (own bootstrap, seed 12345, B=20000)."""
import json, glob, os, sys, collections, numpy as np
RO = os.path.join(os.path.dirname(__file__), "..", "loop_retro")
SM = os.path.join(RO, "results", "l7_collect", "small"); AGG = os.path.join(RO, "results", "l7_aggregate.json")
agg = json.load(open(AGG)) if os.path.exists(AGG) else {}
LEARNER = {"res7f_gbm_aware": "gbm_aware", "res7f_gbm_blind": "gbm_blind", "res7f_gbm_phys": "gbm_physchem", "res7a_chemberta": "chemberta"}  # directory -> aggregate learner key (post-C1 fix)
files = sorted(glob.glob(f"{SM}/*/*.json")); R = collections.defaultdict(dict); armsets = collections.defaultdict(set); cnt = collections.Counter(); owners = collections.defaultdict(list)
for f in files:
    r = json.load(open(f)); d = os.path.basename(os.path.dirname(f))
    if "backend" not in r: print("NO backend key:", f); continue
    k = (d, r["backend"], r["regime"]); cnt[k] += 1; R[k][r["seed"]] = r
    armsets[k] |= {a for a, v in r.items() if isinstance(v, dict) and "hits" in v}; owners[(LEARNER.get(d, r["backend"]), r["regime"], r["seed"])].append(d)
print("== raw file counts (dir, backend, regime): n files / n arms")
for k in sorted(cnt): print(" ", k, cnt[k], len(armsets[k]))
dup = {k: v for k, v in owners.items() if len(set(v)) > 1}
print(f"== duplicate (learner,regime,seed) across directories: {len(dup)} (any such key is overwritten or raises in the aggregator)")
bykey = collections.defaultdict(set)
for (b, rg, s), v in dup.items(): bykey[(b, rg)] |= set(v)
for k, v in sorted(bykey.items()): print("  ", k, sorted(v))
print("== aggregate: inputs", agg.get("inputs"), " raw files:", len(files))
for k, o in sorted(agg.get("small", {}).items()): print("  ", k, "n_seeds", o["n_seeds"])
def h(r, a, n=None): return float(sum(r[a]["hits"][:n])) if a in r else np.nan
def g(r, a): return r[a]["auroc_E"][-1] - r[a]["auroc_E0"] if a in r and r[a].get("auroc_E") else np.nan
def ci(v, lo=2.5, hi=97.5):
    v = np.asarray([x for x in v if x == x]); rng = np.random.default_rng(12345); bs = [rng.choice(v, len(v)).mean() for _ in range(20000)]
    return round(float(v.mean()), 4), [round(float(np.percentile(bs, lo)), 4), round(float(np.percentile(bs, hi)), 4)], len(v)
def pair(rs, f, a, b): return [f(r, a) - f(r, b) for _, r in sorted(rs.items()) if a in r and b in r]
print("== independent headline numbers from raw files, per directory")
for k in sorted(R):
    d, b, rg = k; rs = R[k]; print(f"-- {d} {b} {rg} (n={len(rs)})")
    for a in ("loop_sub", "frozen_sub", "loop_kphys_sub", "loop_kshuf_sub", "loop", "random_fb", "frozen", "shuffled", "one_shot"):
        v = [h(r, a) for r in rs.values() if a in r]
        if v: print(f"   yield {a}: mean {np.mean(v):.2f} n={len(v)}")
    for nm, a, c, f, lo, hi in (("loop_sub-frozen_sub", "loop_sub", "frozen_sub", h, 2.5, 97.5), ("kphys-loop_sub", "loop_kphys_sub", "loop_sub", h, .5, 99.5), ("kphys-kshuf", "loop_kphys_sub", "loop_kshuf_sub", h, .5, 99.5),
                                 ("loop-random_fb", "loop", "random_fb", h, 2.5, 97.5), ("loop-frozen", "loop", "frozen", h, 2.5, 97.5), ("loop-shuffled", "loop", "shuffled", h, 2.5, 97.5), ("loop-one_shot [Egain]", "loop", "one_shot", g, 2.5, 97.5),
                                 ("kphys-kshuf [Egain]", "loop_kphys_sub", "loop_kshuf_sub", g, .5, 99.5)):
        v = pair(rs, f, a, c)
        if v: print(f"   {nm}: mean {ci(v, lo, hi)}")
    z = [r["loop_sub"]["stereo_rho"][-1] for r in rs.values() if "loop_sub" in r and r["loop_sub"].get("stereo_rho")]
    if z: print(f"   zero_sibling loop_sub: {np.mean(z):.3f} (n={len(z)})")
bad = 0; ncell = 0
for key, o in agg.get("small", {}).items():
    L, rg = key.split("|"); dn = [d for d, v in LEARNER.items() if v == L]
    if len(dn) != 1: print("UNMAPPED aggregate key", key); bad += 1; continue
    rs = [r for (d, b, g), x in R.items() if d == dn[0] and g == rg for r in x.values()]
    if len(rs) != o["n_seeds"]: print("N MISMATCH", key, len(rs), o["n_seeds"]); bad += 1
    for arm, st in o["yield_total"].items():
        v = [sum(r[arm]["hits"]) for r in rs if arm in r and r[arm].get("hits")]; ncell += 1   # arms with an empty hits list (one_shot reveals nothing) are n=0 in the aggregate by design
        if len(v) != st["n"] or abs(np.mean(v) - st["mean"]) > 1e-3: print("CELL DIFF yield", key, arm, np.mean(v), st); bad += 1
    for arm, st in o["E_auroc_gain"].items():
        v = [r[arm]["auroc_E"][-1] - r[arm]["auroc_E0"] for r in rs if arm in r and r[arm].get("auroc_E") and r[arm].get("auroc_E0") is not None]; ncell += 1
        if len(v) != st["n"] or (v and abs(np.mean(v) - st["mean"]) > 1e-3): print("CELL DIFF auroc", key, arm, len(v), st); bad += 1
exp = {k: sum(1 for _ in R_) for k, R_ in {(d, g): x for (d, b, g), x in R.items()}.items()}
print(f"== aggregate-vs-raw: {ncell} yield/E-AUROC cells compared, {bad} problems; aggregate keys {len(agg.get('small', {}))} vs raw (dir,regime) groups {len(exp)}")
if "--strict" in sys.argv and (dup or bad or len(agg.get("small", {})) != len(exp)): sys.exit(1)
