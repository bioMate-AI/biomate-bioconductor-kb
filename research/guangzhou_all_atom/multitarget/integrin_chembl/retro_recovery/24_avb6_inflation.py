"""A11 item 4: quantify the inflation of the alpha-v-beta-6 / integrin subset caused by v1 families (complex and subunit entries in different families).
B3 (max Tanimoto to other-family positives, item's own flat excluded) and B1_rgd recomputed for the integrin subset of M and I under v1 vs v2 family exclusion; shared compounds between the two avb6 entries."""
import os, sys, json
import numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; sys.path.insert(0, HERE); import harness as H
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); pos = P[P.label == "pos"]
T1 = pd.read_csv(f"{DATA}/targets.csv"); T2 = pd.read_csv(f"{DATA}/targets_v2.csv"); fam = {1: dict(zip(T1.target_key, T1.family)), 2: dict(zip(T2.target_key, T2.family))}; genes = dict(zip(T1.target_key, T1.genes.fillna("")))
gen = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True); ids = sorted(set(P.compound_id)); idx = {c: i for i, c in enumerate(ids)}
X = np.stack([np.array(list(gen.GetFingerprintAsNumPy(Chem.MolFromSmiles(C.loc[c, "iso_smiles"]))), np.uint8) for c in ids]).astype(np.float32); xs = X.sum(1); flat = np.array(C.flat_key.reindex(ids).astype(str).tolist())
out = {}
a, b = "P06756,P18564", "P18564"
sa = set(P[(P.target_key == a)].compound_id); sb = set(P[(P.target_key == b)].compound_id); pa = set(pos[pos.target_key == a].compound_id); pb = set(pos[pos.target_key == b].compound_id)
out["avb6_complex_vs_beta6_alone"] = dict(compounds_complex=len(sa), compounds_beta6=len(sb), shared_compounds=len(sa & sb), shared_flat_structures=len(set(C.loc[list(sa & sb), "flat_key"])), positives_shared=len(pa & pb), positives_complex=len(pa), positives_beta6=len(pb))
for name in ("M", "I"):
    it = pd.read_csv(f"{DATA}/items_{name}.csv.gz"); itg = [t for t in it.target_key.unique() if "ITG" in genes[t].upper()]; avb = [t for t in it.target_key.unique() if "ITGB6" in genes[t].upper()]; res = {}
    for ver in (1, 2):
        posfam = pos.assign(f=pos.target_key.map(fam[ver])).groupby("compound_id").f.apply(set).to_dict()
        for sub, tl in (("avb6_targets", avb), ("integrin_targets", itg)):
            aucs = {"B3_nn_neg": [], "B1_rgd": []}; fams_n = len({fam[ver][t] for t in tl})
            for t in tl:
                g = it[it.target_key == t]; ii = np.array([idx[c] for c in g.compound_id]); F = fam[ver][t]; refs = np.array([idx[c] for c in posfam if F not in posfam[c]])
                inter = X[ii] @ X[refs].T; S = inter / (xs[ii][:, None] + xs[refs][None, :] - inter + 1e-9); S[flat[ii][:, None] == flat[refs][None, :]] = -1.0
                aucs["B3_nn_neg"].append((F, H.tie_aware_auc(g.label.values, -S.max(1)))); aucs["B1_rgd"].append((F, H.tie_aware_auc(g.label.values, C.loc[g.compound_id, "rgd"].astype(float).values)))
            res[f"v{ver}_{sub}"] = dict(targets=len(tl), families=fams_n, **{k: round(float(pd.DataFrame(v, columns=["f", "a"]).groupby("f").a.mean().mean()), 3) if v else None for k, v in aucs.items()})
    out[name] = res
json.dump(out, open(f"{RES}/avb6_inflation.json", "w"), indent=1); print(json.dumps(out, indent=1))
