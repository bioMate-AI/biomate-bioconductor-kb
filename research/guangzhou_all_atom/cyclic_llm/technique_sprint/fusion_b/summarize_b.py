"""T1b summaries (PREREG sec. 3-5). usage: python3 summarize_b.py perm|perm_shuffle|bind|bind_shuffle"""
import sys, os, json, glob
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); RR = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery"); sys.path.insert(0, RR)
B = 5000; ALPHA_ADJ = 0.05 / 3


def boot_ci(v, seed=3):
    v = np.asarray(v, float); v = v[np.isfinite(v)]; rng = np.random.default_rng(seed); idx = rng.integers(0, len(v), (B, len(v))); m = v[idx].mean(1)
    q = lambda p: float(np.percentile(m, 100 * p))
    return dict(mean=float(v.mean()), ci95=[q(0.025), q(0.975)], ci_adj=[q(ALPHA_ADJ / 2), q(1 - ALPHA_ADJ / 2)], n_clusters=int(len(v)))


def decide(diffs_by_k, comp_by_k, cluster):
    out = {}; a_ok = all(v["mean"] >= -0.03 for v in diffs_by_k.values()); b_ok = any(v["mean"] >= 0.02 and v["ci_adj"][0] > 0 for v in diffs_by_k.values()); nominal = any(v["mean"] >= 0.02 and v["ci95"][0] > 0 for v in diffs_by_k.values())
    ni = all(v["ci95"][0] > -0.05 for v in diffs_by_k.values())
    return dict(cluster=cluster, a_point_noninferior_all_k=a_ok, b_adjusted_supported=b_ok, b_nominal_only=(nominal and not b_ok), formal_NI_lower_gt_minus0p05_all_k=ni,
                outcome=("SUPPORTED" if a_ok and b_ok else "PARTIAL" if a_ok else "FAILED" if not a_ok else "NULL") if True else None) | dict(outcome2=("NULL" if (a_ok and not b_ok) else None))


def perm():
    df = pd.read_csv(f"{HERE}/results/perm_b_cells.csv"); pl = df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index(); out = dict(cluster="lab"); dec = {}; ref = {}
    for k, g in pl.groupby("k"):
        W = g.pivot(index="lab", columns="arm", values="spearman"); cols = ["PT", "A", "PTk"] + [c for c in W.columns if c.startswith(("F1b", "F2b"))]; ok = W[cols].dropna(); res = dict(n_labs=len(ok))
        res["means"] = {c: round(float(ok[c].mean()), 4) for c in cols}; best = max(["PTk", "PT", "A"], key=lambda c: ok[c].mean()); res["best_comparator_on_eval"] = best
        for f in ("F2b_5", "F1b_5", "F2b_10", "F1b_10"):
            res[f"{f}_minus_best"] = boot_ci((ok[f] - ok[best]).values)
            for c in ("PTk", "PT", "A"): res[f"{f}_minus_{c}"] = boot_ci((ok[f] - ok[c]).values)
        for c in ("PT", "A", "PTk", "F2b_5", "F1b_5"): res[c] = boot_ci(ok[c].values)
        res["per_lab_F2b_5_minus_best"] = {l: round(float(x), 3) for l, x in (ok["F2b_5"] - ok[best]).items()}; out[f"k{k}"] = res
    for f in ("F2b_5", "F1b_5"):
        d = {k: out[f"k{k}"][f"{f}_minus_best"] for k in (5, 10, 25) if f"k{k}" in out}; a_ok = all(v["mean"] >= -0.03 for v in d.values()); b_ok = any(v["mean"] >= 0.02 and v["ci_adj"][0] > 0 for v in d.values())
        nom = any(v["mean"] >= 0.02 and v["ci95"][0] > 0 for v in d.values()); ni = all(v["ci95"][0] > -0.05 for v in d.values())
        dec[f] = dict(cluster="lab", a_point_noninferior_all_k=bool(a_ok), b_supported_bonferroni_adjusted=bool(b_ok), b_nominal_only_unadjusted=bool(nom and not b_ok), formal_NI_95lower_gt_minus0p05_all_k=bool(ni), outcome=("SUPPORTED" if a_ok and b_ok else ("NULL" if a_ok else "FAILED")))
    out["decision"] = dec; json.dump(out, open(f"{HERE}/results/perm_b_summary.json", "w"), indent=1)
    for k in (5, 10, 25):
        r = out[f"k{k}"]; print(f"\nk={k} labs={r['n_labs']} best comparator on eval: {r['best_comparator_on_eval']}  means {r['means']}")
        for f in ("F2b_5", "F1b_5", "F2b_10"):
            x = r[f + "_minus_best"]; print("  %-6s - best: %+.3f  95%% [%.3f,%.3f]  adj98.3%% [%.3f,%.3f]  | vs PTk %+.3f  vs PT %+.3f  vs A %+.3f" % (f, x["mean"], *x["ci95"], *x["ci_adj"], r[f + "_minus_PTk"]["mean"], r[f + "_minus_PT"]["mean"], r[f + "_minus_A"]["mean"]))
    print("\nDECISION", json.dumps(dec))


