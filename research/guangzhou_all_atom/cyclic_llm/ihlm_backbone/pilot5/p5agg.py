"""Pilot 5 aggregation. usage: p5agg.py mde   (baseline-only pass A -> results/mde.json; run and COMMIT before pass B)
                                p5agg.py gate  (passes A+B -> results/gate_summary.json)"""
import os, sys, glob, json, itertools, numpy as np, pandas as pd
from scipy import stats
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C
B = 2000; KS3 = (3, 5, 10); BASE = ("prior", "nn", "gp", "d", "rf")


def load(pass_names):
    fs = [f for p in pass_names for f in sorted(glob.glob(f"{C.RES}/outer_{p}_r*_f*.csv.gz"))]
    df = pd.concat([pd.read_csv(f) for f in fs]); df["alias"] = df.alias.str.split(","); df = df.explode("alias"); return df


def rf_table():
    ev = pd.concat([pd.read_csv(f"{C.P4}/results/eval_dev.csv.gz"), pd.read_csv(f"{C.P4}/results/eval_test.csv.gz")]); r = ev[ev.method == "rf"].copy(); r["alias"] = "rf"; r["repeat"] = -1; return r


def fam_values(df, col):
    """per-family value = mean over repeats of (mean over targets of (mean over seeds)); index (alias, k, family)."""
    t = df.groupby(["alias", "k", "family", "repeat", "target"])[col].mean().groupby(["alias", "k", "family", "repeat"]).mean().groupby(["alias", "k", "family"]).mean(); return t


def boot(d, rng, lv=95):
    d = np.asarray(d, float); n = len(d); bs = np.array([d[rng.integers(0, n, n)].mean() for _ in range(B)]); return [float(np.percentile(bs, (100 - lv) / 2)), float(np.percentile(bs, 100 - (100 - lv) / 2))]


def tint(d, lv=0.95):
    """PRIMARY interval (amendment A2): cluster t over families, n-1 df. Returns [lo, hi]."""
    d = np.asarray(d, float); n = len(d); se = d.std(ddof=1) / np.sqrt(n); tc = stats.t.ppf(0.5 + lv / 2, n - 1); return [float(d.mean() - tc * se), float(d.mean() + tc * se)]


def mde():
    df = pd.concat([load(["A"]), rf_table()]); th = fam_values(df, "sp_h"); out = {}
    for k in KS3:
        means = {a: th.loc[(a, k)].mean() for a in BASE}; order = sorted(means, key=means.get, reverse=True); b1, b2 = order[0], order[1]
        d = (th.loc[(b1, k)] - th.loc[(b2, k)]).dropna(); sd = float(d.std(ddof=1)); nf = int(len(d))
        pair_sd = {f"{x}-{y}": float((th.loc[(x, k)] - th.loc[(y, k)]).dropna().std(ddof=1)) for x, y in itertools.combinations(BASE, 2)}
        tc = float(stats.t.ppf(0.975, nf - 1)); pw = {}
        for nm, sd_ in (("primary_best_minus_second", sd), ("conservative_max_pairwise", max(pair_sd.values())), ("median_pairwise", float(np.median(list(pair_sd.values()))))):
            se = sd_ / np.sqrt(nf); eff = max(0.03, tc * se)       # pass needs observed mean >= 0.03 AND cluster-t lower bound > 0 <=> mean >= max(0.03, tc*se)
            pw[nm] = dict(se=float(se), t_crit=tc, effective_margin=float(eff), eff_margin_over_MDE80=float(eff / (2.8 * se)),
                          P_pass_if_true_gain_0p03=float(1 - stats.norm.cdf((eff - 0.03) / se)), P_pass_if_true_gain_0p05=float(1 - stats.norm.cdf((eff - 0.05) / se)), true_gain_for_80pct_power=float(eff + 0.8416 * se))
        out[f"k{k}"] = dict(best=b1, second=b2, family_means={a: float(v) for a, v in means.items()}, sd_between_family_best_minus_second=sd, n_families=nf, MDE80=float(2.8 * sd / np.sqrt(nf)), pairwise_sd=pair_sd, power_of_registered_rule=pw)
    out["n_repeats_in_pass_A"] = int(df[df.repeat >= 0].repeat.nunique()); out["rule"] = "MDE80 = 2.8 * SD_between-family(best baseline - second-best baseline, hard Spearman) / sqrt(n_families); computed from pass A only, before any H5 score exists. Amendment A2 adds power_of_registered_rule: effective margin max(0.03, t_crit*SE) and P(pass) at true gains +0.03/+0.05 under normal approximation, SE from three baseline-only proxies (the registered best-minus-second SD is likely an UNDERESTIMATE of the candidate-vs-best SD because baselines are correlated; the conservative proxy uses the largest pairwise SD)"
    json.dump(out, open(f"{C.RES}/mde.json", "w"), indent=1); print(json.dumps({k: (v["best"], v["second"], round(v["MDE80"], 4)) for k, v in out.items() if k.startswith("k")}))


