"""Noise ceiling for edit effects (amendment A1.3). usage: python3 ceiling.py RAW_CycPeptMPDB.csv OUT.json
sigma_cross from true same-peptide cross-laboratory PAMPA records (Same_Peptides_* columns); includes lab offsets, so the resulting ceiling is a conservative (low) bound."""
import sys, ast, json, zlib, numpy as np, pandas as pd, os
HERE = os.path.dirname(os.path.abspath(__file__))
d = pd.read_csv(sys.argv[1], low_memory=False, usecols=lambda c: c in ("ID", "Source", "SMILES", "PAMPA", "Same_Peptides_Source", "Same_Peptides_Permeability", "Same_Peptides_Assay"))
d = d[d.PAMPA.notna() & (d.PAMPA > -9.99) & d.SMILES.notna()]; recs = {}
for _, r in d.iterrows():
    if not isinstance(r.Same_Peptides_Source, str): continue
    try: srcs = ast.literal_eval(r.Same_Peptides_Source); perm = ast.literal_eval(r.Same_Peptides_Permeability); assay = ast.literal_eval(r.Same_Peptides_Assay)
    except Exception: continue
    for s, pv, av in zip(srcs, perm, assay):
        if s == r.Source: continue
        v = [float(x) for x, a in zip(pv, av) if a == "PAMPA" and float(x) > -9.99]
        if not v: continue
        key = (r.SMILES, tuple(sorted([(r.Source, round(float(r.PAMPA), 4)), (s, round(float(np.mean(v)), 4))])))
        recs[key] = (r.SMILES, float(r.PAMPA), float(np.mean(v)))
df = pd.DataFrame(list(recs.values()), columns=["pep", "ya", "yb"]); out = dict(n_pairs=int(len(df)), n_peptides=int(df.pep.nunique()))
if out["n_peptides"] < 15: out["status"] = "not estimable (< 15 peptides)"
else:
    D = (df.ya - df.yb).values; sig = float(np.sqrt(np.mean(D ** 2) / 2)); out["sigma_cross"] = round(sig, 4)
    rng = np.random.default_rng(zlib.crc32(b"ceiling")); peps = df.pep.unique(); grp = {p: np.where(df.pep.values == p)[0] for p in peps}
    pairs = {k: pd.read_csv(os.path.join(HERE, "data", f"pairs_{k}.csv")) for k in ("nme", "dflip")}
    for k, p in pairs.items():
        var_obs = float(p.dy_raw.var()); r = {}
        def ceil(sg): 
            vn = 2 * sg ** 2; rel = max(0.0, var_obs - vn) / var_obs; return float(np.sqrt(rel))
        bs = []
        for _ in range(2000):
            pick = rng.choice(len(peps), len(peps)); ii = np.concatenate([grp[peps[i]] for i in pick]); bs.append(ceil(np.sqrt(np.mean(D[ii] ** 2) / 2)))
        out[k] = dict(var_observed_effect_raw=round(var_obs, 4), noise_var_effect=round(2 * sig ** 2, 4), reliability=round(max(0.0, var_obs - 2 * sig ** 2) / var_obs, 4), ceiling_corr=round(ceil(sig), 4), ceiling_ci=[round(float(np.percentile(bs, 2.5)), 4), round(float(np.percentile(bs, 97.5)), 4)], note="conservative: sigma_cross includes lab offsets; applies to raw log-Papp effects, used as an approximate ceiling for rank correlation")
json.dump(out, open(os.path.join(HERE, "data", "ceiling.json"), "w"), indent=1); print(json.dumps(out, indent=1))
