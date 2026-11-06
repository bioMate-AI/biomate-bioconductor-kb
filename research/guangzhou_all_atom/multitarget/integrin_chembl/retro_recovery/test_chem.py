"""Tests for chem.py: molecules are BUILT from sequences so the ground truth is known by construction (not hand-written SMILES)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rdkit import Chem
import chem

def cyclize(seq, d_idx=(), nme_idx=()):
    m = Chem.RWMol(Chem.MolFromSequence(seq))
    Chem.AssignStereochemistry(m, cleanIt=True, force=True)
    alphas = [a[0] for a in m.GetSubstructMatches(Chem.MolFromSmarts("[CX4;$([CX4]([NX3])[CX3]=O)]"))]
    for i in d_idx:
        a = m.GetAtomWithIdx(alphas[i])
        a.InvertChirality() if a.GetChiralTag() != Chem.ChiralType.CHI_UNSPECIFIED else None
    nterm = m.GetSubstructMatch(Chem.MolFromSmarts("[NX3;H2][CX4]C(=O)"))[0]
    cands = [t for t in m.GetSubstructMatches(Chem.MolFromSmarts("[CX3](=O)[OX2H1]")) if m.GetAtomWithIdx(t[0]).GetNeighbors() and any(n.GetIdx() in alphas for n in m.GetAtomWithIdx(t[0]).GetNeighbors())]
    assert len(cands) == 1, "C-terminal acid must be the only acid on an alpha carbon"
    c, o = cands[0][0], cands[0][2]
    m.AddBond(nterm, c, Chem.BondType.SINGLE)
    m.RemoveAtom(o)
    for i in sorted(nme_idx, reverse=True):
        # N of residue i: the amide N bonded to alpha i
        a = m.GetAtomWithIdx(alphas[i] if alphas[i] < o else alphas[i] - 1)
        n = [x for x in a.GetNeighbors() if x.GetSymbol() == "N"][0]
        idx = m.AddAtom(Chem.Atom(6)); m.AddBond(n.GetIdx(), idx, Chem.BondType.SINGLE)
    mol = m.GetMol(); Chem.SanitizeMol(mol); return mol

def test_all_l_canonical_is_peptide():
    assert chem.classify(cyclize("GGAFKV"))["stratum"] == "peptide"
    assert chem.classify(cyclize("RGDFKP"))["stratum"] == "peptide"      # Pro handled as canonical

def test_d_residue_makes_ncaa():
    c = chem.classify(cyclize("RGDFKV", d_idx=(3,)))
    assert c["stratum"] == "ncaa_peptide" and c["n_d"] == 1

def test_n_methyl_makes_ncaa():
    c = chem.classify(cyclize("GGAFKV", nme_idx=(2,)))
    assert c["stratum"] == "ncaa_peptide" and c["n_nme"] >= 1

def test_d_proline_makes_ncaa():
    c = chem.classify(cyclize("GGAFKP", d_idx=(5,)))
    assert c["stratum"] == "ncaa_peptide" and c["n_d"] == 1, c

def test_peptoid_n_ethyl_makes_ncaa():
    m = Chem.RWMol(cyclize("GGAFKV", nme_idx=(2,)))
    c_me = [a for a in m.GetAtoms() if a.GetSymbol() == "C" and a.GetDegree() == 1 and any(n.GetSymbol() == "N" and n.GetDegree() == 3 for n in a.GetNeighbors())][0]
    new = m.AddAtom(Chem.Atom(6)); m.AddBond(c_me.GetIdx(), new, Chem.BondType.SINGLE)
    mol = m.GetMol(); Chem.SanitizeMol(mol)
    assert chem.classify(mol)["stratum"] == "ncaa_peptide" and chem.classify(mol)["n_nsub"] >= 1

def test_beta_amino_acid_backbone_is_ncaa():
    m = chem.parse("O=C1CCNC(=O)CNC(=O)CNC(=O)[C@H](C)NC(=O)[C@H](Cc2ccccc2)N1")   # beta-Ala in the ring
    c = chem.classify(m); assert c["stratum"] == "ncaa_peptide" and c["n_backbone_mismatch"] == 1, c

def test_proline_peptide_stays_peptide_not_nsub():
    c = chem.classify(cyclize("GGAFKP")); assert c["stratum"] == "peptide" and c["n_nsub"] == 0, c

def test_noncanonical_side_chain_makes_ncaa():
    m = chem.parse("O=C1CNC(=O)[C@H](Cc2ccc3ccccc3c2)NC(=O)[C@H](C)NC(=O)[C@H](CC(C)C)NC(=O)CN1")   # 2-naphthylalanine + canonical others
    assert chem.classify(m)["stratum"] == "ncaa_peptide"

def test_rgd_detected_only_N_to_C_RGD():
    assert chem.has_rgd(cyclize("RGDFKV")) and not chem.has_rgd(cyclize("DGRFKV")) and not chem.has_rgd(cyclize("GGAFKV"))

def test_macrolide_is_non_peptide():
    m = chem.parse("CC[C@@H]1[C@@]([C@@H]([C@H](C(=O)[C@@H](C[C@@]([C@@H]([C@H]([C@@H]([C@@H](C(=O)O1)C)O[C@H]2C[C@@]([C@H]([C@@H](O2)C)O)(C)OC)C)O[C@H]3[C@@H]([C@H](C[C@H](O3)C)N(C)C)O)(C)O)C)C)O)(C)O")
    assert chem.classify(m)["stratum"] == "non_peptide_macrocycle"

def test_ring_and_amide_counts():
    m = cyclize("GGAFKV"); assert chem.max_ring(m) == 18 and chem.descriptors(m)["amide"] == 6

def test_disulfide_bicycle_still_peptide():
    m = Chem.RWMol(cyclize("CGAFKC"))
    sg = [a.GetIdx() for a in m.GetAtoms() if a.GetSymbol() == "S"]
    m.AddBond(sg[0], sg[1], Chem.BondType.SINGLE)
    for i in sg: m.GetAtomWithIdx(i).SetNumExplicitHs(0); m.GetAtomWithIdx(i).SetNoImplicit(False)
    mol = m.GetMol(); Chem.SanitizeMol(mol)
    assert chem.classify(mol)["stratum"] == "peptide", chem.classify(mol)

if __name__ == "__main__":
    n = 0
    for k, f in list(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(n, "tests passed")