def perm_shuffle():
    df = pd.read_csv(f"{HERE}/results/perm_b_shuffle_cells.csv"); pl = df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index(); out = {}; ok_all = {}
    for arm in ("PT", "A", "PTk", "F1b_5", "F2b_5"):
        okk = True
        for k in (5, 10, 25):
            v = pl[(pl.k == k) & (pl.arm == arm)].spearman.values; c = boot_ci(v); out[f"k{k}_{arm}"] = c; okk &= (abs(c["mean"]) <= 0.03 and c["ci95"][0] <= 0 <= c["ci95"][1])
        ok_all[arm] = bool(okk)
    out["PASS_per_arm"] = ok_all; json.dump(out, open(f"{HERE}/results/perm_b_shuffle_summary.json", "w"), indent=1)
    for k in (5, 10, 25): print("k", k, {a: (round(out[f"k{k}_{a}"]["mean"], 3), [round(x, 3) for x in out[f"k{k}_{a}"]["ci95"]]) for a in ("PT", "A", "PTk", "F1b_5", "F2b_5")})
    print("PASS", ok_all)


def fam_means(D, T, arm, k, metric):
    d = D[(D.arm == arm) & (D.k == k)].groupby("target_key")[metric].mean().reset_index().merge(T[["target_key", "family"]], on="target_key"); d = d[d[metric].notna()]
    return d.groupby("family")[metric].mean()


def fdiff(a, b, seed=11):
    fams = sorted(set(a.index) & set(b.index)); v = a.loc[fams].values - b.loc[fams].values; return boot_ci(v, seed)


