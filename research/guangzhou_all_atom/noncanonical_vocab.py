#!/usr/bin/env python3
"""noncanonical_vocab.py — representation-extension stub for NATIVE non-canonical generation (Track B / B1).

STATUS: SCAFFOLD (no GPU, no training). This module is the *data-layer* half of B1 — it enumerates the
non-canonical monomers PepGLAD's generator would need to emit, computes the exact vocabulary / atom-slot
deltas against the frozen model's fixed representation, and provides the ideal internal-coordinate geometry
for the added atoms. It deliberately does NOT touch the PyTorch model (that is the retrain half; see
docs/20260926_B1_NATIVE_NONCANONICAL_FEASIBILITY.md). It exists so the extension can be specified, unit-
tested, and reviewed before a single GPU-hour is spent.

WHY THIS SHAPE. PepGLAD represents a peptide as a per-residue block with:
  * a residue-TYPE token S in {20 canonical AAs} (data/format.py: VOCAB.idx2block; decoder head is
    AutoEncoder.seq_linear -> s_remap, hard-wired to len(aas)+1 = 21 classes)
  * a fixed [MAX_ATOM_NUMBER=14, 3] coordinate tensor per residue, with a per-type atom template
    (utils/const.sidechain_atoms + backbone_atoms) and an atom_pos code alphabet
    (data/format.MoleculeVocab.idx2atom_pos).
N-methylation is a BACKBONE modification: it adds one methyl carbon (conventional PDB atom name "CN")
bonded to the backbone amide nitrogen N, and it REMOVES that nitrogen's H-bond-donor H. So natively
emitting an N-Me residue requires, at minimum: (1) a way to represent "this residue is N-methylated"
in the token/feature space, (2) a coordinate slot + ideal geometry for CN, (3) validity constraints.

This stub makes all three concrete and machine-checkable. The three hard collisions it surfaces:
  - ATOM-SLOT SATURATION: TRP already uses all 14 channels (4 bb + 10 sc). N-Me adds CN -> 15 > 14.
    => the model's n_channel / MAX_ATOM_NUMBER must grow (AE retrain), OR N-Me be gated off for TRP.
  - TOKEN-SPACE: the 21-way sequence decoder cannot name an N-Me variant. Either double the token set
    (canonical + N-Me flavor, 20 -> 40) or add an orthogonal 1-bit "N-methylated" head (preferred; see doc).
  - ATOM_POS ALPHABET: "CN" has no Greek-letter position code; a new atom_pos entry is needed.

Everything below is pure Python (+ optional RDKit for the SMILES/validity helpers) and runs on CPU.
"""
from __future__ import annotations

from typing import Dict, List, Optional, Tuple

# -- Re-declared minimal constants (kept in sync with utils/const.py; this module must import cleanly
#    WITHOUT torch, so we do not import data.format / utils.const which pull the model stack). ----------
CANONICAL_AAS: List[Tuple[str, str]] = [
    ('G', 'GLY'), ('A', 'ALA'), ('V', 'VAL'), ('L', 'LEU'),
    ('I', 'ILE'), ('F', 'PHE'), ('W', 'TRP'), ('Y', 'TYR'),
    ('D', 'ASP'), ('H', 'HIS'), ('N', 'ASN'), ('E', 'GLU'),
    ('K', 'LYS'), ('Q', 'GLN'), ('M', 'MET'), ('R', 'ARG'),
    ('S', 'SER'), ('T', 'THR'), ('C', 'CYS'), ('P', 'PRO'),
]
BACKBONE_ATOMS = ['N', 'CA', 'C', 'O']
MAX_ATOM_NUMBER = 14  # PepGLAD's hard per-residue channel cap (data/format.MoleculeVocab.MAX_ATOM_NUMBER)

# Number of sidechain heavy atoms per canonical AA (must match utils/const.sidechain_atoms; TRP=10 is max).
SIDECHAIN_ATOM_COUNT: Dict[str, int] = {
    'G': 0, 'A': 1, 'V': 3, 'L': 4, 'I': 4, 'F': 7, 'W': 10, 'Y': 8, 'D': 4, 'H': 6,
    'N': 4, 'E': 5, 'K': 5, 'Q': 5, 'M': 4, 'R': 7, 'S': 2, 'T': 3, 'C': 2, 'P': 3,
}

# N-methyl group added atom: a methyl carbon on the backbone amide N. PDB convention names it "CN".
NME_ATOM_NAME = 'CN'
NME_ATOM_ELEMENT = 'C'
NME_ATOM_POS_CODE = 'N'  # new atom_pos alphabet entry: methyl on backbone Nitrogen (no Greek position)

# Ideal internal coordinates for CN, in the AA_GEOMETRY z-matrix convention (utils/const.py):
#   parents [N, CA, C]  -- CN is built off the backbone N, using CA and C as the frame.
#   (z-length ~1.45 A for N-CH3; z-angle ~120 deg; z-dihedral so CH3 occupies the removed amide-H site.)
NME_IDEAL_GEOMETRY = {
    'atom': NME_ATOM_NAME,
    'element': NME_ATOM_ELEMENT,
    'parents': ['N', 'CA', 'C'],   # frame atoms present in every residue block
    'z-length': 1.45,              # N-C(methyl) single bond
    'z-angle': 120.0,              # CA-N-CN ~ sp2 amide nitrogen
    'z-dihedral': 180.0,           # trans to CA across the N (occupies the removed amide-H site)
}

