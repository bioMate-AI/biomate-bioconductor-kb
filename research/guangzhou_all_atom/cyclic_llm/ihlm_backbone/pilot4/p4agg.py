"""Pilot 4 aggregation. usage: python3 p4agg.py dev RESDIR   -> frozen_config.json + dev_summary.json (A1)
                                 python3 p4agg.py test RESDIR  -> gate, learning curves, repeated splits, secondary arms, controls (reads eval_dev + eval_test)"""
import os, sys, json, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4common as P
KS3 = (3, 5, 10); B = 2000
NNQ = ("nn_q1", "nn_q3", "nn_q6"); D = [f"d_q{q}_l{l}" for q in (1, 3, 6) for l in (0.3, 1.0, 3.0)]
G = [f"g_a{a}_q{q}_l{l}" for a in (10, 100, 1000) for q in (1, 3, 6) for l in (0.3, 1.0, 3.0)]; F0 = ("f0_1000", "f0_3000"); F1 = ("f1_1000", "f1_3000")


def famtab(df, col):
    """family-equal table: index method, columns (k) -> mean over families of (mean over targets of (mean over seeds))."""
    t = df.groupby(["method", "k", "family", "target"])[col].mean().groupby(["method", "k", "family"]).mean()
    return t                                                                  # Series indexed (method,k,family)


def fam_mean(t, method, k): return t.loc[(method, k)].mean()


def per_family(t, method, k): return t.loc[(method, k)]


def choose(t, names, ks=KS3):
    sc = {n: np.mean([fam_mean(t, n, k) for k in ks]) for n in names if (n, ks[0]) in t.index.droplevel(2)}
    return max(sc, key=sc.get), sc


def boot_ci(d, level=97.5, rng=None):
    rng = rng or np.random.default_rng(0); d = np.asarray(d, float); n = len(d); bs = np.array([d[rng.integers(0, n, n)].mean() for _ in range(B)])
    return float(np.percentile(bs, 100 - level)), float(np.percentile(bs, level))


def dev(res):
    df = pd.read_csv(f"{res}/eval_dev.csv.gz"); t = famtab(df, "sp"); th = famtab(df, "sp_h")
    nn, snn = choose(t, NNQ); d, sd_ = choose(t, D); g, sg = choose(t, G); f, sf = choose(t, F0)
    cfg = dict(nn=nn, nn_q=int(nn[-1]), d=[int(d.split("_")[1][1:]), float(d.split("_l")[1])], d_name=d, g_name=g, g=[int(g.split("_")[1][1:]), int(g.split("_")[2][1:]), float(g.split("_l")[1])], f_name=f, f_ck=int(f.split("_")[1]),
               f1_name="f1_" + f.split("_")[1], ridge_alpha=int(g.split("_")[1][1:]))
    base = [nn, "gp", "rf", d, "prior_hgb"]; cand = [f, g]; out = dict(config=cfg, n_dev_families=int(df.family.nunique()), n_dev_targets=int(df.target.nunique()), mde={}, dev_means={})
    for k in KS3:
        bb = max(base, key=lambda m: fam_mean(th, m, k)); out["dev_means"][k] = {m: dict(overall=float(fam_mean(t, m, k)), hard=float(fam_mean(th, m, k))) for m in base + cand + ["prior_h0", "prior_h1"] if (m, k) in t.index.droplevel(2)}
        for c in cand:
            diff = (per_family(th, c, k) - per_family(th, bb, k)).dropna(); sdv = float(diff.std(ddof=1)); n_test = 21
            out["mde"][f"{c}|k{k}"] = dict(best_dev_baseline=bb, mean_diff_dev=float(diff.mean()), sd_between_family=sdv, n_dev_families=int(len(diff)), MDE80=float(3.08 * sdv / np.sqrt(n_test)))
    json.dump(cfg, open(f"{res}/frozen_config.json", "w"), indent=1); json.dump(out, open(f"{res}/dev_summary.json", "w"), indent=1, default=float)
    print(json.dumps(cfg)); print("dev choice scores: nn", {k: round(v, 3) for k, v in snn.items()}); print("d top3", sorted(sd_.items(), key=lambda x: -x[1])[:3]); print("g top3", sorted(sg.items(), key=lambda x: -x[1])[:3]); print("f", sf)
    for k in KS3:
        for c in cand: m = out["mde"][f"{c}|k{k}"]; print(k, c, "vs", m["best_dev_baseline"], "dev diff", round(m["mean_diff_dev"], 3), "SDfam", round(m["sd_between_family"], 3), "MDE80(test, 21 fam)", round(m["MDE80"], 3))


