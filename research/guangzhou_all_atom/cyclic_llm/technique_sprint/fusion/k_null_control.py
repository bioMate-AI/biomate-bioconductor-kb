"""Dedicated negative control for the prior K_phys (PREREG sec. 6.2): labels permuted within each lab (as kb_audit.lolo_evaluate shuffle), rules re-mined on the other
shuffled labs, K_phys scored on the held-out lab's shuffled labels (whole lab, no reveal). Many shuffles because K is non-constant only when a spurious rule becomes active.
Aggregation: (shuffle, lab) rows with non-constant K; bootstrap over shuffles (cluster) of the mean Spearman. usage: python3 k_null_control.py [n_shuffles]"""
import sys, os, json
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import perm_testbed as T, fusion as F, peptide_sar_kb as P
NS = int(sys.argv[1]) if len(sys.argv) > 1 else 40
d0, dfull, pairs0, elig = T.load(); rows = []
for sh in range(NS):
    d = d0.copy(); pr = pairs0.copy(); rng = np.random.default_rng(1000 + sh)
    for s in d.Source.unique():
        m = (d.Source == s).values; d.loc[m, "y_raw"] = rng.permutation(d.loc[m, "y_raw"].values); d.loc[m, "y"] = rng.permutation(d.loc[m, "y"].values)
    ym = d["y_raw"].to_dict(); zm = d["y"].to_dict(); pr["y_a"] = pr.id_a.map(ym); pr["y_b"] = pr.id_b.map(ym); pr["z_a"] = pr.id_a.map(zm); pr["z_b"] = pr.id_b.map(zm)
    for L in elig:
        rs = P.fit(pr, d, [e for e in elig if e != L]); dl = d[d.Source == L]; K = rs.channel(dl)["K_phys"].values
        n_act = sum(v.get("status") == "rule" and v.get("kind") == "physchem" for v in rs.rules.values())
        rows.append(dict(shuffle=sh, lab=L, n=len(dl), n_active_phys=n_act, nonconst=bool(np.std(K) > 1e-12), rho=F.spearman(K, dl.y_raw.values)))
    if sh % 5 == 0: print("shuffle", sh, flush=True)
D = pd.DataFrame(rows); D.to_csv(f"{HERE}/results/k_null_control_rows.csv", index=False)
nc = D[D.nonconst & D.rho.notna()]; by = nc.groupby("shuffle").rho.mean().dropna().values
rng = np.random.default_rng(5); idx = rng.integers(0, len(by), (2000, len(by))); bm = by[idx].mean(1) if len(by) else np.array([np.nan])
out = dict(n_shuffles=NS, rows_total=int(len(D)), rows_nonconstant=int(len(nc)), shuffles_with_nonconstant=int(len(by)), mean_rho=float(nc.rho.mean()) if len(nc) else None,
           mean_of_shuffle_means=float(by.mean()) if len(by) else None, ci95_over_shuffles=[float(np.percentile(bm, 2.5)), float(np.percentile(bm, 97.5))], frac_rows_active=float(D.nonconst.mean()))
json.dump(out, open(f"{HERE}/results/k_null_control.json", "w"), indent=1); print(json.dumps(out, indent=1))
