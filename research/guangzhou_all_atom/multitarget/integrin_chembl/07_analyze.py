"""Step 7: metrics, strongest-null comparison, claim rule. usage: python3 07_analyze.py  (reads data/preds/*.csv.gz, writes results.json)"""
import json, os, sys, numpy as np, pandas as pd
from metrics import *
PD = os.environ.get("INTEGRIN_OUT", "data/preds"); B = int(os.environ.get("BOOT", 2000))
SPLITS = ["S0", "S1", "S2", "S2b", "S3", "S3b"]; GROUP = dict(S0="cluster", S1="cluster", S2="doc", S2b="doc", S3="ck", S3b="ck")
M1 = ["M1", "M2", "M3", "M4"]; N1 = ["N1", "N2", "N3", "N4", "N4b", "N5"]
M2 = ["M1d", "M2d", "M3d", "M4d", "M5", "M6"]; N2 = ["Z", "N1p", "N5"]
AVB6_PARTNERS = {"avb3", "avb5", "avb8", "a5b1"}
def orient_avb6(d):
    d = d[((d.tA == "avb6") & d.tB.isin(AVB6_PARTNERS)) | ((d.tB == "avb6") & d.tA.isin(AVB6_PARTNERS))].copy(); flip = (d.tB == "avb6").values
    for c in ["delta"] + [c for c in M2 + N2 if c in d]: d[c] = np.where(flip, -d[c], d[c])
    d["tA"], d["tB"] = np.where(flip, d.tB, d.tA), np.where(flip, d.tA, d.tB); return d
def expand_both(d):
    a = d.copy(); b = d.copy(); b["tA"], b["tB"] = d.tB.values, d.tA.values
    for c in ["delta"] + [c for c in M2 + N2 if c in d]: b[c] = -d[c].values
    return pd.concat([a, b], ignore_index=True)
def compare(y, models, nulls, groups, fn, lower_better, B, tag):
    allp = {**models, **nulls}; pt, dr = boot_metric(y, allp, groups, fn, B)
    res = {k: dict(value=pt[k], ci=ci(dr[k])) for k in allp}
    best_null = (min if lower_better else max)(nulls, key=lambda k: pt[k]); best_model = (min if lower_better else max)(models, key=lambda k: pt[k])
    out = dict(metric=tag, models={k: res[k] for k in models}, nulls={k: res[k] for k in nulls}, strongest_null=best_null, best_model_this_split=best_model)
    return out, pt, dr
def diff(pt, dr, m, n, lower_better):
    d = dr[m] - dr[n]; lo, hi = ci(d); fav = (hi < 0) if lower_better else (lo > 0); unfav = (lo > 0) if lower_better else (hi < 0)
    return dict(model=m, null=n, point=float(pt[m] - pt[n]), ci=[lo, hi], verdict="BEATS_NULL" if fav else ("WORSE_THAN_NULL" if unfav else "NO_DIFFERENCE"))
R = {"meta": dict(B=B)}
T = {}
for s in SPLITS:
    f1 = f"{PD}/{s}_t1.csv.gz"
    if not os.path.exists(f1): continue
    t1 = pd.read_csv(f1); t2 = pd.read_csv(f"{PD}/{s}_t2.csv.gz"); g = GROUP[s]
    nulls1 = [n for n in N1 if n in t1]; r = {}
    # T1
    o, pt, dr = compare(t1.y, {m: t1[m] for m in M1}, {n: t1[n] for n in nulls1}, t1[g], rmse, True, B, "RMSE (pooled)")
    o["n_rows"] = len(t1); o["n_groups"] = int(t1[g].nunique()); T[(s, "T1")] = (pt, dr)
    o["spearman_point"] = {k: spearman(t1[k], t1.y) for k in M1 + nulls1}
    o["per_target_rmse"] = {t: {k: rmse(x[k], x.y) for k in M1 + ["N1"]} | {"n": len(x)} for t, x in t1.groupby("t")}
    o["doc_macro_rmse"] = {k: float(t1.groupby("doc").apply(lambda x: rmse(x[k], x.y), include_groups=False).mean()) for k in M1 + nulls1}
    r["T1"] = o
    # T2 all pairs and avb6 subset
    for name, d in [("T2", t2), ("T2_avb6", orient_avb6(t2))]:
        if len(d) < 5: continue
        o, pt, dr = compare(d.delta, {m: d[m] for m in M2}, {n: d[n] for n in N2}, d[g], rmse, True, B, "RMSE of delta (pooled)")
        o["n_pairs"] = len(d); o["n_groups"] = int(d[g].nunique()); T[(s, name)] = (pt, dr)
        o["spearman_point"] = {k: spearman(d[k], d.delta) for k in M2 + N2}; o["sign_acc_abs>=0.3_point"] = {k: sign_acc(d[k], d.delta) for k in M2 + N2}
        o["per_pair"] = {f"{a}-{b}": {k: rmse(x[k], x.delta) for k in ["M1d", "M5", "M6", "Z", "N1p"]} | {"n": len(x), "n_groups": int(x[g].nunique())} for (a, b), x in d.groupby(["tA", "tB"]) if x[g].nunique() >= 10 or name == "T2_avb6"}
        r[name] = o
    # T3
    for name, d in [("T3", expand_both(t2)), ("T3_avb6", orient_avb6(t2))]:
        if len(d) < 5: continue
        lab = (d.delta >= 1).astype(int).values; fn = lambda p, y: auroc(p, y)
        o, pt, dr = compare(lab, {m: d[m] for m in M2}, {n: d[n] for n in N2}, d[g], fn, False, B, "AUROC (pooled; label = delta>=1)")
        o["n_pairs_oriented"] = len(d); o["n_positive"] = int(lab.sum()); o["n_groups"] = int(d[g].nunique()); T[(s, name)] = (pt, dr); r[name] = o
    R[s] = r
