"""Regression against pilot 4 BEFORE any pilot-5 evaluation: (a) p5 prior fit reproduces pilot 4's fold-model HGB prior; (b) p5 scoring reproduces pilot 4's saved per-target/seed/k Spearman (all, hard) for prior_hgb, nn_q3, gp, d_q6_l0.3 on test-half targets of a pilot-4 fold."""
import os, sys, pickle, json, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C, p5score as S
import p4models as M4
FOLD = int(sys.argv[1]) if len(sys.argv) > 1 else 0
W = C.world(); W4 = M4.load_world(); fmap4 = W4["fmap"]; hold = {fa for fa, k in fmap4.items() if k == FOLD}
FM = pickle.load(open(f"{C.P4}/results/fold{FOLD}.pkl", "rb")); h4 = FM["M"]["hgb"]
pr = C.fit_prior(W, hold); ref = h4.predict(W["X"]); d = float(np.max(np.abs(pr - ref)))
print("(a) prior reproduction fold", FOLD, "max |p5 - p4| over all compounds =", d)
ev = pd.read_csv(f"{C.P4}/results/eval_test.csv.gz"); tg = sorted(t for t in W["elig"] if W["fam"][t] in hold and (ev.target == t).any())
print("test-half targets in this fold:", len(tg))
want = {"prior": "prior_hgb", "nn_q3": "nn_q3", "gp_2.25_0.25": "gp", "d_q6_l0.3": "d_q6_l0.3"}; worst = 0.0; n = 0
for tk in tg:
    tc = S.TC(tk, W); rec = S.eval_target(tc, ref, C.sigma_p(W, hold), seeds=range(10), ks=(3, 5, 10), want=set(want), full=True)
    df = pd.DataFrame(rec, columns=S.COLS); df["method"] = df.method.map(want)
    m = df.merge(ev[ev.target == tk], on=["target", "method", "k", "seed"], suffixes=("_5", "_4"))
    for a in ("sp", "ndcg", "rec", "sp_h", "ndcg_h", "rec_h"):
        x, y = m[a + "_5"].values, m[a + "_4"].values; ok = ~(np.isnan(x) & np.isnan(y)); worst = max(worst, float(np.nanmax(np.abs(x[ok] - y[ok])))) if ok.any() else worst
    n += len(m)
print("(b) rescoring: compared", n, "rows; max abs difference in sp/ndcg/rec (all+hard) =", worst)
json.dump(dict(fold=FOLD, prior_max_abs_diff=d, rows_compared=n, score_max_abs_diff=worst, n_targets=len(tg)), open(f"{C.RES}/regression_fold{FOLD}.json", "w"))
