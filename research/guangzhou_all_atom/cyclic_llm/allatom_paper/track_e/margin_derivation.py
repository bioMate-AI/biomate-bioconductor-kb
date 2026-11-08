#!/usr/bin/env python3
"""A5: derive and report the relative margin from TUNING curves only (seeds 100-102, train objectives, new SD-AUC scale). Reads small JSON files; no evaluation seed.
usage: margin_derivation.py TUNE_DIR OUT.json
For each tuning objective family X (files under TUNE_DIR/X): per method the best config by SD-AUC at B=1000; G = SD-AUC(best baseline) - SD-AUC(random_lib);
for fractions f in {0.05, 0.10, 0.20}: m = f*G, and (i) 'calls-equivalent': the budget b at which the best baseline's SD-AUC(b) equals SD-AUC(1000) - m
(i.e. m SD-AUC is what the best baseline gains between b and 1000 calls: m expressed as the fraction of the budget spent), (ii) m in rank terms: the
percentile position within the 1,500-draw generation-space reference of a molecule with z = (top-10 mean z)(random_lib) + m is not computed here (reference not on disk);
instead report the z-gain of the best baseline over random_lib in SD units."""
import glob, json, os, sys
import numpy as np
tdir, out = sys.argv[1], sys.argv[2]
STEP = 5                                     # curves are stored subsampled every 5 calls (run_stage0.one_run)
rows, trunc = {}, {}
for f in glob.glob(os.path.join(tdir, "F*", "*.json")):
    r = json.load(open(f)); fam = f.split(os.sep)[-2]; m, c = r["method"].split("#c")
    # truncated = hit the wall-clock cap (A4c): explicit stop_reason when recorded, else inferred (calls < budget and wall time at the 1,800 s cap)
    cut = (r.get("stop_reason") == "wallclock") or (r.get("stop_reason") is None and r["calls"] < 1000 and r.get("wall_s", 0) >= 1790)
    t = trunc.setdefault((fam, m), dict(n=0, truncated=0, budget_fraction_at_truncation=[], stalled_or_other_early_stop=0))
    t["n"] += 1
    if cut:
        t["truncated"] += 1; t["budget_fraction_at_truncation"].append(round(r["calls"] / 1000.0, 3))
    elif r["calls"] < 1000:
        t["stalled_or_other_early_stop"] += 1
    if not cut:                                    # margin is derived from UNTRUNCATED runs only (A4c rule 4)
        rows.setdefault((fam, m, int(c)), []).append(np.array(r["curve"], float))


def auc_at(cv, b):
    k = max(1, b // STEP)
    return float(cv[:k].mean())


res = {}
for fam in sorted({k[0] for k in rows}):
    best = {}
    for (fm, m, c), cvs in rows.items():
        if fm != fam:
            continue
        a = float(np.mean([auc_at(cv, 1000) for cv in cvs]))
        if m not in best or a > best[m][0]:
            best[m] = (a, c, cvs)
    G = max(v[0] for k, v in best.items() if k != "random_lib") - best["random_lib"][0]
    top = max((k for k in best if k != "random_lib"), key=lambda k: best[k][0])
    cv_top = best[top][2]
    ent = dict(best_baseline=top, sd_auc_best=round(best[top][0], 3), sd_auc_random_lib=round(best["random_lib"][0], 3), gap_G=round(G, 3),
               sd_auc_by_method={k: round(v[0], 3) for k, v in sorted(best.items())}, fractions={})
    for f in (0.05, 0.10, 0.20):
        m_ = f * G; target = best[top][0] - m_; b_eq = None
        for b in range(1000, 4, -STEP):
            if float(np.mean([auc_at(cv, b) for cv in cv_top])) <= target:
                b_eq = b
                break
        ent["fractions"][str(f)] = dict(margin_sd_auc=round(m_, 3), best_baseline_reaches_B1000_minus_margin_at_calls=b_eq,
                                        calls_fraction_of_budget=None if b_eq is None else round(1 - b_eq / 1000.0, 3))
    res[fam] = ent
res["_truncation_by_family_method"] = {f"{k[0]}|{k[1]}": v for k, v in sorted(trunc.items())}
json.dump(res, open(out, "w"), indent=1); print(json.dumps(res, indent=1)[:3000])
