"""Verifier ladder for the all-atom hybrid-LLM paper, stages 0-1 (see docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md section 4 and amendment A1).

Objective families used in the pilot (two of the three planned families; the structure family is stage 3):
  F1  physchem / rule objective      TRAIN: fixed textbook potential (no fitting, lab-independent)
                                     STOP : permeability model fitted on source group S (RF on descriptors + fingerprint bits)
                                     HELD-OUT: ETKDG conformer-ensemble minimum polar SASA (physics, top-k only)
  F2  permeability-model objective   TRAIN: HistGradientBoosting fitted on source group A (within-source-z PAMPA labels)
                                     STOP : RF fitted on source group S
                                     HELD-OUT: Tanimoto-kernel ridge ('GP-mean') fitted on source group B
Source groups A / S / B are a deterministic size-balanced round-robin over sources with >= 20 labelled peptides (the
assignment depends only on source sizes, never on any score). Every verifier returns a PERCENTILE in [0,1] against the
reference library (all CycPeptMPDB peptides, post-source-fix annotation), so the normalised AUC-top-k of different families
is comparable. All heavy functions are for EC2 spot / Spark; nothing here is run on the laptop."""
from __future__ import annotations

import hashlib
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from pmo_harness import Verifier  # noqa: E402

ANN_DEFAULT = os.environ.get("ANN_CSV", os.path.join(HERE, "..", "..", "stratification", "data", "annotations.csv.gz"))
ASSAY = "pampa"
MIN_SRC = 20


def _rd():
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*")
    return Chem


def canon(s):
    Chem = _rd()
    m = Chem.MolFromSmiles(s) if isinstance(s, str) and s else None
    return Chem.MolToSmiles(m, isomericSmiles=True) if m is not None else None


# ---------------------------------------------------------------------------------------------- features
_GEN = {}


def _morgan(nbits, counts):
    from rdkit.Chem import rdFingerprintGenerator
    key = (nbits, counts)
    if key not in _GEN:
        _GEN[key] = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=nbits, includeChirality=True)
    return _GEN[key]


def fp_bits(m, nbits=2048):
    return _morgan(nbits, False).GetFingerprintAsNumPy(m).astype(np.uint8)


def fp_counts(m, nbits=1024):
    return _morgan(nbits, True).GetCountFingerprintAsNumPy(m).astype(np.float32)


_NME = None


def desc7(m):
    from rdkit.Chem import Crippen, Descriptors, rdMolDescriptors
    from rdkit import Chem
    global _NME
    if _NME is None:
        _NME = Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])")
    return np.array([rdMolDescriptors.CalcTPSA(m), rdMolDescriptors.CalcNumHBD(m), rdMolDescriptors.CalcNumHBA(m),
                     Crippen.MolLogP(m), Descriptors.MolWt(m), rdMolDescriptors.CalcNumRotatableBonds(m),
                     len(m.GetSubstructMatches(_NME))], np.float32)


def features(smiles_list, kind):
    """kind: 'A' (counts 1024 + desc7) | 'S' (bits 512 + desc7) | 'bits2048'."""
    Chem = _rd()
    out = []
    for s in smiles_list:
        m = Chem.MolFromSmiles(s)
        if kind == "A":
            out.append(np.concatenate([fp_counts(m, 1024), desc7(m)]))
        elif kind == "S":
            out.append(np.concatenate([fp_bits(m, 512).astype(np.float32), desc7(m)]))
        elif kind == "bits2048":
            out.append(fp_bits(m, 2048))
        else:
            raise ValueError(kind)
    return np.asarray(out)


# ---------------------------------------------------------------------------------------------- data and source groups
def load_labelled(ann_path=ANN_DEFAULT, assay=ASSAY):
    import pandas as pd
    ann = pd.read_csv(ann_path, index_col=0)
    ann["cid"] = ann.index
    d = ann[ann[assay].notna() & ann["SMILES"].notna()][["Source", "SMILES", assay, "cid"]].copy()
    d["smiles"] = [canon(s) for s in d["SMILES"]]
    d = d[d["smiles"].notna()].drop_duplicates(["smiles", "Source"])
    d["y_raw"] = d[assay].astype(float)
    g = d.groupby("Source")["y_raw"]
    n, mu, sd = g.transform("size"), g.transform("mean"), g.transform("std")
    d = d[(n >= MIN_SRC) & (sd > 0)].copy()
    d["z"] = ((d["y_raw"] - mu) / sd)[d.index]
    return d.reset_index(drop=True)


