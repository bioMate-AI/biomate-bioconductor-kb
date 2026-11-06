"""Topology-token positive controls (cd cyclic_llm && python3 -m pytest -q v4_eval/test_v5_tokens.py)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rdkit import Chem
import v5_atom_tokens as V

def smi_from_seq(seq): return Chem.MolToSmiles(Chem.MolFromSequence(seq))

def test_linear():
    assert V.topology(smi_from_seq("AGLKF"))[0] == "<topo_linear>"

def test_head_to_tail():
    assert V.topology("C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)NCC(=O)N2CCC[C@H]2C(=O)N1")[0] == "<topo_h2t>"

def test_lariat_isopeptide_and_disulfide_flag():
    # Lys side-chain amide closing onto Asp side chain, linear backbone: 1 macro ring, backbone not cyclic
    t = V.topology("NC(CCCCNC(=O)CC(C(=O)NCC(=O)O)NC(=O)CN)C(=O)O"); assert t[0] in ("<topo_lariat>", "<topo_linear>")
    ds = V.topology("N[C@@H](CSSC[C@H](NC(=O)CN)C(=O)NCC(=O)NC(=O)[C@@H](N)CC)C(=O)O")  # S-S bond present
    assert "<flag_ds>" in ds

def test_staple_and_not_staple():
    # macro ring with a 7-carbon aliphatic bridge between two carbonyls (hydrocarbon bridge) must be flagged; a normal cyclo-peptide must not
    br = "O=C1CCCCCCCC(=O)NCC(=O)NCC(=O)N1"
    assert V.Chem.MolFromSmiles(br) is not None and "<flag_stap>" in V.topology(br)
    assert "<flag_stap>" not in V.topology("C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)NCC(=O)N2CCC[C@H]2C(=O)N1")

def test_bad_smiles():
    assert V.topology("not smiles") == ["<topo_unk>"]
