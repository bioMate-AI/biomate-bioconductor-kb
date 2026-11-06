"""Cluster-based power (PREREG A9). Unit = family. Reads stored scores/metrics only; writes results/power.json."""
import os, sys, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE)
import harness as H
T = pd.read_csv(f"{DATA}/targets.csv"); tf = T[["target_key", "family"]]; Z = 2.8   # (1.96 + 0.84)


def icc(pt):                                   # one-way ANOVA ICC(1) of per-target AUROC within families
    d = pt.merge(tf, on="target_key").dropna(subset=["auc"]); g = d.groupby("family").auc; n = len(d); kf = g.ngroups
    if kf < 2 or n <= kf: return float("nan"), float("nan")
    ni = g.size().values; n0 = (n - (ni ** 2).sum() / n) / (kf - 1); gm = d.auc.mean()
    msb = (ni * (g.mean().values - gm) ** 2).sum() / (kf - 1); msw = ((d.auc - d.family.map(g.mean())) ** 2).sum() / (n - kf)
    r = (msb - msw) / (msb + (n0 - 1) * msw); return float(r), float(d.groupby("family").size().mean())


def row(fam_diff, pt_for_icc=None):
    v = fam_diff.dropna().values; n = len(v); sd = float(v.std(ddof=1)) if n > 1 else float("nan"); mde = Z * sd / np.sqrt(n) if n > 1 else float("nan")
    r = dict(n_families=n, sd_family_diff=round(sd, 4), MDE_80pct=round(float(mde), 4), families_needed_for_0p05=int(np.ceil((Z * sd / 0.05) ** 2)) if n > 1 else None)
    if pt_for_icc is not None:
        rho, mbar = icc(pt_for_icc); r.update(ICC_target_within_family=round(rho, 3) if rho == rho else None, mean_targets_per_family=round(mbar, 2) if mbar == mbar else None)
        if rho == rho and mbar == mbar: r["design_effect"] = round(1 + (mbar - 1) * max(rho, 0), 3); r["effective_independent_targets"] = round(len(pt_for_icc) / (1 + (mbar - 1) * max(rho, 0)), 1)
    return r


out = {}
for which in ("I", "M2"):
    items, tfam = H.load(which); bl = pd.read_csv(f"{DATA}/baseline_scores_{which}.csv.gz"); arms_df = pd.read_csv(f"{DATA}/arm_scores_{which}_V2.csv.gz"); allsc = pd.concat([bl, arms_df])
    fms = {}; pts = {}
    for a, g in allsc.groupby("arm"):
        pt, _ = H.per_target(items, g[["target_key", "compound_id", "score"]]); pts[a] = pt; fms[a] = H.family_means(pt, tfam, "auc")
    strongest = max(bl.arm.unique(), key=lambda b: fms[b].mean()); out[which] = dict(strongest_baseline=strongest, contrasts={})
    for a in sorted(arms_df.arm.unique()):
        fams = sorted(set(fms[a].index) & set(fms[strongest].index)); out[which]["contrasts"][f"{a} - {strongest}"] = row(fms[a].loc[fams] - fms[strongest].loc[fams], pts[a])
pt = pd.read_csv(f"{RES}/h4b_per_target.csv"); out["H4b"] = {}
zs = pt[(pt.k == 0) & (pt.arm == "PT")].groupby("target_key").auc.mean().reset_index().merge(tf, on="target_key").groupby("family").auc.mean()
for k in (5, 10, 25):
    d = pt[pt.k == k].groupby(["arm", "target_key"]).auc.mean().reset_index(); fm = {a: g.merge(tf, on="target_key").groupby("family").auc.mean() for a, g in d.groupby("arm")}
    for a, b, lab in (("NN", "PT", "NN - PT(k=0)"), ("PT+k", "PT", "PT+k - PT(k=0)"), ("FP-k", "PT", "FP-k - PT(k=0)")):
        base = zs if lab.endswith("(k=0)") else fm[b]; fams = sorted(set(fm[a].index) & set(base.index)); out["H4b"][f"k={k}: {lab}"] = row(fm[a].loc[fams] - base.loc[fams], d[d.arm == a])
    fams = sorted(set(fm["NN"].index) & set(fm["FP-k"].index)); out["H4b"][f"k={k}: NN - FP-k"] = row(fm["NN"].loc[fams] - fm["FP-k"].loc[fams])
json.dump(out, open(f"{RES}/power.json", "w"), indent=1)
for w in ("I", "M2"):
    print("\n", w, "strongest baseline", out[w]["strongest_baseline"])
    for k, v in out[w]["contrasts"].items(): print(f"  {k:40s} n_fam={v['n_families']:2d} sd={v['sd_family_diff']:.3f} MDE80={v['MDE_80pct']:.3f} fam_needed(0.05)={v['families_needed_for_0p05']} ICC={v.get('ICC_target_within_family')} eff_targets={v.get('effective_independent_targets')}")
print("\n H4b")
for k, v in out["H4b"].items(): print(f"  {k:28s} n_fam={v['n_families']:2d} sd={v['sd_family_diff']:.3f} MDE80={v['MDE_80pct']:.3f} fam_needed(0.05)={v['families_needed_for_0p05']}")
