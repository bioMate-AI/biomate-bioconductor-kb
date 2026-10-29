"""Peptide-macrocycle compound filter (K4 A1): a ring of >= MIN_RING atoms containing >= MIN_AMIDES amide bonds (C and N both ring members)."""
from rdkit import Chem, RDLogger
RDLogger.DisableLog("rdApp.*")
import config
_AMIDE = Chem.MolFromSmarts("[CX3](=O)[NX3]")

def is_peptide_macrocycle(smiles: str, min_ring=config.MIN_RING, min_amides=config.MIN_AMIDES) -> bool:
    try:
        m = Chem.MolFromSmiles(smiles)
    except Exception:
        return False
    if m is None:
        return False
    rings = [set(r) for r in m.GetRingInfo().AtomRings() if len(r) >= min_ring]
    if not rings:
        return False
    am = [(a[0], a[2]) for a in m.GetSubstructMatches(_AMIDE)]
    if len(am) < min_amides:
        return False
    for r in rings:
        if sum(1 for c, n in am if c in r and n in r) >= min_amides:
            return True
    return False

def classify_chunk(rows):
    """rows: list of (id, smiles) -> list of ids that pass."""
    return [i for i, s in rows if is_peptide_macrocycle(s)]
