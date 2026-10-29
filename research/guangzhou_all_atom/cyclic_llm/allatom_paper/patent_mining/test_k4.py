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

# ---- extraction / verification tests (stage 2) ----
import verify_patent as vp, seq2smiles as s2s

TEXT = ("Example 12 Compound 12 cyclo(Cys-Pro-D-Ala-N-Me-Phe-Gly-Leu) showed an IC50 of 5 nM against PD-L1 in the HTRF assay. "
        "N-methylation of Phe4 increased PAMPA permeability from 0.3 to 2.1 x 10^-6 cm/s.")

def test_quote_must_be_verbatim():
    n = vp.norm(TEXT)
    it = {"kind": "sar_statement", "statement": "N-methylation raised permeability", "quote": "N-methylation of Phe4 increased PAMPA permeability from 0.3 to 2.1"}
    assert vp.verify(it, n, n)[0]
    it["quote"] = "N-methylation of Phe4 improved PAMPA permeability from 0.3 to 2.1"   # one word changed -> must be rejected
    ok, why, _ = vp.verify(it, n, n)
    assert not ok and why == "quote_not_in_patent_text"

def test_value_must_occur_in_text():
    n = vp.norm(TEXT)
    it = {"kind": "example_compound", "statement": "Compound 12 potency", "quote": "Compound 12 cyclo(Cys-Pro-D-Ala-N-Me-Phe-Gly-Leu) showed an IC50 of 5 nM",
          "activity": {"assay": "HTRF", "value": 5, "unit": "nM", "relation": "="}}
    assert vp.verify(it, n, n)[0]
    it["activity"]["value"] = 7
    assert vp.verify(it, n, n)[1] == "value_not_in_text"

def test_structure_string_must_be_verbatim_and_converts():
    n = vp.norm(TEXT)
    it = {"kind": "example_compound", "statement": "Compound 12 sequence", "quote": "Compound 12 cyclo(Cys-Pro-D-Ala-N-Me-Phe-Gly-Leu) showed an IC50 of 5 nM",
          "structure_string": "cyclo(Cys-Pro-D-Ala-N-Me-Phe-Gly-Leu)", "structure_format": "sequence"}
    ok, why, enr = vp.verify(it, n, n)
    assert ok and enr["structure_status"].startswith("ok")
    it["structure_string"] = "cyclo(Cys-Pro-Ala-Phe-Gly-Leu)"
    assert vp.verify(it, n, n)[1] == "structure_not_in_passage"

def test_converter_flags_unknown_residues_instead_of_guessing():
    import pytest
    with pytest.raises(s2s.ConvertError):
        s2s.to_smiles("Ala-Xyz-Gly-Phe")

def test_converter_n_methyl_and_d_residue_change_the_molecule():
    a = s2s.to_smiles("Ala-Phe-Gly-Leu")[0]
    b = s2s.to_smiles("Ala-D-Phe-Gly-Leu")[0]
    c = s2s.to_smiles("Ala-N-Me-Phe-Gly-Leu")[0]
    assert len({a, b, c}) == 3


def test_passages_cut_a_long_single_paragraph_into_bounded_windows():
    import extract_patents as ep
    body = "Example 1 the compound cyclo(Cys-Pro-Ala) had an IC50 of 5 nM and Table 1 shows N-methyl permeability. " * 400
    text = "Title\n\nAbstract\n\nCLAIMS: x\n\n" + body
    out = ep.passages(text, words=450, cap=30)
    assert 1 <= len(out) <= 30
    assert all(len(ps.split()) <= 450 for _, ps in out)
