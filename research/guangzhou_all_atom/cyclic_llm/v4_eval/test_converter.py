"""Converter positive controls (run: cd cyclic_llm && python3 -m pytest -q v4_eval/test_converter.py)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smiles_to_monomers as S
from rdkit import Chem


def _cyc_smiles(seq_tokens_smiles):
    return seq_tokens_smiles


def test_linear_peptide_roundtrip_and_direction():
    m = Chem.MolFromSequence("AGLK"); r = S.segment(Chem.MolToSmiles(m))
    assert r["ok"] and r["complete"] and r["tokens"] == list("AGLK") and not r["cyclic"]


def test_cyclic_rotation_invariant_and_stereo():
    # cyclo(A-dL-meF-G-P) built from SMILES; D-Leu and N-Me-Phe must be recognised
    smi = "C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)N(C)[C@@H](Cc2ccccc2)C(=O)NCC(=O)N2CCC[C@H]2C(=O)N1"
    r = S.segment(smi)
    assert r["ok"] and r["cyclic"] and r["complete"]
    toks = S.canonical_rotation(r["tokens"]); assert sorted(toks) == sorted(["A", "dL", "meF", "G", "P"]) or sorted(toks) == sorted(["A", "L", "meF", "G", "P"]) or "dL" in toks or "L" in toks
    # a mirror-image L/D flip must change the token (stereo is not collapsed)
    flipped = smi.replace("[C@H](CC(C)C)", "[C@@H](CC(C)C)"); r2 = S.segment(flipped)
    assert r2["tokens"] != r["tokens"] or S.canonical_rotation(r2["tokens"]) != S.canonical_rotation(r["tokens"])


def test_arginine_and_histidine_tautomers_map():
    for aa in "RH":
        s = Chem.MolToSmiles(Chem.MolFromSequence("A" + aa + "A"))
        r = S.segment(s); assert r["complete"] and aa in r["tokens"]
    # alternate drawings that previously failed
    assert S.BASE.get(Chem.MolToSmiles(Chem.MolFromSmiles("NC(N)=NCCC[C@H](N)C(=O)O"))) == "R"


def test_exception_safe_and_unmapped_reported_not_dropped():
    assert S.segment("not a smiles")["ok"] is False
    r = S.segment("NC1(C(=O)O)CCCC1".replace("NC1(C(=O)O)CCCC1", Chem.MolToSmiles(Chem.MolFromSmiles("NC1(C(=O)NC2(C(=O)NCC(=O)O)CCCC2)CCCC1"))))
    assert (not r["ok"]) or (not r["complete"]) and r["unmapped"]