def bind():
    import harness as H
    D = pd.read_csv(f"{HERE}/results/bind_b_cells.csv"); BL = pd.read_csv(f"{RR}/results/h4b_per_target.csv"); T = pd.read_csv(f"{RR}/data/targets.csv"); G = json.load(open(f"{RR}/results/validity_gate_h4b.json")); out = dict(cluster="family")
    par = {}
    for arm in ("R", "NN", "FP-k", "PT", "PT+k"):
        m = D[D.arm == arm].merge(BL[BL.arm == arm], on=["target_key", "k", "seed"], suffixes=("", "_b")); par[arm] = dict(n_cells=int(len(m)), max_abs_auc_diff=float((m.auc - m.auc_b).abs().max()), max_abs_ef5_diff=float((m.ef5 - m.ef5_b).abs().max()))
    out["parity_vs_frozen"] = par; print("PARITY", par)
    dec = {}
    for k in (5, 10, 25):
        fm = {a: fam_means(D, T, a, k, "auc") for a in D.arm.unique() if a not in ("PB",) or True}; ck = {c: x["point"] for c, x in G[str(k)]["primary"].items()}; res = dict(controls_auc_point=ck)
        base = ["R", "NN", "FP-k", "PT", "PT+k"]; strongest = max(base, key=lambda a: fm[a].mean()); best = max(["PT+k", "PT", "NN"], key=lambda a: fm[a].mean()); res["strongest_frozen"] = strongest; res["best_comparator"] = best
        res["arms"] = {}
        for a in ["NN", "PT", "PT+k", "FP-k"] + [x for x in fm if x.startswith(("F1b", "F2b"))]:
            r = dict(auc=boot_ci(fm[a].values), vs_best=fdiff(fm[a], fm[best]), vs_NN=fdiff(fm[a], fm["NN"]), vs_PTk=fdiff(fm[a], fm["PT+k"]), vs_strongest=fdiff(fm[a], fm[strongest]), exceeds_max_gate_control_lo=bool(boot_ci(fm[a].values)["ci95"][0] > max(ck.values())))
            if a.startswith(("F1b", "F2b")): r["gain_vs_PT_k0"] = fdiff(fm[a], fam_means(D, T, "PT", 0, "auc"))
            for st in ("auc_near", "auc_far"):
                fs = {x: fam_means(D, T, x, k, st) for x in (a, best, "NN", "PT", "PT+k") if x in fm}; r[st] = dict(mean=float(fs[a].mean()), vs_best=fdiff(fs[a], fs[best]), n_families=int(len(fs[a])))
            res["arms"][a] = r
        out[f"k{k}"] = res
    for f in ("F2b_PT_5", "F1b_PT_5"):
        d = {k: out[f"k{k}"]["arms"][f]["vs_best"] for k in (5, 10, 25)}; a_ok = all(v["mean"] >= -0.03 for v in d.values()); b_ok = any(v["mean"] >= 0.02 and v["ci_adj"][0] > 0 for v in d.values())
        ca = all(out[f"k{k}"]["arms"][f]["vs_strongest"]["ci95"][0] > 0 and out[f"k{k}"]["arms"][f]["gain_vs_PT_k0"]["ci95"][0] > 0 for k in (5, 10, 25) if d[k]["mean"] >= 0.02)
        dec[f] = dict(cluster="family", a_point_noninferior_all_k=bool(a_ok), b_supported_bonferroni_adjusted=bool(b_ok), b_nominal_only_unadjusted=bool(any(v["mean"] >= 0.02 and v["ci95"][0] > 0 for v in d.values()) and not b_ok), formal_NI_95lower_gt_minus0p05_all_k=bool(all(v["ci95"][0] > -0.05 for v in d.values())),
                      outcome=("SUPPORTED(control-adjusted rule still required; gate INVALID)" if a_ok and b_ok else ("NULL" if a_ok else "FAILED")))
    out["decision"] = dec; json.dump(out, open(f"{HERE}/results/bind_b_summary.json", "w"), indent=1)
    for k in (5, 10, 25):
        r = out[f"k{k}"]; print(f"\nk={k} best comparator {r['best_comparator']} strongest frozen {r['strongest_frozen']} controls {r['controls_auc_point']}")
        for a in ("NN", "PT", "PT+k", "F1b_PT_5", "F2b_PT_5", "F2b_PT_10", "F2b_PB_5"):
            x = r["arms"][a]; print("  %-9s AUC %.3f  vs best %+.3f 95%%[%.3f,%.3f] adj[%.3f,%.3f] | near %.3f (vs best %+.3f [%.3f,%.3f]) far %.3f (vs best %+.3f [%.3f,%.3f])" % (a, x["auc"]["mean"], x["vs_best"]["mean"], *x["vs_best"]["ci95"], *x["vs_best"]["ci_adj"], x["auc_near"]["mean"], x["auc_near"]["vs_best"]["mean"], *x["auc_near"]["vs_best"]["ci95"], x["auc_far"]["mean"], x["auc_far"]["vs_best"]["mean"], *x["auc_far"]["vs_best"]["ci95"]))
    print("\nDECISION", json.dumps(dec))


def bind_shuffle():
    T = pd.read_csv(f"{RR}/data/targets.csv"); fs = sorted(glob.glob(f"{HERE}/results/bind_b_shuffle_*_cells.csv")); D = pd.concat([pd.read_csv(f) for f in fs]); out = {}; ok = {}
    for arm in ("R", "NN", "PT", "PT+k", "F1b_PT_5", "F2b_PT_5"):
        okk = True
        for k in (5, 10, 25):
            v = np.mean([fam_means(D[D.shuffle == s], T, arm, k, "auc").mean() for s in D.shuffle.unique()]); vals = pd.concat([fam_means(D[D.shuffle == s], T, arm, k, "auc") for s in D.shuffle.unique()]).groupby(level=0).mean().values
            c = boot_ci(vals); out[f"k{k}_{arm}"] = c; okk &= (abs(c["mean"] - 0.5) <= 0.03 and c["ci95"][0] <= 0.5 <= c["ci95"][1])
        ok[arm] = bool(okk)
    out["PASS_per_arm"] = ok; out["n_shuffles"] = len(fs); json.dump(out, open(f"{HERE}/results/bind_b_shuffle_summary.json", "w"), indent=1)
    for k in (5, 10, 25): print("k", k, {a: (round(out[f"k{k}_{a}"]["mean"], 3), [round(x, 3) for x in out[f"k{k}_{a}"]["ci95"]]) for a in ok})
    print("PASS", ok, "shuffles", len(fs))


if __name__ == "__main__": {"perm": perm, "perm_shuffle": perm_shuffle, "bind": bind, "bind_shuffle": bind_shuffle}[sys.argv[1]]()
