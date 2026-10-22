"""renal_smiles_charge.py — net charge at pH 7.4 from SMILES (for small-molecule radioligands).

Peptide net charge comes from renal_features (Henderson-Hasselbalch on the one-letter sequence). Small-
molecule radioligands (PSMA urea, FAPI quinoline) have no peptide sequence, so their net charge is
computed here from SMILES, by the SAME HH principle applied to matched ionizable groups.

Method (documented approximation, NOT a full pKa solver — dimorphite_dl is not installed):
  1. neutralize explicit charges so we don't double-count;
  2. match ionizable groups by SMARTS, each with a representative pKa;
  3. sum HH fractional charges at pH 7.4: base += 1/(1+10^(pH-pKa)); acid -= 1/(1+10^(pKa-pH)).
This is exact for the dominant groups (carboxylate, aliphatic amine, guanidine, imidazole, sulfonate,
tetrazole, phosphonate) and is clearly labelled as an approximation. Caveat: small molecules largely
clear by tubular transporters (OAT/OCT), not only megalin reabsorption, so charge is a weaker predictor
for them than for filtered peptides — the surrogate stratifies peptide vs small-molecule accordingly.
"""
from __future__ import annotations
from typing import Optional

PH = 7.4
# (name, SMARTS, pKa, is_acid)
_GROUPS = [
    ("carboxylic_acid", "[CX3](=O)[OX2H1,OX1-]", 4.2, True),
    ("sulfonic_acid",   "[SX4](=O)(=O)[OX2H1,OX1-]", -1.0, True),
    ("phosphonate",     "[PX4](=O)([OX2H1,OX1-])[OX2H1,OX1-]", 7.2, True),   # 2nd pKa ~7; 1st always ionized
    ("tetrazole",       "c1nnn[nH1]1", 4.9, True),
    ("phenol",          "[OX2H1][cX3]", 10.0, True),
    ("aliphatic_amine", "[NX3;H2,H1,H0;!$(NC=[O,S,N]);!$(N=*);!$([N+]);!$(Nc);!$(N[CX3](=[NX2,NX3]))]", 10.5, False),
    ("guanidine",       "[NX3][CX3](=[NX2,NX3])[NX3]", 12.5, False),
    ("amidine",         "[NX3][CX3]=[NX2]", 11.5, False),
    ("imidazole",       "c1cnc[nH1]1", 6.0, False),
    ("aniline",         "[NX3;H2,H1;$(Nc)]", 4.6, False),
]


def _hh(pKa: float, is_acid: bool) -> float:
    return -1.0 / (1.0 + 10 ** (pKa - PH)) if is_acid else 1.0 / (1.0 + 10 ** (PH - pKa))


def smiles_net_charge(smiles: str, chelator_charge: float = 0.0) -> Optional[dict]:
    """Return {net_charge_pH74, net_charge_with_chelate, groups:{...}} or None if SMILES unparseable."""
    try:
        from rdkit import Chem
    except Exception:
        return None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    # neutralize explicit charges (work from the neutral form so SMARTS pKa model isn't double-counted)
    for atom in mol.GetAtoms():
        if atom.GetFormalCharge() != 0:
            atom.SetFormalCharge(0)
            atom.SetNumExplicitHs(max(atom.GetNumExplicitHs(), 0))
    try:
        Chem.SanitizeMol(mol)
    except Exception:
        pass
    q, counts, claimed = 0.0, {}, set()
    for name, sma, pKa, is_acid in _GROUPS:      # _GROUPS ordered specific-first (guanidine before amidine)
        patt = Chem.MolFromSmarts(sma)
        if patt is None:
            continue
        n = 0
        for match in mol.GetSubstructMatches(patt, uniquify=True):
            heavy = set(match)
            if heavy & claimed:                   # an atom already claimed by a more-specific group -> skip
                continue
            claimed |= heavy
            n += 1
        if n:
            counts[name] = n
            q += n * _hh(pKa, is_acid)
    return {"net_charge_pH74": round(q, 3), "net_charge_with_chelate": round(q + chelator_charge, 3),
            "groups": counts}


if __name__ == "__main__":
    tests = [
        ("CC(=O)O", "acetic acid -> ~-1"),
        ("CCN", "ethylamine -> ~+1"),
        ("NC(=N)N", "guanidine -> ~+1"),
        ("OC(=O)CCC(N)C(=O)O", "Glu-like diacid+amine -> ~-1"),
        ("c1cc(ccc1)S(=O)(=O)O", "benzenesulfonic -> -1"),
    ]
    for smi, note in tests:
        r = smiles_net_charge(smi)
        print(f"  {smi:28s} net={r['net_charge_pH74']:+.2f}  groups={r['groups']}  ({note})")
    print("\nSMILES net charge @ pH7.4 (HH on matched ionizable groups). Approximation; dimorphite_dl absent.")
