"""A11 item 3: compound / near-duplicate leakage rates across folds (v1 and v2 folds). Pure RDKit + numpy.
For each analysis (I, I_CD, M2) and fold scheme: share of rows whose compound (exact isomeric id, flat structure, or Tanimoto>=0.90 neighbour) is labelled in ANOTHER fold; reported separately for positives and inactives/decoys; scope = all labelled pairs."""
import os, json
import numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); flat = C.flat_key
schemes = {}
for v, tgt in ((1, "targets.csv"), (2, "targets_v2.csv")):
    T = pd.read_csv(f"{DATA}/{tgt}"); fo = pd.read_csv(f"{DATA}/folds_v{v}.csv"); fam = dict(zip(T.target_key, T.family)); fold = dict(zip(fo.family, fo.fold)); schemes[v] = {t: fold[fam[t]] for t in T.target_key}
ids = sorted(set(P.compound_id)); idx = {c: i for i, c in enumerate(ids)}
gen = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
X = np.stack([np.array(list(gen.GetFingerprintAsNumPy(Chem.MolFromSmiles(C.loc[c, "iso_smiles"]))), np.uint8) for c in ids]).astype(np.float32); xs = X.sum(1)
out = {}
for v in (1, 2):
    P["fold"] = P.target_key.map(schemes[v]); fold_of_comp = P.groupby("compound_id").fold.apply(set); fold_of_flat = P.assign(flat=P.compound_id.map(flat)).groupby("flat").fold.apply(set)
    res = {"labelled_compounds": len(ids), "compounds_in_gt1_fold": float(np.mean([len(s) > 1 for s in fold_of_comp])), "flat_structures_in_gt1_fold": float(np.mean([len(s) > 1 for s in fold_of_flat]))}
    # Tanimoto >= 0.90 neighbour in another fold: for each compound, max sim to compounds labelled in folds other than its own set
    comp_fold_mask = {f: np.array([f in fold_of_comp[c] for c in ids]) for f in range(5)}; near = {}
    for a in range(0, len(ids), 1000):
        inter = X[a:a + 1000] @ X.T; S = inter / (xs[a:a + 1000, None] + xs[None, :] - inter + 1e-9)
        for r in range(S.shape[0]): S[r, a + r] = -1
        for r in range(S.shape[0]):
            c = ids[a + r]; mine = fold_of_comp[c]; other = np.zeros(len(ids), bool)
            for f in range(5):
                if f not in mine: other |= comp_fold_mask[f]
            near[c] = float(S[r][other].max()) if other.any() else 0.0
    for name, path in (("I", "items_I.csv.gz"), ("I_CD", "items_I_CD.csv.gz"), ("M2", "items_M2.csv.gz")):
        it = pd.read_csv(f"{DATA}/{path}"); it["fold"] = it.target_key.map(schemes[v]); r2 = {}
        for lab, nm in ((1, "positives"), (0, "inactives_or_decoys")):
            d = it[it.label == lab]
            if d.empty: continue
            exact = np.mean([len(fold_of_comp[c] - {f}) > 0 for c, f in zip(d.compound_id, d.fold)]); flt = np.mean([len(fold_of_flat[flat[c]] - {f}) > 0 for c, f in zip(d.compound_id, d.fold)])
            nb = np.array([near[c] for c in d.compound_id]); r2[nm] = dict(rows=int(len(d)), exact_compound_in_other_fold=round(float(exact), 4), flat_structure_in_other_fold=round(float(flt), 4), tanimoto_ge_0p90_neighbour_in_other_fold=round(float((nb >= 0.90).mean()), 4), tanimoto_ge_0p70=round(float((nb >= 0.70).mean()), 4))
        res[name] = r2
    out[f"folds_v{v}"] = res
json.dump(out, open(f"{RES}/leakage_rates.json", "w"), indent=1); print(json.dumps(out, indent=1))
