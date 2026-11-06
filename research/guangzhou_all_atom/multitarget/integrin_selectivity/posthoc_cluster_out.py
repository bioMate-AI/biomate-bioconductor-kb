"""POST-HOC diagnostic (not pre-registered): is the LOLO structure gain only within-chemotype interpolation?
Leave-chemotype-out: hold out all ligands of one cluster, train on the remaining structure ligands."""
import json, numpy as np, sys
sys.argv = ["x"]
import importlib.util, io, contextlib
# reuse model definitions without re-running the whole analysis: exec the head of analysis.py
src = open("analysis.py").read().split("# ================================================================== (a) LOLO")[0]
exec(src)
CL = {"linear_RGD_peptides": ["RGD", "RGDS", "GRGD", "GRGDS", "GRGDSP", "GRGDSPK", "GRGDNP", "GRGDTP"],
      "cyclic_RGD_pentapeptides": ["Cilengitide", "c(RGDfK)", "c(RGDyK)", "c(RGDfV)"],
      "other_ligands": ["Eptifibatide", "Tirofiban", "ATN161", "GR144053"]}
idx = {k: [lig_names.index(n) for n in v] for k, v in CL.items()}
out = {}
rng = np.random.default_rng(7)
for cname, held in idx.items():
    tr = [i for i in S_all if i not in held]
    rows = {"N1_mean": [], "M1_ridge_morgan": [], "M2_tanimoto_gp": []}
    pr = {"N1_mean": lambda tr, i: Y[tr].mean(0), "M1_ridge_morgan": m1_ridge, "M2_tanimoto_gp": m2_gp}
    err = {k: [] for k in pr}
    for i in held:
        for k, f in pr.items():
            p = f(tr, i)
            for j in range(5):
                if not C[i, j]: err[k].append((p[j] - Y[i, j]) ** 2)
    out[cname] = {k: float(np.sqrt(np.mean(v))) for k, v in err.items()}
    out[cname]["n_cells_unc"] = len(err["N1_mean"]); out[cname]["n_train"] = len(tr)
print(json.dumps(out, indent=1)); json.dump(out, open("posthoc_cluster_out.json", "w"), indent=1)
