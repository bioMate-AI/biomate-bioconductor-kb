"""Mechanism check (read-only on workstream 6 per-seed files): does fusing a channel (even a shuffled one) change WHICH compounds the loop picks?
Available per round: counts of picks from 2020_Townsend, 2021_Kelly and 'other'. Reports the share of picks from the two largest labs per arm/regime and the paired
difference to the no-knowledge arm (seed bootstrap 99 % CI of the mean)."""
import glob, json, os, re
import numpy as np
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "loop_retro", "results", "l7_collect", "small")
def share(a):
    t = sum(d.get("2020_Townsend", 0) + d.get("2021_Kelly", 0) for d in a["src"]); n = sum(sum(d.values()) for d in a["src"]); return t / n
R = {}
for dn in sorted(os.listdir(BASE)):
    for f in sorted(glob.glob(os.path.join(BASE, dn, "*.json"))):
        m = re.search(r"_([A-Z])_(\d+)\.json$", f)
        if not m: continue
        r = json.load(open(f))
        if all(a in r for a in ("loop_sub", "loop_kphys_sub", "loop_kshuf_sub")): R.setdefault(f"{dn}|{m.group(1)}", []).append({a: share(r[a]) for a in ("loop_sub", "loop_kphys_sub", "loop_kshuf_sub")})
def boot(v, B=10000):
    v = np.asarray(v); rng = np.random.default_rng(0); b = [v[rng.integers(0, len(v), len(v))].mean() for _ in range(B)]; return [round(float(np.percentile(b, .5)), 3), round(float(np.percentile(b, 99.5)), 3)]
out = {}
for k, L in R.items():
    o = {a: round(float(np.mean([x[a] for x in L])), 3) for a in L[0]}; o["n"] = len(L)
    for nm, a, b in (("kphys-none", "loop_kphys_sub", "loop_sub"), ("kshuf-none", "loop_kshuf_sub", "loop_sub"), ("kphys-kshuf", "loop_kphys_sub", "loop_kshuf_sub")):
        d = [x[a] - x[b] for x in L]; o[nm] = dict(mean=round(float(np.mean(d)), 3), ci99=boot(d))
    out[k] = o
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "kshuf_diversity_audit.json"), "w"), indent=1)
for k, o in out.items(): print(k, {a: o[a] for a in ("loop_sub", "loop_kphys_sub", "loop_kshuf_sub")}, "| kshuf-none %+.3f %s | kphys-none %+.3f %s | kphys-kshuf %+.3f %s" % (o["kshuf-none"]["mean"], o["kshuf-none"]["ci99"], o["kphys-none"]["mean"], o["kphys-none"]["ci99"], o["kphys-kshuf"]["mean"], o["kphys-kshuf"]["ci99"]))
