"""Regression (all pilot-4 folds): p5 scoring with pilot 4's own fold priors reproduces pilot 4's test-half family-equal means (all + hard stratum) for prior_hgb, nn_q3, gp, d_q6_l0.3 at k = 3, 5, 10; per-row differences reported (float32 tie noise across platforms)."""
import os, sys, pickle, json, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C, p5score as S
W = C.world(); fmap4 = json.load(open(f"{C.RES}/pilot4_inferred_foldmap.json")); ev = pd.read_csv(f"{C.P4}/results/eval_test.csv.gz")
want = {"prior": "prior_hgb", "nn_q3": "nn_q3", "gp_2.25_0.25": "gp", "d_q6_l0.3": "d_q6_l0.3"}; rows = []
for f in range(6):
    hold = {fa for fa, k in fmap4.items() if int(k) == f}; FM = pickle.load(open(f"{C.P4}/results/fold{f}.pkl", "rb")); ref = FM["M"]["hgb"].predict(W["X"]); sp_ = C.sigma_p(W, hold)
    tg = sorted(t for t in W["elig"] if W["fam"][t] in hold and (ev.target == t).any())
    for tk in tg: rows += S.eval_target(S.TC(tk, W), ref, sp_, seeds=range(10), ks=(3, 5, 10), want=set(want), full=True)
    print("fold", f, len(tg), "targets", flush=True)
df = pd.DataFrame(rows, columns=S.COLS); df["method"] = df.method.map(want)
m = df.merge(ev, on=["target", "method", "k", "seed"], suffixes=("_5", "_4")); out = dict(n_rows=int(len(m)), n_targets=int(df.target.nunique()), n_families=int(df.family.nunique()))
for a in ("sp", "ndcg", "rec", "sp_h", "ndcg_h", "rec_h"):
    d = (m[a + "_5"] - m[a + "_4"]).abs(); out[f"row_max_{a}"] = float(d.max()); out[f"row_n_diff_{a}"] = int((d > 1e-9).sum())
for col in ("sp", "sp_h", "ndcg_h"):
    a = S.famtab(df, col); b = S.famtab(ev[ev.target.isin(df.target.unique()) & ev.method.isin(want.values()) & ev.k.isin((3, 5, 10))], col)
    dd = {f"{m_}|k{k}": [float(a.loc[(m_, k)].mean()), float(b.loc[(m_, k)].mean())] for m_ in want.values() for k in (3, 5, 10)}
    out[f"famequal_{col}"] = dd; out[f"famequal_max_abs_diff_{col}"] = max(abs(x - y) for x, y in dd.values())
json.dump(out, open(f"{C.RES}/regression_all.json", "w"), indent=1); print(json.dumps({k: v for k, v in out.items() if not k.startswith("famequal_") or k.startswith("famequal_max")}, indent=1))