# claim rule: best model chosen on S2 per task, compared with the strongest null of each split
claims = {}
for task, models, lb in [("T1", M1, True), ("T2", M2, True), ("T3", M2, False), ("T2_avb6", M2, True), ("T3_avb6", M2, False)]:
    if ("S2", task) not in T: continue
    pt2, _ = T[("S2", task)]; best = (min if lb else max)(models, key=lambda k: pt2[k]); c = dict(best_model_selected_on_S2=best)
    for s in SPLITS:
        if (s, task) not in T: continue
        pt, dr = T[(s, task)]; sn = R[s][task]["strongest_null"]; c[s] = diff(pt, dr, best, sn, lb); c[s]["n_groups"] = R[s][task]["n_groups"]
    ok2 = c["S2"]["verdict"]; ok3 = c.get("S3", {}).get("verdict", "NA")
    c["verdict"] = "POSITIVE" if ok2 == "BEATS_NULL" and ok3 == "BEATS_NULL" else ("NEGATIVE" if "WORSE_THAN_NULL" in (ok2, ok3) else "NULL")
    if c["verdict"] != "POSITIVE" and any(c.get(s, {}).get("verdict") == "BEATS_NULL" for s in ["S0", "S1"]): c["note"] = "beats null under S0/S1 (within-series interpolation) but not under both S2 and S3"
    claims[task] = c
R["claims"] = claims
# permutation check (labels permuted across all rows (plus a within-document variant)): real vs permuted spearman for best T1 model and T2 model under S2
rng = np.random.RandomState(7)
if os.path.exists(f"{PD}/S2_t1.csv.gz"):
    t1 = pd.read_csv(f"{PD}/S2_t1.csv.gz"); t2 = pd.read_csv(f"{PD}/S2_t2.csv.gz"); pc = {}
    for nm, d, col, yc in [("T1", t1, claims["T1"]["best_model_selected_on_S2"], "y"), ("T2", t2, claims["T2"]["best_model_selected_on_S2"], "delta")]:
        real = spearman(d[col], d[yc]); perm = []; rm_real = rmse(d[col], d[yc]); rm_perm = []; permw = []
        for _ in range(200):
            y = pd.Series(rng.permutation(d[yc].values)); perm.append(spearman(d[col], y)); rm_perm.append(rmse(d[col], y))
            permw.append(spearman(d[col], d.groupby("doc")[yc].transform(lambda s: rng.permutation(s.values))))
        pc[nm] = dict(model=col, spearman_real=real, spearman_permuted_mean=float(np.mean(perm)), spearman_within_doc_permuted_mean=float(np.mean(permw)), spearman_permuted_p95=float(np.percentile(perm, 95)), rmse_real=rm_real, rmse_permuted_mean=float(np.mean(rm_perm)))
    ys = np.where(rng.rand(len(t2) * 2) < 0.5, 1, 0); pc["T3_auroc_random_labels"] = auroc(rng.rand(len(ys)), ys)
    R["permutation_check_S2"] = pc
json.dump(R, open("results.json", "w"), indent=1, default=float)
print(json.dumps({k: {x: v for x, v in c.items() if x in ("best_model_selected_on_S2", "S2", "S3", "verdict", "S1", "S0")} for k, c in claims.items()}, indent=1, default=float))