def gate():
    rng = np.random.default_rng(11); df = pd.concat([load(["A", "B"]), rf_table()]); th = fam_values(df, "sp_h"); tt = fam_values(df, "sp"); tn = fam_values(df, "ndcg_h"); mde_ = json.load(open(f"{C.RES}/mde.json")); out = dict(gate={}, curves={})
    for cand in ("h5", "h5nn"):
        passk = []; nogok = []
        for k in KS3:
            means = {a: th.loc[(a, k)].mean() for a in BASE}; bt = max(means, key=means.get); d = (th.loc[(cand, k)] - th.loc[(bt, k)]).dropna(); ci = tint(d.values); cip = boot(d.values, rng); do = (tt.loc[(cand, k)] - tt.loc[(bt, k)]).dropna()
            dn = (tn.loc[(cand, k)] - tn.loc[(bt, k)]).dropna(); ok = bool(d.mean() >= 0.03 and ci[0] > 0); passk.append(ok); nogo = bool(ci[1] < 0.03); nogok.append(nogo)
            per_rep = df[(df.alias == cand) & (df.k == k)].groupby(["repeat", "family", "target"]).sp_h.mean().groupby(["repeat", "family"]).mean().groupby("repeat").mean() - \
                      df[(df.alias == bt) & (df.k == k) & (df.repeat >= 0)].groupby(["repeat", "family", "target"]).sp_h.mean().groupby(["repeat", "family"]).mean().groupby("repeat").mean() if bt != "rf" else None
            out["gate"][f"{cand}|k{k}"] = dict(best_baseline=bt, baseline_means=means, cand_mean_hard=float(th.loc[(cand, k)].mean()), diff_hard=float(d.mean()), ci95_cluster_t_PRIMARY=ci, ci95_family_percentile_bootstrap_SECONDARY=cip, margin_excluded_from_above=nogo, n_families=int(len(d)), pass_k=ok, MDE80=mde_[f"k{k}"]["MDE80"],
                                               overall=dict(diff=float(do.mean()), ci95_cluster_t=tint(do.values), ci95_percentile_secondary=boot(do.values, rng)), ndcg_hard=dict(diff=float(dn.mean()), ci95_cluster_t=tint(dn.values), ci95_percentile_secondary=boot(dn.values, rng)),
                                               repeat_spread_of_mean_diff=None if per_rep is None else dict(min=float(per_rep.min()), median=float(per_rep.median()), max=float(per_rep.max())))
        vocab = "GO" if sum(passk) >= 2 else ("NO-GO-detectable" if sum(nogok) >= 2 else "INCONCLUSIVE")
        out["gate"][cand] = dict(passes=int(sum(passk)), margin_excluded_from_above_at_k=int(sum(nogok)), verdict=vocab, MDEs=[mde_[f"k{k}"]["MDE80"] for k in KS3],
                                 note="screening verdict (exploratory re-analysis of pilot-4 families; not paper evidence). GO = registered rule at >=2 of 3 k (mean >= +0.03 and cluster-t lower bound > 0); NO-GO-detectable = cluster-t upper bound < +0.03 at >=2 of 3 k; otherwise INCONCLUSIVE. Any compute decision taken from this verdict is a judgement call; the interval against the margin is the evidence.")
    for a in list(BASE) + ["h5", "h5nn"]:
        out["curves"][a] = {}
        for k in (0, 1, 3, 5, 10, 25):
            if (a, k) not in th.index.droplevel(2) and (a, k) not in tt.index.droplevel(2): continue
            o = tt.loc[(a, k)].dropna() if (a, k) in tt.index.droplevel(2) else pd.Series(dtype=float); h = th.loc[(a, k)].dropna() if (a, k) in th.index.droplevel(2) else pd.Series(dtype=float)
            out["curves"][a][k] = dict(overall=[float(o.mean())] + tint(o.values) if len(o) else None, hard=[float(h.mean())] + tint(h.values) if len(h) else None, n_fam=int(len(o)))
    cfgs = [json.load(open(f)) for f in sorted(glob.glob(f"{C.RES}/configs/cfg_r*_f*.json"))]
    from collections import Counter
    out["selected_config_counts"] = {a: dict(Counter(c["selected"][a] for c in cfgs)) for a in ("nn", "gp", "d", "h5", "h5nn")}
    json.dump(out, open(f"{C.RES}/gate_summary.json", "w"), indent=1, default=float)
    for cand in ("h5", "h5nn"):
        print(cand, out["gate"][cand])
        for k in KS3: g = out["gate"][f"{cand}|k{k}"]; print("  k", k, "vs", g["best_baseline"], "diff", round(g["diff_hard"], 4), [round(x, 4) for x in g["ci95_cluster_t_PRIMARY"]], "MDE80", round(g["MDE80"], 4), "pass", g["pass_k"])


if __name__ == "__main__":
    {"mde": mde, "gate": gate}[sys.argv[1]]()
