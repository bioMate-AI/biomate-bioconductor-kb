"""Label-noise ceiling from duplicate measurements (same pid, same assay, DIFFERENT source)."""
import numpy as np, pandas as pd, json, itertools
from common import *
c = pd.read_csv(CLEAN); out = {}
def est(df, name):
    d2 = []; 
    for (pid, a), g in df.groupby(["pid", "assay"]):
        if g.source.nunique() < 2: continue
        v = g.groupby("source").y.mean().values
        for i, j in itertools.combinations(range(len(v)), 2): d2.append((v[i] - v[j]) ** 2)
    if not d2: return None
    s2 = float(np.mean(d2) / 2); var = float(df.y.var())
    return {"n_pairs": len(d2), "sigma2_noise": s2, "sigma_noise": s2 ** .5, "var_y_all": var, "ceiling_r2": 1 - s2 / var,
            "ceiling_rmse_floor": s2 ** .5, "var_y_of_duplicated_peptides": float(df[df.pid.isin(df.groupby('pid').source.nunique().loc[lambda s: s > 1].index)].y.var())}
out["all_assays_pooled_same_assay_pairs"] = est(c, "all")
for a in ["PAMPA", "Caco2"]: out[a] = est(c[c.assay == a], a)
# same-peptide cross-assay (PAMPA vs Caco2) for context
p = c[c.assay == "PAMPA"].groupby("pid").y.mean(); q = c[c.assay == "Caco2"].groupby("pid").y.mean(); j = p.index.intersection(q.index)
out["pampa_vs_caco2_same_peptide"] = {"n": int(len(j)), "pearson": float(np.corrcoef(p[j], q[j])[0, 1]) if len(j) > 2 else None, "mean_abs_diff": float((p[j] - q[j]).abs().mean()) if len(j) else None}
w=[]
for (pid,a,src),g in c.groupby(['pid','assay','source']):
    if len(g)>1: w.append(g.y.var(ddof=1))
out['within_source_replicates']={'n_groups':len(w),'sigma2_noise':float(np.mean(w)) if w else None}
json.dump(out, open(os.path.join(HERE, "results/noise_ceiling.json"), "w"), indent=1); print(json.dumps(out, indent=1))
