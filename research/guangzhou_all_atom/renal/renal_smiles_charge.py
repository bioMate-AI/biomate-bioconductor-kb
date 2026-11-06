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
# chelator -> net charge of the METAL COMPLEX at pH 7.4. The metal-free SMILES counts the WHOLE chelator
# (ring amines AND carboxylate arms) as ionizable; in vivo they all coordinate the metal, so we EXCLUDE
# every chelator atom from group matching (macrocycle ring + acetate arms, atom-claimed) and add this
# single complex charge instead.
CHELATOR_COMPLEX_CHARGE = {
    "DOTA": -1.0, "DOTAGA": -2.0, "NOTA": 0.0, "NODAGA": -1.0, "DTPA": -2.0, "CHX-A-DTPA": -2.0,
    "macropa": -1.0, "TRAP": -2.0, "DFO": 0.0, None: 0.0, "": 0.0,
}
# azamacrocycle cores: DOTA/DOTAGA/NODAGA share cyclen (12-membered tetraaza); NOTA/NODAGA = TACN (9-membered triaza)
_MACROCYCLE_SMARTS = ["[#7]1[#6][#6][#7][#6][#6][#7][#6][#6][#7][#6][#6]1",   # cyclen (DOTA)
                      "[#7]1[#6][#6][#7][#6][#6][#7][#6][#6]1"]                # TACN (NOTA)
_ARM_SMARTS = "[#7;R][CH2][CX3](=O)[OX2H1,OX1-]"   # ring-N-CH2-COOH acetate arm
# FIX 2 (reviewer C): acyclic chelators (DTPA, CHX-A''-DTPA, DFO, macropa, TRAP, HBED, DTPA-derivatives)
# have NO macrocycle ring, so the macrocycle SMARTS above never fired and their donor arms were double-
# counted — once as free ionizable groups AND again via the added complex charge. For acyclic chelators we
# claim their open-chain donor atoms too (open-chain N-acetate arms, hydroxamates, phosphonate/phosphinate
# arms), so ONLY the single metal-complex charge counts, matching the macrocyclic treatment.
_ACYCLIC_CHELATORS = {"DTPA", "CHX-A-DTPA", "CHX-A''-DTPA", "DFO", "macropa", "TRAP", "HBED"}
_ACYCLIC_ARM_SMARTS = [
    "[#7;!R][CH2][CX3](=O)[OX2H1,OX1-]",                 # open-chain N-CH2-COOH arm (DTPA / CHX-A''-DTPA)
    "[CX3](=O)[NX3][OX2H1,OX1-]",                        # hydroxamate donor (DFO)
    "[#6][PX4](=O)([OX2H1,OX1-])[#6]",                   # phosphinate arm (TRAP)
    "[#6][PX4](=O)([OX2H1,OX1-])[OX2H1,OX1-]",           # phosphonate arm
]
# (name, SMARTS, pKa, is_acid). NB: phosphonate is DIPROTIC and handled specially below (FIX 6): it has
# pKa1 ~ 1-2 (always fully ionized, contributes -1) AND pKa2 ~ 6-7 (partially ionized at pH 7.4). A single
# pKa 7.2 under-counted it by ~ -1. _PHOSPHONATE_PKA holds (pKa1, pKa2); the pKa field here is unused for it.
_PHOSPHONATE_PKA = (1.5, 6.5)
_GROUPS = [
    ("carboxylic_acid", "[CX3](=O)[OX2H1,OX1-]", 4.2, True),
    ("sulfonic_acid",   "[SX4](=O)(=O)[OX2H1,OX1-]", -1.0, True),
    ("phosphonate",     "[PX4](=O)([OX2H1,OX1-])[OX2H1,OX1-]", 6.5, True),   # diprotic; see FIX 6 below
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


def smiles_net_charge(smiles: str, chelator: Optional[str] = None) -> Optional[dict]:
    """In-vivo net charge of the metal complex at pH 7.4 from a METAL-FREE ligand SMILES.

    The SMILES counts the chelator's arms as free carboxylic acids (~ -1 each), but in vivo they
    coordinate the metal. So: in-vivo = raw_HH_charge + (n_chelator_COOH) + complex_charge — we add back
    the n carboxylates the SMILES over-counted as -1, then add the true metal-complex charge. Returns
    {net_charge_pH74 (raw ligand), net_charge_with_chelate (in-vivo complex), groups}."""
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
    # 1) claim EVERY chelator atom (macrocycle ring + acetate arms) so none is counted as ionizable —
    #    the metal coordinates them in vivo; their contribution is the single complex charge added below.
    chel_claimed = False
    for sma in _MACROCYCLE_SMARTS:
        patt = Chem.MolFromSmarts(sma)
        for match in (mol.GetSubstructMatches(patt, uniquify=True) if patt else []):
            claimed |= set(match); chel_claimed = True
    if chel_claimed:
        arm = Chem.MolFromSmarts(_ARM_SMARTS)
        for match in (mol.GetSubstructMatches(arm, uniquify=True) if arm else []):
            claimed |= set(match)
    # FIX 2: acyclic chelator -> no ring to match, so claim its open-chain donor arms by name.
    if (chelator in _ACYCLIC_CHELATORS) and not chel_claimed:
        for sma in _ACYCLIC_ARM_SMARTS:
            patt = Chem.MolFromSmarts(sma)
            for match in (mol.GetSubstructMatches(patt, uniquify=True) if patt else []):
                claimed |= set(match); chel_claimed = True
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
            if name == "phosphonate":                 # FIX 6: diprotic — pKa1 (always -1) + pKa2 (HH)
                pk1, pk2 = _PHOSPHONATE_PKA
                q += n * (_hh(pk1, True) + _hh(pk2, True))
            else:
                q += n * _hh(pKa, is_acid)
    complex_q = CHELATOR_COMPLEX_CHARGE.get(chelator, 0.0)
    # q already EXCLUDES all chelator atoms (claimed above); add the metal-complex charge once.
    invivo = q + (complex_q if chel_claimed or chelator in CHELATOR_COMPLEX_CHARGE else 0.0)
    return {"net_charge_pH74": round(q, 3), "net_charge_with_chelate": round(invivo, 3),
            "groups": counts, "chelator_excluded": chel_claimed, "complex_charge": complex_q}


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
