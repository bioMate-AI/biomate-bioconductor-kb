"""Re-evaluation requested by the independent code review (M1, M8): percentile and t-based cluster intervals side by side; non-inferiority on the CI lower bound.
Reads the stored cell files of T1 (fusion/results) and T1b (fusion_b/results); no new fitting. Writes results/reeval_intervals.json.
Readings per (study, testbed, arm, k): difference vs the best comparator (chosen on the evaluation clusters, as registered), cluster = lab (permeability) or family (binding).
  (b) 'gain': mean >= +0.02 AND lower bound > 0, under four interval types: percentile-nominal, t-nominal (df = n-1), percentile-Bonferroni(3), t-Bonferroni(3).
  (a) 'non-inferior': registered reading = POINT >= -0.03 (both T1 and T1b registrations); CI readings = lower bound (95 %, nominal) > -0.03 (registered margin applied to a CI) and > -0.05 (formal margin of T1b section 5), percentile and t."""
import os, sys, json
import numpy as np, pandas as pd
from scipy import stats
HERE = os.path.dirname(os.path.abspath(__file__)); F1D = os.path.abspath(f"{HERE}/../fusion/results"); RR = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery"); B = 5000
T = pd.read_csv(f"{RR}/data/targets.csv")[["target_key", "family"]]


def intervals(v, seed=3):
    v = np.asarray(v, float); v = v[np.isfinite(v)]; n = len(v); m = float(v.mean()); se = float(v.std(ddof=1) / np.sqrt(n)); rng = np.random.default_rng(seed); bm = v[rng.integers(0, n, (B, n))].mean(1)
    pct = lambda a: [float(np.percentile(bm, 100 * a / 2)), float(np.percentile(bm, 100 * (1 - a / 2)))]; tq = lambda a: float(stats.t.ppf(1 - a / 2, n - 1)); adj = 0.05 / 3
    return dict(n=n, mean=m, p_t_two_sided=float(2 * stats.t.sf(abs(m / se), n - 1)) if se > 0 else None,
                pct95=pct(0.05), t95=[m - tq(0.05) * se, m + tq(0.05) * se], pct_adj=pct(adj), t_adj=[m - tq(adj) * se, m + tq(adj) * se])


def read(iv):
    gain = {k: bool(iv["mean"] >= 0.02 and iv[k][0] > 0) for k in ("pct95", "t95", "pct_adj", "t_adj")}
    ni = {"point>=-0.03(registered)": bool(iv["mean"] >= -0.03)} | {f"{k}_lower>{m}": bool(iv[k][0] > m) for k in ("pct95", "t95") for m in (-0.03, -0.05)}
    return gain, ni


def perm_diffs(df, arms, comps, tag):
    pl = df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index(); out = []
    for k, g in pl.groupby("k"):
        W = g.pivot(index="lab", columns="arm", values="spearman"); ok = W[list(comps) + list(arms)].dropna(); best = max(comps, key=lambda c: ok[c].mean())
        for a in arms: out.append(dict(study=tag, testbed="permeability(lab)", arm=a, k=int(k), best=best, **intervals((ok[a] - ok[best]).values)))
    return out


def fam_series(D, arm, k):
    d = D[(D.arm == arm) & (D.k == k)].groupby("target_key").auc.mean().reset_index().merge(T, on="target_key"); return d.groupby("family").auc.mean()


def bind_diffs(D, arms, comps, tag):
    out = []
    for k in (5, 10, 25):
        fs = {a: fam_series(D, a, k) for a in list(comps) + list(arms)}; fams = sorted(set.intersection(*[set(s.index) for s in fs.values()])); best = max(comps, key=lambda c: fs[c].loc[fams].mean())
        for a in arms: out.append(dict(study=tag, testbed="binding(family)", arm=a, k=k, best=best, **intervals((fs[a].loc[fams] - fs[best].loc[fams]).values)))
    return out


rows = []
f1 = pd.read_csv(f"{F1D}/perm_cells_nopt.csv"); rows += perm_diffs(f1, ["F1_5", "F2_5"], ["K", "A"], "T1")
rows += bind_diffs(pd.read_csv(f"{F1D}/bind_cells.csv"), ["F1_PB_5", "F2_PB_5", "F1_PT_5", "F2_PT_5"], ["NN"], "T1")
rows += perm_diffs(pd.read_csv(f"{HERE}/results/perm_b_cells.csv"), ["F1b_5", "F2b_5"], ["PTk", "PT", "A"], "T1b")
rows += bind_diffs(pd.read_csv(f"{HERE}/results/bind_b_cells.csv"), ["F1b_PT_5", "F2b_PT_5"], ["NN", "PT+k", "PT"], "T1b")
for r in rows: r["gain"], r["noninferior"] = read(r)
json.dump(rows, open(f"{HERE}/results/reeval_intervals.json", "w"), indent=1)
f = lambda x: "[%.3f,%.3f]" % tuple(x)
print("%-4s %-18s %-9s %2s %-5s %6s %5s | pct95 %-17s t95 %-17s | pctAdj %-17s tAdj %-17s | gain(p95,t95,pA,tA)" % ("stud", "testbed", "arm", "k", "best", "mean", "p_t", "", "", "", ""))
for r in rows:
    g = r["gain"]; print("%-4s %-18s %-9s %2d %-5s %+.3f %.3f | %-23s %-23s | %-23s %-23s | %s" % (r["study"], r["testbed"], r["arm"], r["k"], r["best"], r["mean"], r["p_t_two_sided"], f(r["pct95"]), f(r["t95"]), f(r["pct_adj"]), f(r["t_adj"]), "".join("Y" if g[k] else "n" for k in ("pct95", "t95", "pct_adj", "t_adj"))))
print()
for (study, tb, arm), grp in pd.DataFrame(rows).groupby(["study", "testbed", "arm"], sort=False):
    ks = sorted(grp.k); g = {k: grp[grp.k == k].iloc[0] for k in ks}
    b = {t: any(g[k]["gain"][t] for k in ks) for t in ("pct95", "t95", "pct_adj", "t_adj")}; ni = {m: all(g[k]["noninferior"][m] for k in ks) for m in g[ks[0]]["noninferior"]}
    print(study, tb, arm, "| (b) any k:", b, "| (a) all k:", ni)
