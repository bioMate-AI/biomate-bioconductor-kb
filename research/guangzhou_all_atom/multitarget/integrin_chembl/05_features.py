"""Step 5: compound universe, fingerprints, kernels, Butina clusters. Heavy arrays go to the scratchpad cache (not committed)."""
import os, numpy as np, pandas as pd, json
from multiprocessing import Pool
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import Descriptors, rdFingerprintGenerator
from rdkit.ML.Cluster import Butina
from scipy.spatial.distance import cdist
RDLogger.DisableLog("rdApp.*")
CACHE = os.environ.get("INTEGRIN_CACHE", "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad") + "/feat"
os.makedirs(CACHE, exist_ok=True)
L = pd.read_csv("data/long_all.csv.gz"); E = pd.read_csv("data/external_ligands.csv"); E = E[E.smiles.notna()]
comp = pd.concat([L[["cmpd_key", "smiles"]].drop_duplicates("cmpd_key"), E.rename(columns={"flat_key": "cmpd_key"})[["cmpd_key", "smiles"]]]).drop_duplicates("cmpd_key").reset_index(drop=True)
comp["ci"] = np.arange(len(comp)); comp.to_csv(CACHE + "/comp.csv", index=False); print("compounds", len(comp))
def desc(smi):
    m = Chem.MolFromSmiles(smi); d = Descriptors.CalcMolDescriptors(m); return [d[k] for k in sorted(d)]
names = sorted(Descriptors.CalcMolDescriptors(Chem.MolFromSmiles("CCO")))
if __name__ == "__main__":
    mols = [Chem.MolFromSmiles(s) for s in comp.smiles]
    g = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    C = np.stack([g.GetCountFingerprintAsNumPy(m) for m in mols]).astype(np.float32); np.save(CACHE + "/counts2048.npy", C)
    B = (C > 0).astype(np.float32); np.save(CACHE + "/bits2048.npy", B)
    X = np.log1p(C).astype(np.float64); np.save(CACHE + "/K_lin.npy", X @ X.T)
    inter = B @ B.T; n = B.sum(1); T = inter / (n[:, None] + n[None, :] - inter); np.save(CACHE + "/tanimoto.npy", T.astype(np.float32))
    s = C.astype(np.float64).sum(1); L1 = cdist(C.astype(np.float64), C.astype(np.float64), "cityblock"); K = (s[:, None] + s[None, :] - L1) / (s[:, None] + s[None, :] + L1); np.save(CACHE + "/K_mm.npy", K)
    with Pool(7) as p: D = np.array(p.map(desc, comp.smiles, chunksize=50), dtype=np.float64)
    D[~np.isfinite(D)] = np.nan; med = np.nanmedian(D, 0); med[np.isnan(med)] = 0; D = np.where(np.isnan(D), med, D); D = np.clip(D, -1e6, 1e6)
    np.save(CACHE + "/desc.npy", D.astype(np.float32)); json.dump(names, open(CACHE + "/desc_names.json", "w"))
    # Butina clusters (distance = 1 - Tanimoto, threshold 0.4  <=>  Tanimoto >= 0.6)
    dist = []; 
    for i in range(1, len(comp)): dist.extend((1 - T[i, :i]).tolist())
    cl = Butina.ClusterData(dist, len(comp), 0.4, isDistData=True); lab = np.zeros(len(comp), int)
    for k, c in enumerate(cl):
        for i in c: lab[i] = k
    comp["cluster"] = lab; comp[["cmpd_key", "ci", "cluster"]].to_csv("data/compound_clusters.csv.gz", index=False)
    print("clusters", len(cl), "largest", max(len(c) for c in cl), "singletons", sum(len(c) == 1 for c in cl))
