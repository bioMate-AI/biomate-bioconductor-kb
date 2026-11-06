"""Runs the pre-registered analyses (README section 2). Writes results.json and learning_curve.png."""
import json, itertools, sys
import numpy as np, pandas as pd
from sklearn.linear_model import Ridge, LinearRegression
from common import RAW, HERE, DOMAINS, spearman, boot_ci, domain_ci
from build_table import build_all, avail_table
import models as M

PCA2_DOMS = ["363", "366", "385"]
ALL_DOMS = sorted(DOMAINS)
SEED = 0


def attach(t):
    p2 = pd.read_csv(f"{RAW}/PCA2/PWM_score.csv")
    p2["domain"] = p2.pool.map({"P4": "363", "P5": "366", "P6": "385"})
    p2 = p2.groupby(["domain", "aa_seq"]).score.mean().rename("pwm").reset_index()
    p2["dataset"] = "PCA2"
    p1 = pd.read_csv(f"{RAW}/PCA1/PWM_scores.csv")
    p1["domain"] = p1.name.astype(str)
    p1 = p1[p1.domain.isin(ALL_DOMS)].groupby(["domain", "aa_seq"]).PWM_score.mean().rename("pwm").reset_index()
    p1["dataset"] = "PCA1"
    t = t.merge(pd.concat([p1, p2]), on=["dataset", "domain", "aa_seq"], how="left")
    av = avail_table(); t["avail"] = t.aa_seq.map(av)
    return t


def avail_frame():
    """Peptide-only availability with family label (for the 'deployable' availability predictor)."""
    a1 = pd.read_csv(f"{RAW}/PCA1/med_avail_score.csv")
    a1 = a1[a1.family.str.startswith("PRM_")].copy(); a1["family"] = a1.family.str.replace("PRM_0", "", regex=False)
    a1 = a1[~a1.aa_seq.str.contains(r"\*")]
    return a1[["aa_seq", "family", "med_norm"]].rename(columns={"med_norm": "score"})


def zs(x):
    x = np.asarray(x, float); return (x - np.nanmean(x)) / (np.nanstd(x) + 1e-12)


def stack_prom_pwm(tr, te):
    """Exploratory (e): promiscuity + z(PWM) linear stack; promiscuity of a train domain is computed leaving that domain out."""
    X, y = [], []
    for d, g in tr.groupby("domain"):
        others = tr[tr.domain != d]
        pr = M.null_promiscuity(others, g)
        ok = np.isfinite(pr) & np.isfinite(g.pwm.values)
        X.append(np.c_[pr[ok], zs(g.pwm.values[ok])]); y.append(g.score.values[ok])
    if not X or sum(len(v) for v in y) == 0:
        return np.full(len(te), np.nan)
    X = np.vstack(X); y = np.concatenate(y)
    lr = LinearRegression().fit(X, y)
    pr = M.null_promiscuity(tr, te); pw = zs(te.pwm.values)
    out = np.full(len(te), np.nan); ok = np.isfinite(pr) & np.isfinite(pw)
    out[ok] = lr.predict(np.c_[pr[ok], pw[ok]])
    return out


def predict_all(tr, te, sim, desc, with_prom=True):
    P = {}
    if with_prom:
        P["null_a_promiscuity"] = M.null_promiscuity(tr, te)
    P["null_b_additive_position"] = M.null_additive_position(tr, te)
    P["null_c_pwm"] = M.pwm_scores(te)
    P["null_d_physchem"] = M.null_physchem(tr, te)
    P["model_i_additive_offsets"] = M.model_additive_offsets(tr, te)
    P["model_ii_lowrank"] = M.model_lowrank(tr, te, sim)
    P["model_iii_gbm"] = M.model_gbm(tr, te, desc)
    if with_prom:
        P["expl_e_prom_plus_pwm"] = stack_prom_pwm(tr, te)
    return P


def score_preds(P, te, ci=True):
    y = te.score.values; out = {}
    for k, p in P.items():
        r = spearman(p, y)
        out[k] = dict(rho=r, ci=boot_ci(p, y) if ci and np.isfinite(r) else (np.nan, np.nan), n=int(np.isfinite(p).sum()))
    return out


