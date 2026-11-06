"""Label-light audit of the CycPeptMP published split (akiyamalab/cycpeptmp @ e7160fad, data/eval_index): how 'hard' is its test set?
Descriptive only (no model fitting): scaffold overlap, nearest-neighbour ECFP4 Tanimoto to train, source composition, label spread
(test std matters because R2 scales with test variance), and fraction of censored/sentinel (-10) labels."""
import numpy as np, pandas as pd, json
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import rdFingerprintGenerator
from rdkit.Chem.Scaffolds import MurckoScaffold
from common import *
RDLogger.DisableLog("rdApp.*")
R = os.path.join(SCRATCH, "../cpmp_repo")
p = pd.read_csv(f"{R}/desc/peptide_used.csv")
E_ = lambda n: np.load(f"{R}/data/eval_index/{n}.npy", allow_pickle=True)
te, tr, va = set(E_("Test_ID")), set(E_("Train_ID_cv0")), set(E_("Valid_ID_cv0"))
gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
mols = [Chem.MolFromSmiles(s) for s in p.SMILES]
fps = [gen.GetFingerprint(m) for m in mols]
def gscaf(m):
    return Chem.MolToSmiles(MurckoScaffold.MakeScaffoldGeneric(MurckoScaffold.GetScaffoldForMol(m)))
p["scaf"] = [gscaf(m) for m in mols]
def audit(test_ids, train_ids, name):
    ti = np.where(p.ID.isin(test_ids))[0]; ri = np.where(p.ID.isin(train_ids))[0]
    trfp = [fps[i] for i in ri]; scs = set(p.scaf.values[ri])
    nn = [max(DataStructs.BulkTanimotoSimilarity(fps[i], trfp)) for i in ti]
    y_te, y_tr = p.y.values[ti], p.y.values[ri]
    return {"split": name, "n_test": len(ti), "n_train": len(ri), "frac_test_scaffold_in_train": float(np.mean([p.scaf.values[i] in scs for i in ti])),
            "mean_nn_tanimoto": float(np.mean(nn)), "median_nn_tanimoto": float(np.median(nn)), "frac_nn_ge_0.8": float(np.mean(np.array(nn) >= .8)),
            "test_y_std": float(y_te.std()), "train_y_std": float(y_tr.std()), "test_frac_y_le_-10": float((y_te <= -10).mean()),
            "test_source_top": p.iloc[ti].Set.value_counts().head(4).to_dict()}
out = [audit(te, tr, "CycPeptMP published test (cv0 train)")]
rng = np.random.default_rng(0); ids = p.ID.values; rid = rng.permutation(ids)
out.append(audit(set(rid[:344]), set(rid[344 + 344:]), "random 344 from same pool (reference)"))
# our generic-scaffold-grouped holdout of equal size from same pool
sc = p.scaf.values; ug = np.unique(sc); rng.shuffle(ug); chosen = []; n = 0
for g in ug:
    chosen.append(g); n += (sc == g).sum()
    if n >= 344: break
mask = np.isin(sc, chosen)
out.append(audit(set(ids[mask]), set(ids[~mask]), "scaffold-grouped holdout (~344) same pool"))
out.append({"pool": {"n": len(p), "y_std": float(p.y.std()), "frac_y_le_-10": float((p.y <= -10).mean()), "n_pampa": int(p.PAMPA.notna().sum())}})
json.dump(out, open(os.path.join(HERE, "results/published_split_audit.json"), "w"), indent=1); print(json.dumps(out, indent=1))
