"""Pilot 4 shared data layer (new-target few-shot learning curve, exact potencies). All label-free except the declared eligibility rule (n_exact >= 30, SD(pActivity) >= 0.5)."""
import os, hashlib, numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__))
RR = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery/data")
NB = 2048


def split_half(family):                      # pre-registered: sha256(family) mod 2 ; 0 = dev, 1 = test
    return int(hashlib.sha256(str(family).encode()).hexdigest(), 16) % 2


def load():
    d = pd.read_csv(f"{RR}/pair_labels.csv.gz"); t = pd.read_csv(f"{RR}/targets_v2.csv"); c = pd.read_csv(f"{RR}/compounds.csv.gz")
    ex = d[d.relations.astype(str) == "="].copy(); ex["p"] = -np.log10(ex.value_nM.astype(float) * 1e-9)
    ex = ex.merge(t[["target_key", "family"]], on="target_key", how="left")
    g = ex.groupby("target_key").p.agg(n="size", sd="std")
    elig = g[(g.n >= 30) & (g.sd >= 0.5)].index
    fam = ex.drop_duplicates("target_key").set_index("target_key").family
    return ex, c, elig, fam


def folds(elig, fam, K=6):
    """greedy balance of eligible families into K groups by number of eligible targets (largest family first, into the lightest group); all other families go to fold -1 (training only)."""
    cnt = fam.loc[elig].value_counts().sort_values(ascending=False)
    load = [0] * K; out = {}
    for f, n in cnt.items():
        k = int(np.argmin(load)); out[f] = k; load[k] += int(n)
    return out, load


def fingerprints(smiles):
    from rdkit import Chem, DataStructs
    from rdkit.Chem import rdFingerprintGenerator as G
    gen = G.GetMorganGenerator(radius=2, fpSize=NB, includeChirality=True)
    X = np.zeros((len(smiles), NB), np.float32)
    for i, s in enumerate(smiles):
        m = Chem.MolFromSmiles(s)
        if m is None: continue
        X[i, list(gen.GetFingerprint(m).GetOnBits())] = 1.0
    return X


def tanimoto(A, B):
    inter = A @ B.T; na = A.sum(1)[:, None]; nb = B.sum(1)[None, :]
    return inter / np.maximum(na + nb - inter, 1e-9)
