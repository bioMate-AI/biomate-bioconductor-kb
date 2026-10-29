import config, gp_parse
from pm_filter import is_peptide_macrocycle

def test_cyclic_hexapeptide_true():
    assert is_peptide_macrocycle("C[C@H]1NC(=O)CNC(=O)[C@@H](C)NC(=O)CNC(=O)[C@@H](C)NC(=O)CNC1=O")

def test_linear_peptide_false():
    assert not is_peptide_macrocycle("CC(N)C(=O)NCC(=O)NC(C)C(=O)NCC(=O)O")

def test_macrolactone_without_amides_false():
    assert not is_peptide_macrocycle("O=C1CCCCCCCCCCCO1")

def test_small_amide_drug_false():
    assert not is_peptide_macrocycle("CC(=O)Nc1ccc(O)cc1")

def test_bad_smiles_false():
    assert not is_peptide_macrocycle("not_a_smiles")

def test_cpc_codes_normalise():
    assert "C07K7/64" in config.CPC_VERIFIED and "A61K38/12" not in config.CPC_VERIFIED

def test_gp_parse_minimal():
    html = ('<html><title>US1B2 - Test - Google Patents</title><meta name="DC.title" content="Cyclic peptides">'
            '<meta name="description" content="An abstract."><meta name="DC.date" content="2020-01-02" scheme="issue">'
            '<span itemprop="Code">C07K7/64</span><section itemprop="claims"><div>1. A cyclic peptide.</div></section>'
            '<section itemprop="description"><p>Example 1 IC50 5 nM.</p></section></html>')
    d = gp_parse.parse(html)
    assert d["title"] == "Cyclic peptides" and d["cpc"] == ["C07K7/64"] and "IC50 5 nM" in d["description"] and d["pub_date"] == "2020-01-02"
