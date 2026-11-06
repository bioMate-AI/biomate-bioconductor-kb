#!/usr/bin/env python3
"""Shared SMILES featurization for the real-data binding model (Track A1).

Features = Morgan/ECFP4 count-capped bit fingerprint (2048) + a compact block of
interpretable RDKit physchem descriptors. Ligand-only by design: the honest
novel-target test (hold out PD-L1/avb6 entirely) depends on the model having NO
target channel for those unseen proteins, so chemical similarity is all it has.

Target transform: pAffinity = 9 - log10(affinity_nM)  (pKd-like, higher = stronger).
"""
import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, rdMolDescriptors, Crippen, Lipinski
from rdkit.Chem import rdFingerprintGenerator

RDLogger.DisableLog("rdApp.*")

_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)

# compact, interpretable descriptor block (relevant to peptide developability + binding)
DESC_NAMES = [
    "MolWt", "MolLogP", "TPSA", "NumHDonors", "NumHAcceptors",
    "NumRotatableBonds", "NumRings", "NumAromaticRings", "FractionCSP3",
    "NumAliphaticRings", "HeavyAtomCount", "NumHeteroatoms", "NHOHCount",
    "NOCount", "RingCount", "NumSaturatedRings",
]


def _desc(mol):
    return np.array([
        Descriptors.MolWt(mol),
        Crippen.MolLogP(mol),
        rdMolDescriptors.CalcTPSA(mol),
        Lipinski.NumHDonors(mol),
        Lipinski.NumHAcceptors(mol),
        Descriptors.NumRotatableBonds(mol),
        rdMolDescriptors.CalcNumRings(mol),
        rdMolDescriptors.CalcNumAromaticRings(mol),
        rdMolDescriptors.CalcFractionCSP3(mol),
        rdMolDescriptors.CalcNumAliphaticRings(mol),
        mol.GetNumHeavyAtoms(),
        rdMolDescriptors.CalcNumHeteroatoms(mol),
        Lipinski.NHOHCount(mol),
        Lipinski.NOCount(mol),
        rdMolDescriptors.CalcNumRings(mol),
        rdMolDescriptors.CalcNumSaturatedRings(mol),
    ], dtype=np.float32)


def featurize_smiles(smiles):
    """Return (fp2048 uint8, desc16 float32) or None if SMILES unparseable."""
    m = Chem.MolFromSmiles(smiles) if isinstance(smiles, str) else None
    if m is None:
        return None
    fp = np.asarray(_FP.GetFingerprint(m), dtype=np.uint8)
    try:
        d = _desc(m)
    except Exception:
        return None
    if not np.all(np.isfinite(d)):
        return None
    return fp, d


def seq_to_smiles(seq):
    """Head-to-tail cyclic SMILES for a 1-letter sequence (for scoring peptide pools)."""
    m = Chem.MolFromSequence(seq)
    if m is None:
        return None
    return Chem.MolToSmiles(m)


def nm_to_paffinity(nm):
    return 9.0 - np.log10(nm)


def paffinity_to_nm(p):
    return 10.0 ** (9.0 - p)
