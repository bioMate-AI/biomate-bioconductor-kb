"""Label-free featurisation, cached to scratch npz."""
import numpy as np, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, rdFingerprintGenerator
from common import *
RDLogger.DisableLog("rdApp.*")
CACHE = os.path.join(SCRATCH, "feats.npz")

def build():
    c = pd.read_csv(CLEAN)
    mols = [Chem.MolFromSmiles(s) for s in c.can]
    gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    ecfp = np.array([gen.GetCountFingerprintAsNumPy(m) for m in mols], np.float32)
    names = [n for n, _ in Descriptors.descList]
    desc = np.array([[f(m) for _, f in Descriptors.descList] for m in mols], np.float64)
    desc = np.nan_to_num(np.clip(desc, -1e6, 1e6)).astype(np.float32)
    vocab = sorted(set(x for s in c.monomers for x in s.split("|"))); vi = {m: i for i, m in enumerate(vocab)}
    bag = np.zeros((len(c), len(vocab)), np.float32)
    for r, s in enumerate(c.monomers):
        for x in s.split("|"): bag[r, vi[x]] += 1
    assay = np.stack([(c.assay == a).values for a in ASSAY_ORDER], 1).astype(np.float32)
    np.savez_compressed(CACHE, ecfp=ecfp, desc=desc, bag=bag, assay=assay, desc_names=np.array(names), vocab=np.array(vocab))

def get():
    if not os.path.exists(CACHE): build()
    z = np.load(CACHE, allow_pickle=True); return {k: z[k] for k in z.files}

if __name__ == "__main__":
    build(); z = get(); print({k: z[k].shape for k in z})
