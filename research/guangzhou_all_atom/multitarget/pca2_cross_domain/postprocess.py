"""Derived numbers from results.json: curve gains k=3->6, and domain count needed to detect a given gain over the best null."""
import json
import numpy as np
from scipy import stats
from common import HERE

R = json.load(open(f"{HERE}/results.json"))
out = {}
pd_ = R["learning_curve_B_pca1_per_domain"]
for n, kk in pd_.items():
    doms = list(kk["1"])
    g = np.array([kk["6"][d] - kk["3"][d] for d in doms]); g1 = np.array([kk["3"][d] - kk["1"][d] for d in doms])
    t = stats.t.ppf(0.975, len(g) - 1)
    out[n] = dict(gain_1_to_3=float(g1.mean()), gain_3_to_6=float(g.mean()),
                  gain_3_to_6_t_ci=[float(g.mean() - t * g.std(ddof=1) / np.sqrt(len(g))), float(g.mean() + t * g.std(ddof=1) / np.sqrt(len(g)))])
need = {}
for key in ("B1_pca1_train", "B2_pca1_plus_pca2_train"):
    S = R[key]; best = S["best_null"]
    for m, v in S["model_minus_best_null"].items():
        d = [S["per_domain"][dm][m]["rho"] - S["per_domain"][dm][best]["rho"] for dm in S["per_domain"]]
        sd = float(np.std(d, ddof=1)); mean = float(np.mean(d))
        row = {"best_null": best, "mean_diff": mean, "sd_diff_across_domains": sd}
        for delta in (0.03, 0.05, 0.10, 0.15):
            n = 3
            while n < 5000 and stats.t.ppf(0.975, n - 1) * sd / np.sqrt(n) > delta:
                n += 1
            row[f"domains_for_ci_to_exclude_0_if_true_gain_{delta}"] = n
        need[f"{key}:{m}"] = row
out["domains_needed_approx_50pct_power"] = need
json.dump(out, open(f"{HERE}/postprocess.json", "w"), indent=1)
print(json.dumps(out, indent=1))
