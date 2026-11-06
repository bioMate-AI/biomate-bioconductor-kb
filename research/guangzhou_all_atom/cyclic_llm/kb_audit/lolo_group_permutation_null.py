"""Stricter null for K_phys: K is constant within a flat-structure group (stereoisomers share 2D descriptors), so peptides are not exchangeable. Permute K at the
GROUP level (each flat-structure group receives another group's K value) within each held-out lab; labels fixed. Reports per-lab p, labs with p<0.05, null of the median."""
import os, sys, json
import numpy as np, pandas as pd
from scipy.stats import rankdata
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "stratification"))
import common as C, peptide_sar_kb as P
d = C.load_labelled(); pairs = pd.read_csv(os.path.join(HERE, "..", "stratification", "data", "mmp_pairs_pampa.csv.gz"))
vc = d.Source.value_counts(); elig = sorted(vc[vc >= P.MIN_SRC_N].index); d = d[d.Source.isin(elig)].copy(); pairs = pairs[pairs.source.isin(elig)].copy()
rng = np.random.default_rng(7); B = 5000; res = {}; nulls = []; obsl = []
def rho(a, b):
    ra, rb = rankdata(a) - rankdata(a).mean(), rankdata(b) - rankdata(b).mean(); den = np.sqrt((ra ** 2).sum() * (rb ** 2).sum()); return (ra * rb).sum() / den if den > 0 else np.nan
for L in elig:
    rs = P.fit(pairs, d, [s for s in elig if s != L]); te = d[d.Source == L]; k = rs.channel(te)["K_phys"].values; y = te.y.values
    g, inv = np.unique(te.flat_smiles.values, return_inverse=True); ng = len(g)
    kg = np.array([k[inv == j].mean() for j in range(ng)]); const = bool(np.allclose([k[inv == j].std() for j in range(ng)], 0, atol=1e-9))
    o = rho(k, y); nul = np.array([rho(kg[rng.permutation(ng)][inv], y) for _ in range(B)])
    res[L] = dict(n=int(len(y)), n_groups=int(ng), K_const_within_group=const, rho=float(o), p=float((np.sum(np.abs(nul) >= abs(o)) + 1) / (B + 1)))
    nulls.append(nul); obsl.append(o)
N = np.array(nulls); med_null = np.median(N, axis=0); med_obs = float(np.median(obsl))
out = dict(observed_median=med_obs, null_median_mean=float(med_null.mean()), null_median_sd=float(med_null.std()), null_median_95=[float(np.percentile(med_null, 2.5)), float(np.percentile(med_null, 97.5))],
           p_median=float((np.sum(med_null >= med_obs) + 1) / (B + 1)), n_labs=len(elig), n_labs_p_lt_0_05=int(sum(v["p"] < 0.05 for v in res.values())), expected=round(0.05 * len(elig), 2), per_lab=res)
json.dump(out, open(os.path.join(HERE, "lolo_group_permutation_null.json"), "w"), indent=1)
print({k: v for k, v in out.items() if k != "per_lab"}); print({L: (v["n_groups"], round(v["rho"], 2), round(v["p"], 3)) for L, v in res.items()})
