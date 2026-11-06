"""Summaries for testbed 1 (PREREG sec. 3, 5). usage: python3 summarize_perm.py shuffle|real"""
import sys, os, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); B = 2000
def boot_mean_median(v, seed=3):
    v = np.asarray(v, float); v = v[np.isfinite(v)]; rng = np.random.default_rng(seed); idx = rng.integers(0, len(v), (B, len(v)))
    return dict(mean=float(v.mean()), mean_ci=[float(np.percentile(v[idx].mean(1), 2.5)), float(np.percentile(v[idx].mean(1), 97.5))],
                median=float(np.median(v)), median_ci=[float(np.percentile(np.median(v[idx], 1), 2.5)), float(np.percentile(np.median(v[idx], 1), 97.5))], n_labs=int(len(v)))
def per_lab(df):
    return df.groupby(["shuffle", "k", "lab", "arm"]).spearman.mean().reset_index() if "shuffle" in df else df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index()
def real():
    fn = f"{HERE}/results/perm_cells.csv"; full = os.path.exists(fn)
    df = pd.read_csv(fn if full else f"{HERE}/results/perm_cells_nopt.csv"); pl = df.groupby(["k", "lab", "arm"]).spearman.mean().reset_index(); piv = {k: g.pivot(index="lab", columns="arm", values="spearman") for k, g in pl.groupby("k")}
    out = dict(source=os.path.basename(fn if full else "perm_cells_nopt.csv"), baselines_included=full); rule_a = {}; rule_b = {}
    for k, W in piv.items():
        res = dict(n_labs=int(W["K"].notna().sum())); ok = W[["K", "A", "F1_5", "F2_5"]].dropna()
        for arm in [c for c in W.columns if not c.startswith("W_")]:
            res[arm] = boot_mean_median(W[arm].values)
        best = "K" if ok.K.mean() >= ok.A.mean() else "A"; res["best_component_on_eval"] = best
        for f in ("F1_5", "F2_5"):
            diff = (ok[f] - ok[best]).values; b = boot_mean_median(diff); res[f"{f}_minus_best"] = b
            for comp in ("K", "A"): res[f"{f}_minus_{comp}"] = boot_mean_median((ok[f] - ok[comp]).values)
            rule_b.setdefault(f, {})[k] = bool(b["mean"] >= 0.02 and b["mean_ci"][0] > 0); rule_a.setdefault(f, {})[k] = bool(b["mean"] >= -0.03)
        res["n0_grid_mean"] = {c: float(W[c].mean()) for c in W.columns if c.startswith(("F1_", "F2_")) and not c.endswith("_sib")}; res["w_curve_mean(F1 form)"] = {c: float(W[c].mean()) for c in W.columns if c.startswith("W_")}
        res["sibling_inclusive"] = {c: float(W[c].mean()) for c in ("K_sib", "A_sib", "F1_5_sib", "F2_5_sib") if c in W}
        for c in ("RF_rev", "PT", "PTk"):
            if c in W: res[c + "_minus_best_fusion"] = None
        out[f"k{k}"] = res
    out["criteria"] = {f: dict(a_noninferior_all_k=all(rule_a[f].values()), b_complementary_some_k=any(rule_b[f].values()), per_k_b=rule_b[f], per_k_a=rule_a[f]) for f in rule_a}
    json.dump(out, open(f"{HERE}/results/perm_summary.json", "w"), indent=1)
    for k in sorted(piv):
        r = out[f"k{k}"]; print(f"\nk={k} labs={r['n_labs']} best component on eval = {r['best_component_on_eval']}")
        for a in ("K", "A", "F1_5", "F2_5") + tuple(c for c in ("RF_rev", "PT", "PTk") if c in r):
            x = r[a]; print("  %-7s mean %.3f [%.3f,%.3f]  median %.3f [%.3f,%.3f]" % (a, x["mean"], *x["mean_ci"], x["median"], *x["median_ci"]))
        for f in ("F1_5", "F2_5"):
            x = r[f + "_minus_best"]; print("  %s - best(%s): %+.3f [%.3f,%.3f]  | vs K %+.3f  vs A %+.3f" % (f, r["best_component_on_eval"], x["mean"], *x["mean_ci"], r[f + "_minus_K"]["mean"], r[f + "_minus_A"]["mean"]))
        print("  n0 grid (mean Spearman):", {c: round(v, 3) for c, v in r["n0_grid_mean"].items()}); print("  w-curve (F1 form, w=prior weight):", {c[2:]: round(v, 3) for c, v in r["w_curve_mean(F1 form)"].items()}); print("  sibling-inclusive:", {c: round(v, 3) for c, v in r["sibling_inclusive"].items()})
    print("\nCRITERIA:", json.dumps(out["criteria"]))


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "real": real()
    if mode == "shuffle":
        df = pd.read_csv(f"{HERE}/results/perm_shuffle_cells.csv"); pl = per_lab(df).groupby(["k", "lab", "arm"]).spearman.mean().reset_index(); out = {}
        for k in sorted(pl.k.unique()):
            for arm in ("K", "A", "F1_5", "F2_5", "K_sib", "A_sib", "F1_5_sib", "F2_5_sib"):
                v = pl[(pl.k == k) & (pl.arm == arm)].spearman.values; out[f"k{k}_{arm}"] = boot_mean_median(v)
        pass_ = {a: all(abs(out[f"k{k}_{a}"]["mean"]) <= 0.03 and out[f"k{k}_{a}"]["mean_ci"][0] <= 0 <= out[f"k{k}_{a}"]["mean_ci"][1] for k in sorted(pl.k.unique())) for a in ("K", "A", "F1_5", "F2_5")}
        out["PASS_per_arm(|mean|<=0.03 and CI contains 0 at every k)"] = pass_; json.dump(out, open(f"{HERE}/results/perm_shuffle_summary.json", "w"), indent=1)
        for k in sorted(pl.k.unique()): print("k", k, {a: (round(out[f"k{k}_{a}"]["mean"], 3), [round(x, 3) for x in out[f"k{k}_{a}"]["mean_ci"]], out[f"k{k}_{a}"]["n_labs"]) for a in ("K", "A", "F1_5", "F2_5")})
        print("PASS:", pass_)
