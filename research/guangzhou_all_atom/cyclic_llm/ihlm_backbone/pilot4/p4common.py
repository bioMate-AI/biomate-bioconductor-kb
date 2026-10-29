"""Pilot 4 shared data layer (new-target few-shot learning curve, exact potencies). All label-free except the declared eligibility rule (n_exact >= 30, SD(pActivity) >= 0.5)."""
import os, json, hashlib, numpy as np, pandas as pd
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


FOLD_MAP = os.path.join(HERE, "fold_map.json"); FOLD_MAP_SHA256 = open(os.path.join(HERE, "fold_map.sha256")).read().split()[0] if os.path.exists(os.path.join(HERE, "fold_map.sha256")) else None


def folds(elig, fam, K=6):
    """Family -> fold map ACTUALLY USED by pilot 4 (the six fold pickles were trained under it), read from the committed `fold_map.json` (sha256 in `fold_map.sha256`).
    Errata 2: the original implementation (value_counts().sort_values(ascending=False), greedy argmin) had an UNSTABLE tie order among the 33 single-target families, so it gave a platform-dependent assignment (32 of 47 families differ between the training machine and a local rebuild). The map was recovered from the pickles (see docs/20261031_NEWTARGET_FEWSHOT_PILOT4_PREREG.md §13) and frozen; `folds_rebuild` below is a deterministic alternative and is NOT the map used."""
    raw = open(FOLD_MAP, "rb").read()
    if FOLD_MAP_SHA256 is not None: assert hashlib.sha256(raw).hexdigest() == FOLD_MAP_SHA256, "fold_map.json does not match fold_map.sha256"
    fm = json.loads(raw)["fold_map"]; fams = set(fam.loc[list(elig)].unique())
    assert fams == set(fm), f"fold map families differ from eligible families ({len(fams ^ set(fm))} mismatches)"
    cnt = fam.loc[list(elig)].value_counts(); load = [0] * K
    for f_, k in fm.items(): load[k] += int(cnt[f_])
    return {f_: int(k) for f_, k in fm.items()}, load


def folds_rebuild(elig, fam, K=6):
    """Deterministic greedy balance (count descending, family id ascending as explicit tiebreak, stable). A valid balanced partition, but a DIFFERENT assignment from the one used in pilot 4."""
    cnt = fam.loc[list(elig)].value_counts(); order = sorted(cnt.index, key=lambda k: (-int(cnt[k]), str(k))); load = [0] * K; out = {}
    for f_ in order:
        k = int(np.argmin(load)); out[f_] = k; load[k] += int(cnt[f_])
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
