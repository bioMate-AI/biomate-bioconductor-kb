import sys, math
from pathlib import Path
import pandas as pd
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_matrix as bm

MX = pd.read_csv(Path(__file__).resolve().parents[1] / "matrix.csv")
K = MX[MX.source == "kapp2017"]

def test_parse_value():
    assert bm.parse_value("13.7 ± 0.3") == (13.7, 0.3, "=")
    assert bm.parse_value("> 10000") == (10000.0, None, ">")
    assert bm.parse_value(">10000") == (10000.0, None, ">")
    assert bm.parse_value("n.d") is None and bm.parse_value("n.d.") is None

def test_kapp_shape():  # Table 1 has 29 ligand rows, Table 2 has 5; 6 integrins each
    assert K.ligand_id.nunique() == 34 and K.integrin.nunique() == 6 and len(K) == 204
    assert (K.table == "Table 1").sum() == 29 * 6 and (K.table == "Table 2").sum() == 5 * 6
    assert K.groupby("ligand_id").size().eq(6).all()

def test_kapp_spot_values_and_censoring():
    g = lambda l, i: K[(K.ligand_id == l) & (K.integrin == i)].iloc[0]
    assert g("Cilengitide", "avb3").ic50_nM == 0.61 and g("Cilengitide", "avb3").censor == "="
    assert g("c(FRGDLAFp(NMe)K)", "avb6").ic50_nM == 0.28
    assert g("RGD", "avb6").censor == ">" and g("RGD", "avb6").ic50_nM == 10000
    assert g("Tirofiban", "aIIbb3").ic50_nM == 1.3
    assert g("sn243", "avb6").censor == ">"  # printed '>10000' without space
    assert g("Echistatin", "aIIbb3").ic50_nM == 0.90

def test_kapp_censored_count():
    assert (K.censor == ">").sum() == 89 and (K.censor == "=").sum() == 115
    assert (K[K.censor == ">"].ic50_nM == 10000).all()

def test_pIC50():
    assert all(abs(r.pIC50 - (9 - math.log10(r.ic50_nM))) < 1e-3 for r in MX.itertuples())
    assert (MX[MX.censor == ">"].pIC50 <= 5.35).all()

def test_quigley():
    Q = MX[MX.source == "quigley2023"]
    assert len(Q) == 16 and Q.ligand_id.nunique() == 4
    v = lambda l, i: Q[(Q.ligand_id == l) & (Q.integrin == i)].ic50_nM.iloc[0]
    assert v("Quigley_FF", "avb6") == 0.17 and v("Quigley_FF", "a5b1") == 226 and v("Quigley_YF", "avb3") == 630
    assert v("Quigley_FY", "avb8") == 37 and v("Quigley_YY", "avb3") == 219 and (Q.censor == "=").all()

def test_tomassi():
    T = MX[(MX.source == "tomassi2021") & MX.ligand_id.str.startswith("Tomassi_cmpd")]
    assert T.ligand_id.nunique() == 6 and len(T) == 16
    c = T[T.censor == ">"]
    assert set(c.ligand_id) == {"Tomassi_cmpd4", "Tomassi_cmpd5"} and len(c) == 3 and (c.ic50_nM == 5000).all()
    assert T[(T.ligand_id == "Tomassi_cmpd6") & (T.integrin == "avb3")].ic50_nM.iloc[0] == 1199
    assert T[(T.ligand_id == "Tomassi_cmpd1") & (T.integrin == "avb8")].ic50_nM.iloc[0] == 174

def test_ligands_csv():
    L = pd.read_csv(Path(__file__).resolve().parents[1] / "ligands.csv").fillna("")
    assert set(MX.ligand_id) == set(L.ligand_id)
    A = L[L.tier == "A"]; assert len(A) == 7 and (A.pubchem_cid != "").all()
    assert (L[L.smiles != ""].provenance != "").all()
    assert int(float(L[L.ligand_id == "Cilengitide"].iloc[0].pubchem_cid)) == 176873