# Proline cannot be N-methylated (its backbone N is already a tertiary ring nitrogen -- no amide H to replace).
NME_INELIGIBLE = {'P'}


class NonCanonicalMonomer:
    """One non-canonical building block the extended generator would need to emit.

    Plain class (not a dataclass) so the module loads cleanly via importlib in the torch-free unit tests
    (the repo's test convention; Python 3.14 dataclasses trip on importlib-loaded, unregistered modules).
    """

    def __init__(self, symbol: str, parent_symbol: str, abrv: str, kind: str,
                 added_atoms: Optional[List[str]] = None, removed_donor_h: bool = False,
                 total_atoms: int = 0):
        self.symbol = symbol                # extended short code, e.g. 'nA' for N-methyl-Ala
        self.parent_symbol = parent_symbol  # the canonical AA it derives from, e.g. 'A'
        self.abrv = abrv                    # 3+ letter placeholder (real one from a monomer DB / HELM)
        self.kind = kind                    # 'n_methyl' | 'd_amino' | 'staple' (only 'n_methyl' here)
        self.added_atoms = added_atoms or []  # extra atom names vs the canonical parent
        self.removed_donor_h = removed_donor_h  # whether a backbone NH donor is removed
        self.total_atoms = total_atoms      # backbone + sidechain + added, for the slot check

    @property
    def exceeds_channel_cap(self) -> bool:
        return self.total_atoms > MAX_ATOM_NUMBER


def enumerate_n_methyl_monomers() -> List[NonCanonicalMonomer]:
    """Enumerate the N-methylated variants of the 20 canonical AAs (except Pro).

    Returns one NonCanonicalMonomer per eligible AA, with the exact atom-slot accounting so callers
    (and the retrain planning) can see which variants blow the 14-channel cap.
    """
    monomers: List[NonCanonicalMonomer] = []
    for sym, abrv in CANONICAL_AAS:
        if sym in NME_INELIGIBLE:
            continue
        base_atoms = len(BACKBONE_ATOMS) + SIDECHAIN_ATOM_COUNT[sym]
        total = base_atoms + 1  # + CN
        monomers.append(NonCanonicalMonomer(
            symbol=f'n{sym}',
            parent_symbol=sym,
            abrv=f'M{abrv[:2]}',        # placeholder 3-letter; real one comes from a monomer DB (e.g. HELM)
            kind='n_methyl',
            added_atoms=[NME_ATOM_NAME],
            removed_donor_h=True,        # the permeability lever: one fewer backbone H-bond donor
            total_atoms=total,
        ))
    return monomers


def representation_delta() -> dict:
    """Compute exactly what must change in PepGLAD's representation to natively emit N-Me residues.

    Pure bookkeeping -- the single source of truth for the retrain scope. No model import, no GPU.
    """
    monomers = enumerate_n_methyl_monomers()
    over_cap = [m for m in monomers if m.exceeds_channel_cap]
    return {
        'new_residue_tokens': len(monomers),          # if going the "double the token set" route (20->40)
        'alt_orthogonal_flag_bits': 1,                # if going the preferred "N-methyl 1-bit head" route
        'new_atom_pos_codes': [NME_ATOM_POS_CODE],    # 'N' position code for the methyl carbon
        'new_atom_geometry_entries': 1,               # CN ideal internal coords (one entry, shared)
        'max_atoms_needed': max(m.total_atoms for m in monomers),
        'current_channel_cap': MAX_ATOM_NUMBER,
        'monomers_exceeding_cap': [m.symbol for m in over_cap],   # e.g. ['nW'] (N-Me-Trp = 15 atoms)
        'seq_decoder_classes_current': len(CANONICAL_AAS) + 1,    # 21 (AutoEncoder.seq_linear width)
        'requires_ae_retrain': True,                  # any token/atom-space change => AE (and LDM) retrain
    }


# -- Optional RDKit validity helper (used by the test if RDKit is present; skipped otherwise) ----------
def n_methylated_backbone_smarts() -> str:
    """SMARTS matching an N-methylated backbone amide (same pattern chemistry_permeability_analysis.py uses
    to *score* N-Me post-hoc -- here it validates that a proposed monomer actually carries the modification)."""
    return '[NX3;$([N]C=O)][CH3]'


if __name__ == '__main__':
    import json
    print(json.dumps(representation_delta(), indent=2))
    print()
    for m in enumerate_n_methyl_monomers():
        flag = '  <-- EXCEEDS 14-channel cap (needs AE retrain with larger n_channel)' if m.exceeds_channel_cap else ''
        print(f'{m.symbol:4} <- {m.parent_symbol}  atoms={m.total_atoms:2d}  -1 donor{flag}')
