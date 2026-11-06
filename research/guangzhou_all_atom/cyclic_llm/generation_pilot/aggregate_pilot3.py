#!/usr/bin/env python3
"""Aggregate pilot 3 TEST results per the pre-registration (docs/20261031_GENERATION_PILOT3_PREREG.md sections 6, 9). usage: aggregate_pilot3.py TEST_DIR OUT.json
Gates G1-G3 per generator; 'LLM wins' = some LLM generator with G1 PASS whose Y minus the best tuned simple generator's Y has BOTH t-interval and percentile-bootstrap lower bounds > 0;
NO-ONE-PRODUCES if the best simple Y < 5 per 1000; UNDERPOWERED if the CI width of the difference exceeds 50% of the best simple Y."""
import sys, os, json, numpy as np
from scipy import stats
d, out = sys.argv[1], sys.argv[2]
G = {}
for f in sorted(os.listdir(d)):
    if f.startswith("test_") and f.endswith(".json"): r = json.load(open(os.path.join(d, f))); G[r["gen"]] = r
SIMPLE = [g for g in ("S-EDIT", "S-LIB", "S-BRICS") if g in G]; LLM = [g for g in ("L-P0", "L-CHEMFM", "L-PCLM2") if g in G]
P0_NME_TV = 0.8173


def vals(g, k): return np.array(G[g]["summary"][k]["per_seed"], float) if k in G[g]["summary"] else np.array([])


def ci_t(v):
    n = len(v)
    if n < 2: return [None, None]
    h = stats.t.ppf(0.975, n - 1) * v.std(ddof=1) / np.sqrt(n); return [round(float(v.mean() - h), 3), round(float(v.mean() + h), 3)]


def ci_b(v, B=5000):
    r = np.random.default_rng(0); b = [r.choice(v, len(v)).mean() for _ in range(B)]; return [round(float(np.percentile(b, 2.5)), 3), round(float(np.percentile(b, 97.5)), 3)]


res = {"generators": {}, "n_seeds": {g: len(G[g]["runs"]) for g in G}}
best_simple_nme_tv = min([G[g]["summary"]["nme_TV"]["mean"] for g in SIMPLE if "nme_TV" in G[g]["summary"]] or [None])
for g in G:
    s = G[g]["summary"]; row = {"cfg": G[g]["cfg"], **{k: s[k]["mean"] for k in s}}
    row["G1_validity>=0.90"] = bool(s["validity"]["mean"] >= 0.90); row["G2_macro_within_50pct_rel"] = bool(s["macro_fraction"]["mean"] >= 0.5)
    row["G3_nmeTV<=P0_and<=best_simple"] = bool(s["nme_TV"]["mean"] <= P0_NME_TV and (best_simple_nme_tv is None or s["nme_TV"]["mean"] <= best_simple_nme_tv)) if "nme_TV" in s else False
    row["Y_t_interval"] = s["Y"]["t_interval"]; row["Y_boot_interval"] = s["Y"]["percentile_bootstrap"]
    res["generators"][g] = row
if SIMPLE:
    ysimple = {g: vals(g, "Y").mean() for g in SIMPLE}; bs = max(ysimple, key=ysimple.get); res["best_simple"] = {"gen": bs, "Y": round(float(ysimple[bs]), 3)}
    res["llm_vs_best_simple"] = {}
    for g in LLM:
        n = min(len(vals(g, "Y")), len(vals(bs, "Y"))); diff = vals(g, "Y")[:n] - vals(bs, "Y")[:n]
        ct, cb = ci_t(diff), ci_b(diff) if n >= 2 else [None, None]
        wins = bool(res["generators"][g]["G1_validity>=0.90"] and ct[0] is not None and ct[0] > 0 and cb[0] > 0)
        yc = vals(g, "Y_cluster"); ycs = vals(bs, "Y_cluster"); collapse = bool(len(yc) and len(ycs) and yc.mean() < ycs.mean() and wins)
        width = (ct[1] - ct[0]) if ct[0] is not None else None
        res["llm_vs_best_simple"][g] = dict(n_seeds=n, diff_mean=round(float(diff.mean()), 3), t_interval=ct, percentile_bootstrap=cb, wins=wins, mode_collapse_flag=collapse,
                                            underpowered=bool(width is None or width > 0.5 * ysimple[bs]))
    if ysimple[bs] < 5: res["verdict"] = "NO-ONE-PRODUCES"
    elif any(v["wins"] and not v["mode_collapse_flag"] for v in res["llm_vs_best_simple"].values()): res["verdict"] = "LLM WINS (pilot gate passed)"
    elif res["llm_vs_best_simple"] and all(v["underpowered"] for v in res["llm_vs_best_simple"].values()): res["verdict"] = "UNDERPOWERED"
    else: res["verdict"] = "SIMPLE GENERATOR WINS or no detectable LLM advantage at this width"
# controls
ctrl = {}
for g in ("C-COPY", "C-RANDINIT-P0", "C-RANDINIT-PCLM2", "C-SHUF-PCLM2"):
    if g in G: ctrl[g] = {k: G[g]["summary"][k]["mean"] for k in ("validity", "novelty_of_unique", "Y") if k in G[g]["summary"]}
res["controls"] = ctrl
json.dump(res, open(out, "w"), indent=1, default=float); print(json.dumps(res, indent=1, default=float))