LARGEST_LABS = ("2020_Townsend", "2021_Kelly")


def source_groups(d, version="v2"):
    """version 'v1' (amendment A1): size-balanced round-robin [0,1,2,2,1,0] over sources sorted by (-n, name).
    version 'v2' (amendment A2): the two largest labs (2020_Townsend, 2021_Kelly) are ALWAYS train (group 0) and never used for the stop or
    held-out verifiers; the remaining sources (>= MIN_SRC labelled peptides) are dealt to S (1) and B (2) by a snake draft on size
    (pattern S,B,B,S repeated, sources sorted by (-n, name)). Sources with < MIN_SRC peptides are excluded (within-source z is unreliable below 20).
    Uses source sizes only, never a score. Returns dict source -> group index (0=A train, 1=S stop, 2=B held-out)."""
    sizes = d.groupby("Source").size()
    ranked = sorted(sizes.items(), key=lambda kv: (-int(kv[1]), str(kv[0])))
    if version == "v1":
        order = [0, 1, 2, 2, 1, 0]
        return {src: order[i % len(order)] for i, (src, _) in enumerate(ranked)}
    if version != "v2":
        raise ValueError(version)
    groups, rest = {}, []
    for src, n in ranked:
        if src in LARGEST_LABS:
            groups[src] = 0
        else:
            rest.append(src)
    pat = [1, 2, 2, 1]
    for i, src in enumerate(rest):
        groups[src] = pat[i % 4]
    ns = {g: sum(1 for v in groups.values() if v == g) for g in (1, 2)}
    if min(ns.values()) < 5:
        raise ValueError(f"groups v2: S/B need >= 5 sources each, got {ns}")
    return groups


def group_summary(d, groups):
    d = d.assign(g=d["Source"].map(groups))
    return {g: dict(n_sources=int(d[d.g == g]["Source"].nunique()), n_peptides=int((d.g == g).sum()),
                    sources=sorted(d[d.g == g]["Source"].unique().tolist())) for g in (0, 1, 2)}


# ---------------------------------------------------------------------------------------------- models
class TanimotoKRR:
    """Kernel ridge with the Tanimoto kernel on 2048-bit chirality-aware Morgan bits (GP posterior mean, fixed alpha)."""

    def __init__(self, alpha=1.0):
        self.alpha = alpha

    @staticmethod
    def kern(X, Y):
        X, Y = X.astype(np.float32), Y.astype(np.float32)
        dot = X @ Y.T
        return dot / (X.sum(1)[:, None] + Y.sum(1)[None, :] - dot + 1e-9)

    def fit(self, X, y):
        self.X, self.mu = X, float(np.mean(y))
        K = self.kern(X, X)
        self.coef = np.linalg.solve(K + self.alpha * np.eye(len(X), dtype=np.float32), (np.asarray(y) - self.mu).astype(np.float32))
        return self

    def predict(self, X):
        return self.kern(X, self.X) @ self.coef + self.mu


def _pct(ref_sorted):
    return lambda raw: float(np.searchsorted(ref_sorted, raw, side="right")) / len(ref_sorted)


