"""The constraint set C, copied EXACTLY from pilot 3 (generation_pilot/gen_pilot.py::satisfies, docs/20261031_GENERATION_PILOT3_PREREG.md section 3).
test_rules.py asserts equality with gen_pilot.satisfies on a large string set whenever gen_pilot is importable."""
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors
from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams

NME = Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])")
_pp = FilterCatalogParams(); _pp.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS); PAINS = FilterCatalog(_pp)

RING_MIN = 12
NME_LO, NME_HI = 2, 6
MW_LO, MW_HI = 600.0, 1400.0
TPSA_HI = 300.0


def mol_stats(m):
    rr = [len(r) for r in m.GetRingInfo().AtomRings()]
    return (max(rr) if rr else 0), len(m.GetSubstructMatches(NME))


def satisfies(m):
    """m: sanitised Mol or None."""
    if m is None or len(Chem.GetMolFrags(m)) != 1: return False
    mr, nme = mol_stats(m)
    if mr < RING_MIN or not (NME_LO <= nme <= NME_HI): return False
    mw = Descriptors.MolWt(m)
    if not (MW_LO <= mw <= MW_HI): return False
    if rdMolDescriptors.CalcTPSA(m) > TPSA_HI: return False
    return not PAINS.HasMatch(m)


def satisfies_smiles(s):
    m = Chem.MolFromSmiles(s) if s else None
    return satisfies(m)
