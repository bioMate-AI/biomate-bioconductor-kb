"""Descriptive extras for testbed 1 (not part of the registered criteria): (i) multiplicity view for 'some k' (3 k tested): 98.33% (Bonferroni) lab-bootstrap CI of F - best component,
(ii) per-lab differences. Reads results/perm_cells_nopt.csv."""
import os, json, numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); df = pd.read_csv(f"{HERE}/results/perm_cells_nopt.csv"); pl = df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index(); out = {}; B = 5000
for k, g in pl.groupby("k"):
    W = g.pivot(index="lab", columns="arm", values="spearman"); ok = W[["K", "A", "F1_5", "F2_5"]].dropna(); best = "K" if ok.K.mean() >= ok.A.mean() else "A"; out[str(k)] = dict(best=best, n_labs=len(ok))
    for f in ("F1_5", "F2_5"):
        dlt = (ok[f] - ok[best]).values; rng = np.random.default_rng(9); idx = rng.integers(0, len(dlt), (B, len(dlt))); m = dlt[idx].mean(1)
        out[str(k)][f] = dict(mean=float(dlt.mean()), ci95=[float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))], ci98_33=[float(np.percentile(m, 0.833)), float(np.percentile(m, 99.167))],
                              labs_positive=int((dlt > 0).sum()), per_lab={l: round(float(x), 3) for l, x in zip(ok.index, dlt)})
json.dump(out, open(f"{HERE}/results/perm_extras.json", "w"), indent=1)
for k, v in out.items():
    print("k", k, "best", v["best"], "labs", v["n_labs"])
    for f in ("F1_5", "F2_5"): x = v[f]; print("  %s mean %+.3f  95%% CI [%.3f, %.3f]  Bonferroni(3) 98.3%% CI [%.3f, %.3f]  labs>0 %d/%d" % (f, x["mean"], *x["ci95"], *x["ci98_33"], x["labs_positive"], v["n_labs"]))
    print("  F1 per lab:", v["F1_5"]["per_lab"])
