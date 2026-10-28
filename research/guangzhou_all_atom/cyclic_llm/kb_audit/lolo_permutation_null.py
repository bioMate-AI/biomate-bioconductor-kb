"""Permutation-null audit of the leave-one-lab-out channel result (own harness; reads workstream 4's annotation/pair tables only).
Observed: for every held-out lab, rules are mined on the OTHER labs (peptide_sar_kb.fit), K_phys/K_nme/K_total are computed for that lab, and Spearman(K, within-source label)
is taken. Nulls (all keep the held-out lab's labels fixed and the rules fixed, so the null is conditional on the mined rules, which never saw that lab):
  N1 within-lab permutation of K across the lab's peptides  (exactly preserves the lab's K marginal distribution and the source structure; breaks the association)
  N2 global permutation of K across all eligible-lab peptides (preserves the pooled K marginal, destroys lab structure)
  N3 label permutation within lab (equivalent to N1 for Spearman; reported as a check)
Outputs per-lab permutation p-values, the null distribution of the MEDIAN per-lab rho, and p-values for the observed median/pooled rho."""
import os, sys, json
import numpy as np, pandas as pd
from scipy.stats import spearmanr, rankdata, binomtest
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "stratification"))
import common as C, peptide_sar_kb as P
d = C.load_labelled(); pairs = pd.read_csv(os.path.join(HERE, "..", "stratification", "data", "mmp_pairs_pampa.csv.gz"))
vc = d.Source.value_counts(); elig = sorted(vc[vc >= P.MIN_SRC_N].index); d = d[d.Source.isin(elig)].copy(); pairs = pairs[pairs.source.isin(elig)].copy()
B = int(sys.argv[1]) if len(sys.argv) > 1 else 20000; rng = np.random.default_rng(12345)
K = {}; Y = {}
for L in elig:
    rs = P.fit(pairs, d, [s for s in elig if s != L]); te = d[d.Source == L]; ch = rs.channel(te)
    K[L] = {k: ch[k].values.astype(float) for k in ("K_phys", "K_nme", "K_total")}; Y[L] = te.y.values.astype(float)
def rho(a, b):
    ra, rb = rankdata(a), rankdata(b); ra = ra - ra.mean(); rb = rb - rb.mean(); den = np.sqrt((ra ** 2).sum() * (rb ** 2).sum()); return float((ra * rb).sum() / den) if den > 0 else np.nan
out = {}
for key in ("K_phys", "K_nme", "K_total"):
    labs = [L for L in elig if np.std(K[L][key]) > 0]; obs = np.array([rho(K[L][key], Y[L]) for L in labs])
    # N1: within-lab permutation of K (vectorised over B using rank arrays)
    nul1 = np.zeros((B, len(labs))); pl = []
    for j, L in enumerate(labs):
        rk = rankdata(K[L][key]) - (len(Y[L]) + 1) / 2; ry = rankdata(Y[L]) - (len(Y[L]) + 1) / 2; den = np.sqrt((rk ** 2).sum() * (ry ** 2).sum())
        idx = np.argsort(rng.random((B, len(rk))), axis=1); nul1[:, j] = (rk[idx] * ry).sum(1) / den
        pl.append(float((np.sum(np.abs(nul1[:, j]) >= abs(obs[j])) + 1) / (B + 1)))
    med_obs = float(np.median(obs)); med_null = np.median(nul1, axis=1); p_med = float((np.sum(med_null >= med_obs) + 1) / (B + 1))
    # pooled held-out rho (peptides of all labs together) and its within-lab-permutation null
    allk = np.concatenate([K[L][key] for L in labs]); ally = np.concatenate([Y[L] for L in labs]); pooled_obs = rho(allk, ally)
    sizes = [len(Y[L]) for L in labs]; cuts = np.cumsum(sizes)[:-1]; pooled_null = np.zeros(2000)
    for b in range(2000):
        kk = np.concatenate([K[L][key][rng.permutation(len(Y[L]))] for L in labs]); pooled_null[b] = rho(kk, ally)
    p_pool = float((np.sum(pooled_null >= pooled_obs) + 1) / 2001)
    # N2: global permutation of K across all eligible peptides (destroys lab structure)
    g = np.zeros(2000)
    for b in range(2000):
        kk = rng.permutation(allk); parts = np.split(kk, cuts); g[b] = np.median([rho(parts[j], Y[L]) for j, L in enumerate(labs)])
    p_glob = float((np.sum(g >= med_obs) + 1) / 2001)
    sign = binomtest(int((obs > 0).sum()), len(obs), 0.5, alternative="greater").pvalue
    out[key] = dict(n_labs=len(labs), observed_median=med_obs, observed_per_lab=dict(zip(labs, map(float, obs))), per_lab_perm_p=dict(zip(labs, pl)),
                    n_labs_p_lt_0_05=int(sum(p < 0.05 for p in pl)), n_labs_p_lt_0_05_expected_under_null=round(0.05 * len(labs), 2),
                    null_median_mean=float(med_null.mean()), null_median_sd=float(med_null.std()), null_median_95=[float(np.percentile(med_null, 2.5)), float(np.percentile(med_null, 97.5))],
                    p_observed_median_vs_within_lab_null=p_med, pooled_observed=pooled_obs, pooled_null_mean=float(pooled_null.mean()), pooled_null_sd=float(pooled_null.std()),
                    p_pooled_vs_within_lab_null=p_pool, null_median_global_perm_mean=float(g.mean()), null_median_global_perm_sd=float(g.std()), p_median_vs_global_null=p_glob,
                    sign_test_p=float(sign), n_positive=int((obs > 0).sum()))
json.dump(out, open(os.path.join(HERE, "lolo_permutation_null.json"), "w"), indent=1)
for k, o in out.items():
    print("%-8s labs %d | observed median %.3f | within-lab null median %.3f ± %.3f (95%% [%.3f, %.3f]) p=%.4g | global-perm null %.3f ± %.3f p=%.4g | pooled %.3f vs null %.3f ± %.3f p=%.4g | labs p<0.05: %d (expect %.1f) | sign test %d/%d p=%.3g" % (
        k, o["n_labs"], o["observed_median"], o["null_median_mean"], o["null_median_sd"], *o["null_median_95"], o["p_observed_median_vs_within_lab_null"], o["null_median_global_perm_mean"], o["null_median_global_perm_sd"],
        o["p_median_vs_global_null"], o["pooled_observed"], o["pooled_null_mean"], o["pooled_null_sd"], o["p_pooled_vs_within_lab_null"], o["n_labs_p_lt_0_05"], o["n_labs_p_lt_0_05_expected_under_null"], o["n_positive"], o["n_labs"], o["sign_test_p"]))
print({L: round(p, 4) for L, p in out["K_phys"]["per_lab_perm_p"].items()})