def test(res):
    cfg = json.load(open(f"{res}/frozen_config.json")); dv = pd.read_csv(f"{res}/eval_dev.csv.gz"); ts = pd.read_csv(f"{res}/eval_test.csv.gz")
    allm = pd.concat([dv, ts]); ts_t = famtab(ts, "sp"); ts_h = famtab(ts, "sp_h"); ts_n = famtab(ts, "ndcg"); ts_r = famtab(ts, "rec")
    base = [cfg["nn"], "gp", "rf", cfg["d_name"], "prior_hgb"]; cand = [cfg["f_name"], cfg["g_name"]]; mde = json.load(open(f"{res}/dev_summary.json"))["mde"]
    rng = np.random.default_rng(1); out = dict(gate={}, n_test_families=int(ts.family.nunique()), n_test_targets=int(ts.target.nunique()))
    for c in cand:
        passk = []
        for k in KS3:
            bt = max(base, key=lambda m: fam_mean(ts_h, m, k)); bdv = mde[f"{c}|k{k}"]["best_dev_baseline"]
            diff = (per_family(ts_h, c, k) - per_family(ts_h, bt, k)).dropna(); lo, hi = boot_ci(diff.values, rng=rng)
            diff_dv = (per_family(ts_h, c, k) - per_family(ts_h, bdv, k)).dropna(); lo2, hi2 = boot_ci(diff_dv.values, rng=rng)
            do = (per_family(ts_t, c, k) - per_family(ts_t, bt, k)).dropna(); lo3, hi3 = boot_ci(do.values, rng=rng)
            ok = bool(diff.mean() >= 0.03 and lo > 0); passk.append(ok)
            out["gate"][f"{c}|k{k}"] = dict(best_test_baseline=bt, diff_hard=float(diff.mean()), ci97_5=[lo, hi], n_fam=int(len(diff)), pass_k=ok, MDE80=mde[f"{c}|k{k}"]["MDE80"],
                                            sens_devbaseline=dict(base=bdv, diff=float(diff_dv.mean()), ci=[lo2, hi2]), overall=dict(diff=float(do.mean()), ci=[lo3, hi3]))
        mdes = [mde[f"{c}|k{k}"]["MDE80"] for k in KS3]; wide = sum(m > 0.05 for m in mdes) >= 2
        out["gate"][c] = dict(passes=int(sum(passk)), verdict="PASS" if sum(passk) >= 2 else ("NOT DETECTED / UNDERPOWERED" if wide else "FAIL"), MDEs=mdes)
    # learning curves (all methods of interest), family-equal means with family bootstrap CIs
    lc = {}; names = base + cand + ["prior_h0", "prior_h1", "dh0", "dh1", cfg["f1_name"], f"g_a{cfg['ridge_alpha']}_q1_l1.0"] + [m for m in ts.method.unique() if m.startswith("prior_ridge")]
    for m in dict.fromkeys(names):
        lc[m] = {}
        for k in (0, 1, 3, 5, 10, 25):
            if (m, k) not in ts_t.index.droplevel(2): continue
            a = ts_t.loc[(m, k)].dropna(); h = ts_h.loc[(m, k)].dropna() if (m, k) in ts_h.index.droplevel(2) else pd.Series(dtype=float)
            lc[m][k] = dict(overall=[float(a.mean())] + list(boot_ci(a.values, 95, rng)), hard=([float(h.mean())] + list(boot_ci(h.values, 95, rng))) if len(h) else None,
                            ndcg=float(ts_n.loc[(m, k)].mean()), recall=float(ts_r.loc[(m, k)].mean()))
    out["learning_curves"] = lc
    # target-weighted sensitivity
    tw = {}
    for k in KS3:
        for m in base + cand: sub = ts[(ts.method == m) & (ts.k == k)]; tw[f"{m}|k{k}"] = float(sub.groupby("target").sp_h.mean().mean())
    out["target_weighted_hard"] = tw
    # secondary: censor-aware
    sec = {}
    for a, b, nm in (("prior_h1", "prior_h0", "prior h1-h0"), ("dh1", "dh0", "correction dh1-dh0"), (cfg["f1_name"], cfg["f_name"], "meta f1-f0")):
        for k in (0, 3, 5, 10, 25):
            if (a, k) not in ts_t.index.droplevel(2) or (b, k) not in ts_t.index.droplevel(2): continue
            d_all = (per_family(ts_t, a, k) - per_family(ts_t, b, k)).dropna(); lo, hi = boot_ci(d_all.values, 95, rng); r = dict(overall=[float(d_all.mean()), lo, hi])
            if k >= 3: d_h = (per_family(ts_h, a, k) - per_family(ts_h, b, k)).dropna(); lo, hi = boot_ci(d_h.values, 95, rng); r["hard"] = [float(d_h.mean()), lo, hi]
            sec[f"{nm}|k{k}"] = r
    out["secondary_censor"] = sec
    # repeated random family splits over all 47 eligible families
    fams = sorted(allm.family.unique()); tt = famtab(allm, "sp"); thh = famtab(allm, "sp_h"); res_rs = {c: {k: [] for k in KS3} for c in ("f", "g")}; passes = {c: 0 for c in ("f", "g")}
    rr = np.random.default_rng(7)
    for _ in range(50):
        perm = rr.permutation(fams); dev_f, test_f = perm[:len(fams) // 2], perm[len(fams) // 2:]
        def fm(tab, m, k, fs): s = tab.loc[(m, k)]; return s[s.index.isin(fs)].mean()
        nnc = max(NNQ, key=lambda m: np.mean([fm(tt, m, k, dev_f) for k in KS3])); dc = max(D, key=lambda m: np.mean([fm(tt, m, k, dev_f) for k in KS3]))
        gc = max(G, key=lambda m: np.mean([fm(tt, m, k, dev_f) for k in KS3])); fc = max(F0, key=lambda m: np.mean([fm(tt, m, k, dev_f) for k in KS3]))
        for cn, c in (("f", fc), ("g", gc)):
            oks = 0
            for k in KS3:
                bb = max([nnc, "gp", "rf", dc, "prior_hgb"], key=lambda m: fm(thh, m, k, test_f)); df_ = fm(thh, c, k, test_f) - fm(thh, bb, k, test_f); res_rs[cn][k].append(float(df_)); oks += df_ >= 0.03
            passes[cn] += int(oks >= 2)
    out["repeated_splits"] = {c: dict(frac_pass=passes[c] / 50, median_diff={k: float(np.median(v)) for k, v in res_rs[c].items()}, q10_q90={k: [float(np.percentile(v, 10)), float(np.percentile(v, 90))] for k, v in res_rs[c].items()}) for c in res_rs}
    # iterative variant
    if os.path.exists(f"{res}/al_test.csv.gz"):
        al = pd.read_csv(f"{res}/al_test.csv.gz"); y = al.groupby(["method", "family", "target"])["yield"].mean().groupby(["method", "family"]).mean(); rnd = y.loc["random"]; alo = {}
        for m in ("random", "nn", "gp_ucb", "d", "f", "g"):
            d_ = (y.loc[m] - rnd).dropna(); alo[m] = dict(yield_mean=float(y.loc[m].mean()), minus_random=[float(d_.mean())] + list(boot_ci(d_.values, 95, rng)) if m != "random" else None)
        out["iterative"] = alo
    # controls
    if os.path.exists(f"{res}/controls_test.csv.gz"):
        cd = pd.read_csv(f"{res}/controls_test.csv.gz"); cc = {}
        for ctl, g in cd.groupby("control"):
            tab = g.groupby(["method", "k", "family", "target"]).sp.mean().groupby(["method", "k", "family"]).mean()
            for m in g.method.unique():
                for k in sorted(g.k.unique()):
                    v = tab.loc[(m, k)].dropna(); cc[f"{ctl}|{m}|k{k}"] = dict(mean=float(v.mean()), ci95=boot_ci(v.values, 95, rng))
        out["controls"] = cc
        pl = {m: cc.get(f"planted|{m}|k10", {}).get("mean") for m in (cfg["nn"], "gp", "prior_hgb")}; out["control_C1_planted_pass"] = bool(pl[cfg["nn"]] >= 0.4 and pl["gp"] >= 0.4 and pl["prior_hgb"] <= 0.15); out["control_C1_values"] = pl
        sh = [(key, v) for key, v in cc.items() if key.startswith("shuffled|")]; out["control_C2_shuffled_pass"] = bool(all(v["ci95"][0] <= 0 <= v["ci95"][1] and abs(v["mean"]) <= 0.05 for _, v in sh)); out["control_C2_fail_cells"] = [key for key, v in sh if not (v["ci95"][0] <= 0 <= v["ci95"][1] and abs(v["mean"]) <= 0.05)]
    if os.path.exists(f"{res}/c4_leak.json"): out["C4_L1"] = json.load(open(f"{res}/c4_leak.json"))
    if os.path.exists(f"{res}/s3_diag.csv.gz"):
        s3 = pd.read_csv(f"{res}/s3_diag.csv.gz"); out["S3"] = {p: dict(mean_auroc_family_equal=float(g.groupby("family").auroc.mean().mean()), ci95=boot_ci(g.groupby("family").auroc.mean().values, 95, rng), n_fam=int(g.family.nunique())) for p, g in s3.groupby("prior")}
    json.dump(out, open(f"{res}/test_summary.json", "w"), indent=1, default=float)
    for c in cand:
        print(c, out["gate"][c]); 
        for k in KS3: g = out["gate"][f"{c}|k{k}"]; print("  k", k, "vs", g["best_test_baseline"], "diff_hard", round(g["diff_hard"], 3), [round(x, 3) for x in g["ci97_5"]], "MDE80", round(g["MDE80"], 3), "pass", g["pass_k"])
    print("repeated splits", out["repeated_splits"])


if __name__ == "__main__":
    {"dev": dev, "test": test}[sys.argv[1]](sys.argv[2] if len(sys.argv) > 2 else os.path.join(P.HERE, "results"))