def summarise(per_dom):
    """per_dom: {domain: {pred: {rho,...}}} -> mean + CI over domains per predictor and diff vs best null."""
    preds = sorted({k for d in per_dom.values() for k in d})
    res = {k: domain_ci([per_dom[d][k]["rho"] for d in per_dom if k in per_dom[d]]) for k in preds}
    nulls = [k for k in preds if k.startswith("null_") and np.isfinite(res[k]["mean"])]
    best = max(nulls, key=lambda k: res[k]["mean"]) if nulls else None
    diffs = {}
    for k in preds:
        if k.startswith("model_") and best:
            dl = [per_dom[d][k]["rho"] - per_dom[d][best]["rho"] for d in per_dom if k in per_dom[d] and best in per_dom[d]]
            diffs[k] = domain_ci(dl)
    return dict(per_domain={d: {k: v for k, v in x.items()} for d, x in per_dom.items()}, over_domains=res, best_null=best, model_minus_best_null=diffs)


def clean(o):
    if isinstance(o, dict): return {str(k): clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [clean(v) for v in o]
    if isinstance(o, (np.floating, float)): return None if not np.isfinite(o) else float(o)
    if isinstance(o, (np.integer,)): return int(o)
    return o


def main():
    t, _ = build_all(); t = attach(t)
    sim, ident = M.blosum_similarity(); desc = M.domain_descriptors()
    R = {"identity": {a: {b: round(ident[a][b], 3) for b in ALL_DOMS} for a in ALL_DOMS},
         "max_offdiag_identity": max(ident[a][b] for a in ALL_DOMS for b in ALL_DOMS if a != b),
         "counts": {"PCA2_pairs": int((t.dataset == "PCA2").sum()), "PCA1_pairs": int((t.dataset == "PCA1").sum()),
                    "PCA2_domains": 3, "union_domains": 7,
                    "PCA2_unique_peptides": int(t[t.dataset == "PCA2"].aa_seq.nunique())}}
    pca1 = t[t.dataset == "PCA1"]; pca2 = t[t.dataset == "PCA2"]
    # noise ceiling for PCA2: expected rho of two independent noisy measurements ~ reliability
    rel = {}
    for d, g in pca2.groupby("domain"):
        var_tot = g.score.var(); var_noise = np.nanmean(g.se ** 2)
        rel[d] = dict(reliability=float(max(0, 1 - var_noise / var_tot)), ceiling_r=float(np.sqrt(max(0, 1 - var_noise / var_tot))))
    R["pca2_noise"] = rel
    # PCA1 vs PCA2 independent re-measurement of the same (PDZ, cognate peptide) pairs
    rep = {}
    for d in PCA2_DOMS:
        a = pca1[pca1.domain == d].set_index("aa_seq").score; b = pca2[(pca2.domain == d)].set_index("aa_seq").score
        j = pd.concat([a, b], axis=1, join="inner"); rep[d] = dict(n=len(j), rho=spearman(j.iloc[:, 0], j.iloc[:, 1]))
    R["pca1_vs_pca2_remeasurement"] = rep

    # ---------------- Analysis A: PCA2 only, 3 PDZ, LODO
    A_all, A_cog, A_res, A_noncog = {}, {}, {}, {}
    for d in PCA2_DOMS:
        tr, te = M.lodo_split(pca2, d)
        P = predict_all(tr, te, sim, desc)
        A_all[d] = score_preds(P, te)
        c = te.cognate.values
        A_cog[d] = score_preds({k: v[c] for k, v in P.items()}, te[c])
        A_noncog[d] = score_preds({k: v[~c] for k, v in P.items()}, te[~c])
        prom = P["null_a_promiscuity"]; ytrue = te.score.values - prom
        A_res[d] = {k: dict(rho=spearman(v - prom, ytrue), ci=(np.nan, np.nan), n=0) for k, v in P.items()
                    if k.startswith(("model_", "expl_")) or k in ("null_b_additive_position", "null_c_pwm", "null_d_physchem")}
        A_res[d]["null_c_pwm"]["rho"] = spearman(zs(te.pwm.values), ytrue)  # PWM alone vs the domain-specific residual
        A_res[d]["null_b_additive_position"]["rho"] = spearman(P["null_b_additive_position"], ytrue)
        A_res[d]["null_d_physchem"]["rho"] = spearman(P["null_d_physchem"], ytrue)
        for k in ("model_i_additive_offsets", "model_ii_lowrank", "model_iii_gbm", "expl_e_prom_plus_pwm"):
            A_res[d][k]["rho"] = spearman(P[k] - prom, ytrue)
    R["A_all_peptides"] = summarise(A_all); R["A_cognate_family"] = summarise(A_cog)
    R["A_noncognate_families"] = summarise(A_noncog)
    R["A_domain_specific_residual"] = summarise(A_res)

    # ---------------- Analysis B: 7 domains, PCA1 cognate test set
    B1, B2, S1, S2 = {}, {}, {}, {}
    for d in ALL_DOMS:
        te = pca1[pca1.domain == d]
        tr, _ = M.lodo_split(pca1, d); B1[d] = score_preds(predict_all(tr, te, sim, desc, with_prom=False), te)
        tr2, _ = M.lodo_split(t, d); P = predict_all(tr2, te, sim, desc, with_prom=False)
        B2[d] = score_preds({k: v for k, v in P.items() if k.startswith("model_")}, te)
        trs, _ = M.lodo_split(pca1, d, max_identity=0.30, ident=ident)
        S1[d] = score_preds({k: v for k, v in predict_all(trs, te, sim, desc, with_prom=False).items() if k.startswith(("model_", "null_b", "null_c", "null_d"))}, te) if len(trs) else {}
        other = "PDZ" if DOMAINS[d]["cls"] == "SH3" else "SH3"
        trc, _ = M.lodo_split(pca1, d, only_class=other)
        S2[d] = score_preds({k: v for k, v in predict_all(trc, te, sim, desc, with_prom=False).items() if k.startswith(("model_", "null_b", "null_c", "null_d"))}, te)
    R["B1_pca1_train"] = summarise(B1); R["B2_pca1_plus_pca2_train"] = summarise({d: {**B1[d], **{k + "@B2": v for k, v in B2[d].items()}} for d in B1})
    R["S1_identity_le_30"] = summarise(S1); R["S2_leave_class_out"] = summarise(S2)
    # B3: PCA2 cognate rows of the 3 PDZ as independent re-measurement, train on PCA1 other domains
    B3 = {}
    for d in PCA2_DOMS:
        te = pca2[(pca2.domain == d) & pca2.cognate]
        tr, _ = M.lodo_split(pca1, d); B3[d] = score_preds(predict_all(tr, te, sim, desc, with_prom=False), te)
    R["B3_pca2_cognate_test_pca1_train"] = summarise(B3)

    # ---------------- Analysis C: earlier benchmark (PWM, PWM+avail) on the 7 domains
    av = avail_frame(); C = {}
    for d in ALL_DOMS:
        te = pca1[pca1.domain == d].copy()
        tr = pca1[pca1.domain != d]
        # availability predictor for the deployable variant: trained only on other families' availability rows
        a_tr = av[av.family != d].merge(pca1[["aa_seq", "backbone"]].drop_duplicates("aa_seq"), on="aa_seq", how="left")
        # backbone for avail rows from family label
        bbmap = pca1.drop_duplicates("family").set_index("family").backbone
        a_tr["backbone"] = a_tr.family.map(bbmap); a_tr["domain"] = a_tr.family
        f = M.Feat(a_tr)
        ar = Ridge(alpha=10.0).fit(np.hstack([f.pos(a_tr), f.phys(a_tr)]), a_tr.score.values)
        te["avail_pred"] = ar.predict(np.hstack([f.pos(te), f.phys(te)]))
        # train the PWM+avail combiner on train domains (z-scored within domain)
        Xs, ys = [], []
        for dd, g in tr.groupby("domain"):
            ok = g.pwm.notna() & g.avail.notna()
            Xs.append(np.c_[zs(g.pwm[ok]), zs(g.avail[ok])]); ys.append(zs(g.score[ok]))
        lr = LinearRegression().fit(np.vstack(Xs), np.concatenate(ys))
        lr_pwm = LinearRegression().fit(np.vstack(Xs)[:, :1], np.concatenate(ys))
        ok = te.pwm.notna() & te.avail.notna()
        g = te[ok]; y = g.score.values
        out = {"pwm_all_rows": dict(rho=spearman(te.pwm, te.score), ci=boot_ci(te.pwm.values, te.score.values), n=int(te.pwm.notna().sum())),
               "pwm_common_rows": dict(rho=spearman(g.pwm, y), ci=boot_ci(g.pwm.values, y), n=len(g)),
               "pwm_plus_avail_measured": dict(rho=spearman(lr.predict(np.c_[zs(g.pwm), zs(g.avail)]), y), ci=(np.nan, np.nan), n=len(g)),
               "pwm_plus_avail_predicted": dict(rho=spearman(lr.predict(np.c_[zs(g.pwm), zs(g.avail_pred)]), y), ci=(np.nan, np.nan), n=len(g)),
               "avail_measured_alone": dict(rho=spearman(g.avail, y), ci=(np.nan, np.nan), n=len(g))}
        C[d] = out
    R["C_earlier_benchmark_pca1_7domains"] = summarise(C)
    # same for PCA2 3 PDZ (cognate rows) -- PWM available, avail from PCA1/P1 for most peptides
    C2 = {}
    for d in PCA2_DOMS:
        te = pca2[(pca2.domain == d) & pca2.cognate]
        tr = pca1[pca1.domain != d]
        Xs, ys = [], []
        for dd, g in tr.groupby("domain"):
            ok = g.pwm.notna() & g.avail.notna(); Xs.append(np.c_[zs(g.pwm[ok]), zs(g.avail[ok])]); ys.append(zs(g.score[ok]))
        lr = LinearRegression().fit(np.vstack(Xs), np.concatenate(ys))
        ok = te.pwm.notna() & te.avail.notna(); g = te[ok]; y = g.score.values
        C2[d] = {"pwm_common_rows": dict(rho=spearman(g.pwm, y), ci=boot_ci(g.pwm.values, y), n=len(g)),
                 "pwm_plus_avail_measured": dict(rho=spearman(lr.predict(np.c_[zs(g.pwm), zs(g.avail)]), y), ci=(np.nan, np.nan), n=len(g))}
    R["C2_earlier_benchmark_pca2_3pdz"] = summarise(C2)

    # ---------------- Learning curves
    rng = np.random.default_rng(SEED)
    names = ["null_b_additive_position", "null_d_physchem", "model_i_additive_offsets", "model_ii_lowrank", "model_iii_gbm"]
    LC = {n: {} for n in names}  # name -> k -> {domain: mean rho over subsets}
    for d in ALL_DOMS:
        te = pca1[pca1.domain == d]; others = [x for x in ALL_DOMS if x != d]
        for k in range(1, 7):
            combos = list(itertools.combinations(others, k))
            if len(combos) > 20:
                combos = [combos[i] for i in rng.choice(len(combos), 20, replace=False)]
            acc = {n: [] for n in names}
            for c in combos:
                tr = pca1[pca1.domain.isin(c)]
                P = predict_all(tr, te, sim, desc, with_prom=False)
                for n in names:
                    acc[n].append(spearman(P[n], te.score.values))
            for n in names:
                LC[n].setdefault(k, {})[d] = float(np.nanmean(acc[n]))
        print("LC done", d, flush=True)
    R["learning_curve_B_pca1"] = {n: {k: domain_ci(list(v.values())) for k, v in kk.items()} for n, kk in LC.items()}
    R["learning_curve_B_pca1_per_domain"] = {n: {k: v for k, v in kk.items()} for n, kk in LC.items()}
    # PWM line (no training) for reference
    R["pwm_mean_rho_pca1"] = domain_ci([C[d]["pwm_all_rows"]["rho"] for d in ALL_DOMS])
    # learning curve A (k=1,2) on PCA2, same-peptide cross-domain
    LCA = {n: {1: {}, 2: {}} for n in names + ["null_a_promiscuity"]}
    for d in PCA2_DOMS:
        te = pca2[pca2.domain == d]; others = [x for x in PCA2_DOMS if x != d]
        for k in (1, 2):
            accs = {n: [] for n in LCA}
            for c in itertools.combinations(others, k):
                tr = pca2[pca2.domain.isin(c)]; P = predict_all(tr, te, sim, desc)
                for n in LCA: accs[n].append(spearman(P[n], te.score.values))
            for n in LCA: LCA[n][k][d] = float(np.nanmean(accs[n]))
    R["learning_curve_A_pca2"] = {n: {k: domain_ci(list(v.values())) for k, v in kk.items()} for n, kk in LCA.items()}
    R["learning_curve_A_pca2_per_domain"] = {n: {k: v for k, v in kk.items()} for n, kk in LCA.items()}

    # ---------------- shuffled-label sanity
    perm = {}
    for d in PCA2_DOMS:
        tr, te = M.lodo_split(pca2, d); P = predict_all(tr, te, sim, desc)
        rs = {k: [] for k in P}
        for i in range(30):
            y = rng.permutation(te.score.values)
            for k, p in P.items(): rs[k].append(spearman(p, y))
        perm[d] = {k: float(np.nanmean(v)) for k, v in rs.items()}
    R["permutation_mean_rho_shuffled_test_labels"] = perm

    json.dump(clean(R), open(f"{HERE}/results.json", "w"), indent=1)
    make_plot(json.load(open(f"{HERE}/results.json")))
    print("done")


def make_plot(R):
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.2))
    cols = {"null_b_additive_position": "#888", "null_d_physchem": "#bbb", "model_i_additive_offsets": "#1f77b4",
            "model_ii_lowrank": "#2ca02c", "model_iii_gbm": "#d62728", "null_a_promiscuity": "#000"}
    for n, kk in R["learning_curve_B_pca1"].items():
        ks = sorted(int(k) for k in kk); m = [kk[str(k)]["mean"] for k in ks]
        lo = [kk[str(k)]["t_lo"] for k in ks]; hi = [kk[str(k)]["t_hi"] for k in ks]
        ax[0].plot(ks, m, "-o", color=cols[n], label=n.replace("_", " ")); ax[0].fill_between(ks, lo, hi, color=cols[n], alpha=0.08)
    pw = R["pwm_mean_rho_pca1"]["mean"]
    ax[0].axhline(pw, ls="--", color="k", lw=1, label="PWM (in vitro, no training)")
    ax[0].axhline(0, color="k", lw=0.5)
    ax[0].set_xlabel("number of training domains"); ax[0].set_ylabel("mean LODO Spearman (7 domains, PCA1 test)")
    ax[0].set_title("B: 7 domains (4 SH3 + 3 PDZ); band = t 95% CI over domains"); ax[0].legend(fontsize=6)
    for n, kk in R["learning_curve_A_pca2"].items():
        ks = sorted(int(k) for k in kk); ax[1].plot(ks, [kk[str(k)]["mean"] for k in ks], "-o", color=cols[n], label=n.replace("_", " "))
    ax[1].set_xticks([1, 2]); ax[1].set_xlabel("number of training domains"); ax[1].set_ylabel("mean LODO Spearman (3 PDZ, PCA2)")
    ax[1].set_title("A: PCA2, 3 PDZ x 3 peptide families (k<=2)"); ax[1].axhline(0, color="k", lw=0.5); ax[1].legend(fontsize=6)
    plt.tight_layout(); plt.savefig(f"{HERE}/learning_curve.png", dpi=130)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "plot":
        make_plot(json.load(open(f"{HERE}/results.json")))
    else:
        main()