def build_ladder(ann_path=ANN_DEFAULT, seed=0, ref_cap=3000, version="v2"):
    """Fits every verifier (EC2/Spark only). Returns dict with verifiers per family, groups, and reference sets."""
    from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor
    d = load_labelled(ann_path)
    groups = source_groups(d, version)
    d["g"] = d["Source"].map(groups)
    srcs = {g: frozenset(d[d.g == g]["Source"].unique()) for g in (0, 1, 2)}
    XA = features(d[d.g == 0]["smiles"].tolist(), "A"); yA = d[d.g == 0]["z"].values
    XS = features(d[d.g == 1]["smiles"].tolist(), "S"); yS = d[d.g == 1]["z"].values
    XB = features(d[d.g == 2]["smiles"].tolist(), "bits2048"); yB = d[d.g == 2]["z"].values
    mA = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.06, random_state=seed).fit(XA, yA)
    mS = RandomForestRegressor(n_estimators=300, min_samples_leaf=2, n_jobs=-1, random_state=seed).fit(XS, yS)
    mB = TanimotoKRR(alpha=1.0).fit(XB, yB)
    rng = np.random.default_rng(seed)
    uniq = sorted(set(d["smiles"]))
    ref = [uniq[i] for i in rng.choice(len(uniq), min(ref_cap, len(uniq)), replace=False)]
    Chem = _rd()

    def raw_t1(s):  # textbook potential, no fitting
        m = Chem.MolFromSmiles(s)
        v = desc7(m)
        tpsa, hbd, _, logp, _, rot, _ = [float(x) for x in v]
        return -0.01 * tpsa - 0.15 * hbd + 0.20 * logp - 0.10 * max(0.0, rot - 10.0)

    def raw_perm(model, kind):
        return lambda s: float(model.predict(features([s], kind))[0])

    raws = {"phys_potential": raw_t1, "perm_A_hgb": raw_perm(mA, "A"), "perm_S_rf": raw_perm(mS, "S"), "perm_B_krr": raw_perm(mB, "bits2048")}
    refsort = {k: np.sort(np.array([f(s) for s in ref], float)) for k, f in raws.items()}
    pct = {k: _pct(refsort[k]) for k in raws}
    mk = lambda name, role, trained_on, cost: Verifier(name=name, fn=(lambda s, _k=name: pct[_k](raws[_k](s))), role=role, cost=cost, trained_on=frozenset(trained_on))
    ladder = {
        "F1": dict(train=mk("phys_potential", "train", [], 0.005), stop=mk("perm_S_rf", "stop", srcs[1], 0.05)),
        "F2": dict(train=mk("perm_A_hgb", "train", srcs[0], 0.01), stop=mk("perm_S_rf_f2", "stop", srcs[1], 0.05), heldout=mk("perm_B_krr", "heldout", srcs[2], 0.05)),
    }
    # the F2 stop verifier is the same fitted RF under a different name so that names stay unique across families
    pct["perm_S_rf_f2"], raws["perm_S_rf_f2"] = pct["perm_S_rf"], raws["perm_S_rf"]
    return dict(d=d, groups=groups, group_summary=group_summary(d, groups), ladder=ladder, ref=ref, srcs=srcs, pct=pct, raws=raws)


# ---------------------------------------------------------------------------------------------- physics held-out (F1)
def polar_sasa_min(smiles, n_conf=4, seed=7, max_iters=200):
    """Minimum over ETKDG+MMFF conformers of the polar (N,O and their H) solvent-accessible surface area; None on failure."""
    from rdkit import Chem
    from rdkit.Chem import AllChem, rdFreeSASA
    m = Chem.AddHs(Chem.MolFromSmiles(smiles))
    ps = AllChem.ETKDGv3()
    ps.randomSeed = seed
    ps.useMacrocycleTorsions = True
    ps.useRandomCoords = True
    ps.maxIterations = 200
    cids = list(AllChem.EmbedMultipleConfs(m, n_conf, ps))
    if not cids:
        return None
    try:
        AllChem.MMFFOptimizeMoleculeConfs(m, maxIters=max_iters)
    except Exception:
        pass
    radii = rdFreeSASA.classifyAtoms(m)
    polar = [a.GetIdx() for a in m.GetAtoms() if a.GetAtomicNum() in (7, 8) or (a.GetAtomicNum() == 1 and any(n.GetAtomicNum() in (7, 8) for n in a.GetNeighbors()))]
    best = None
    for cid in cids:
        rdFreeSASA.CalcSASA(m, radii, confIdx=cid)
        v = sum(float(m.GetAtomWithIdx(i).GetProp("SASA")) for i in polar)
        best = v if best is None else min(best, v)
    return best


def physics_heldout_verifier(ref_smiles, n_ref=120, seed=0):
    """F1 held-out verifier: percentile of -min polar SASA against n_ref reference peptides (computed once; seconds each)."""
    rng = np.random.default_rng(seed)
    pick = [ref_smiles[i] for i in rng.choice(len(ref_smiles), min(n_ref, len(ref_smiles)), replace=False)]
    vals = []
    for s in pick:
        try:
            v = polar_sasa_min(s)
        except Exception:
            v = None
        if v is not None:
            vals.append(-v)
    refsort = np.sort(np.array(vals, float))
    pct = _pct(refsort)

    def fn(s):
        try:
            v = polar_sasa_min(s)
        except Exception:
            v = None
        return 0.0 if v is None else pct(-v)

    return Verifier(name="etkdg_min_polar_sasa", fn=fn, role="heldout", cost=10.0, trained_on=frozenset()), len(vals)
