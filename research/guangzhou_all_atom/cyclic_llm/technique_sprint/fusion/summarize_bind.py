"""Summaries for testbed 2 (PREREG sec. 4, 5 + A1). Parity check against the frozen baselines first."""
import sys, os, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); RR = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery"); sys.path.insert(0, RR)
import harness as H
D = pd.read_csv(f"{HERE}/results/bind_cells.csv"); BL = pd.read_csv(f"{RR}/results/h4b_per_target.csv"); T = pd.read_csv(f"{RR}/data/targets.csv"); tf = T[["target_key", "family"]]
G = json.load(open(f"{RR}/results/validity_gate_h4b.json"))
# parity: my NN and PT arms vs frozen baseline rows
par = {}
for arm in ("NN", "PT"):
    m = D[D.arm == arm].merge(BL[BL.arm == arm], on=["target_key", "k", "seed"], suffixes=("", "_b")); par[arm] = dict(n_cells=int(len(m)), max_abs_auc_diff=float((m.auc - m.auc_b).abs().max()), max_abs_ef5_diff=float((m.ef5 - m.ef5_b).abs().max()))
print("PARITY vs frozen baselines:", par)
def fam(df, arm, k, metric="auc"):
    d = df[(df.arm == arm) & (df.k == k)].groupby("target_key")[metric].mean().reset_index(); return H.family_means(d, tf, metric)
allarms = pd.concat([D[["target_key", "k", "seed", "arm", "auc", "ef5", "p10"]], BL[BL.arm.isin(["R", "FP-k", "PT+k"])][["target_key", "k", "seed", "arm", "auc", "ef5", "p10"]]])
out = dict(parity=par); B = 2000
for k in (5, 10, 25):
    ck = {c: x["point"] for c, x in G[str(k)]["primary"].items()}; ctrl_max = max(ck.values()); res = {}
    base_arms = ["NN", "FP-k", "PT", "PT+k", "R"]
    fm = {a: fam(allarms, a, k) for a in set(allarms[allarms.k == k].arm)}
    strongest = max(base_arms, key=lambda a: fm[a].mean()); res["strongest_baseline"] = dict(arm=strongest, auc=H.boot_mean(fm[strongest], B=B)); res["controls_auc_point"] = ck
    res["arms"] = {}
    for a in ("NN", "PT", "PB", "F1_PB_5", "F2_PB_5", "F1_PT_5", "F2_PT_5") + tuple(f"{f}_{p}_{n}" for f in ("F1", "F2") for p in ("PB", "PT") for n in (1, 2, 10, 25)):
        if a not in fm: continue
        r = dict(auc=H.boot_mean(fm[a], B=B), vs_NN=H.boot_diff(fm[a], fm["NN"], B=B), vs_strongest=H.boot_diff(fm[a], fm[strongest], B=B))
        prior0 = {"PB": "PB", "PT": "PT"}.get(a.split("_")[1] if a.startswith("F") else a)
        if prior0 and a not in ("PB", "PT"): r["gain_vs_own_k0"] = H.boot_diff(fm[a], fam(allarms, prior0, 0), B=B)
        r["exceeds_max_control_lo"] = bool(r["auc"]["lo"] > ctrl_max)
        for m in ("ef5", "p10"): r[m] = H.boot_mean(fam(allarms, a, k, m), B=B)
        res["arms"][a] = r
    out[str(k)] = res
for pn in ("PB", "PT"):
    out[f"k0_{pn}"] = H.boot_mean(fam(allarms, pn, 0), B=B)
json.dump(out, open(f"{HERE}/results/bind_summary.json", "w"), indent=1)
for k in (5, 10, 25):
    r = out[str(k)]; print("\nk", k, "strongest baseline:", r["strongest_baseline"]["arm"], round(r["strongest_baseline"]["auc"]["point"], 3), "| controls", {c[:2]: round(v, 3) for c, v in r["controls_auc_point"].items()})
    for a in ("NN", "PB", "PT", "F1_PB_5", "F2_PB_5", "F1_PT_5", "F2_PT_5"):
        x = r["arms"][a]; print("  %-9s AUC %.3f [%.3f,%.3f]  vs NN %+.3f [%.3f,%.3f]  vs strongest %+.3f [%.3f,%.3f]%s" % (a, x["auc"]["point"], x["auc"]["lo"], x["auc"]["hi"], x["vs_NN"]["point"], x["vs_NN"]["lo"], x["vs_NN"]["hi"], x["vs_strongest"]["point"], x["vs_strongest"]["lo"], x["vs_strongest"]["hi"], ("  gain vs k0 %+.3f [%.3f,%.3f]" % tuple(x["gain_vs_own_k0"][q] for q in ("point", "lo", "hi"))) if "gain_vs_own_k0" in x else ""))
print("k0 PB", {q: round(v, 3) for q, v in out["k0_PB"].items() if q != "n_families"}, "PT", {q: round(v, 3) for q, v in out["k0_PT"].items() if q != "n_families"})
