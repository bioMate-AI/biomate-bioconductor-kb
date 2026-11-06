"""Unit tests with planted structures (positive controls) for tokens/annotation. Run: python3 test_annotate.py"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens as T, annotate as A
from rdkit import Chem

def test_token_classes():
    c = T.classify
    assert c("dP")["is_D"] and c("dP")["is_pro_like"] and not c("dP")["is_nme"]
    assert c("Me_dL")["is_nme"] and c("Me_dL")["is_D"] and c("Me_dL")["base"] == "L"
    assert c("meL")["is_nme"] and not c("meL")["is_D"]
    assert c("Sar")["is_nme"] and not c("Sar")["is_peptoid"]
    assert c("Bn_Gly")["is_peptoid"] and c("Bn_Gly")["comp"] == "aromatic" and c("Pr_Gly")["comp"] == "aliphatic"
    assert c("Mono5")["is_unknown"] and c("ac-")["is_cap_n"] and c("-pip")["is_cap_c"]
    assert c("bHph")["is_ext_backbone"] and c("Nle")["comp"] == "aliphatic" and c("Nva")["comp"] == "aliphatic"
    assert c("Et_Phe")["is_nalkyl"] and not c("Et_Phe")["is_nme"] and c("Et_Phe")["comp"] == "aromatic"
    assert c("deca-")["is_cap_n"] and not c("deca-")["is_D"]
    assert c("d(N->O)Val")["is_D"] and c("d(N->O)Val")["is_backbone_mod"]
    assert c("Asp_piperidide")["comp"] == "polar" and c("D")["comp"] == "negative" and c("Ser(tBu)")["comp"] == "polar"

def test_topology_from_helm():
    t = A.parse_helm("PEPTIDE1{A.B.C.D.E.F}$PEPTIDE1,PEPTIDE1,1:R1-6:R2$$$")
    assert A.topology_from_conn(t[1], 6) == ("head_to_tail", 1, 6)
    t = A.parse_helm("PEPTIDE1{[ac-].P.A.B.C.D.E.F}$PEPTIDE1,PEPTIDE1,4:R3-8:R2$$$")
    assert A.topology_from_conn(t[1], 8) == ("lariat_sc_cterm", 4, 8)
    t = A.parse_helm("PEPTIDE1{A.B.C.D.E.[-pip]}$PEPTIDE1,PEPTIDE1,1:R1-3:R3$$$")
    assert A.topology_from_conn(t[1], 6) == ("lariat_nterm_sc", 1, 3)

def test_pattern_features_planted():
    p = A.pattern_feats([1, 0, 1, 0, 1, 0], True); assert (p["adj"], p["alt"], p["run"]) == (0, 3, 1)
    p = A.pattern_feats([1, 1, 0, 0, 0, 1], True); assert p["adj"] == 2 and p["run"] == 3          # wrap-around run 5,0,1
    p = A.pattern_feats([1, 1, 0, 0, 0, 1], False); assert p["adj"] == 1 and p["run"] == 2         # linear tail: no wrap
    p = A.pattern_feats([0, 0, 0], True); assert p == dict(adj=0, alt=0, run=0)

def test_cip_counts_follow_planted_chirality():
    l = Chem.MolFromSmiles("C[C@H]1NC(=O)[C@H](C)NC(=O)[C@H](CC(C)C)NC1=O")
    d = Chem.MolFromSmiles("C[C@@H]1NC(=O)[C@H](C)NC(=O)[C@H](CC(C)C)NC1=O")      # flip one alpha centre
    rl, sl, n = A.cip_backbone_counts(l); rd, sd, _ = A.cip_backbone_counts(d)
    assert n == 3 and rl + sl == 3 and abs(rl - rd) == 1 and abs(sl - sd) == 1

def test_smiles_topology_rule():
    h2t = Chem.MolFromSmiles("C[C@H]1NC(=O)[C@H](C)NC(=O)[C@H](CC(C)C)NC(=O)[C@H](Cc2ccccc2)NC1=O")
    lar = Chem.MolFromSmiles("CC(=O)N[C@@H](C)C(=O)N[C@@H]1CCCCNC(=O)[C@H](C)NC1=O")           # Ac-Ala-Lys(side chain->C-term Ala)
    assert A.rdkit_topology(h2t) == "head_to_tail" and A.rdkit_topology(lar) == "lariat"
    assert A.rdkit_topology(Chem.MolFromSmiles("CCO")) == "acyclic"

def test_annotate_one_counts():
    helm = "PEPTIDE1{[dP].[Me_dL].L.[meL].A.Y}$PEPTIDE1,PEPTIDE1,1:R1-6:R2$$$"
    smi = "CC(C)C[C@@H]1NC(=O)[C@H](Cc2ccc(O)cc2)NC(=O)[C@@H](C)N(C)C(=O)[C@H](CC(C)C)NC(=O)[C@H](CC(C)C)N(C)C(=O)[C@H]2CCCN12"
    a = A.annotate_one(helm, smi)
    assert a["helm_topology"] == "head_to_tail" and a["n_D"] == 2 and a["n_dpro"] == 1 and a["n_D_and_nme"] == 1 and a["n_nme"] == 2
    assert a["nme_pos"] == [2, 4] and a["d_pos"] == [1, 2] and a["nme_adj_pro"] == 1       # Me_dL at position 2 is adjacent to dP at position 1

if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for f in fns: f(); print("PASS", f.__name__)
    print(len(fns), "tests passed")
