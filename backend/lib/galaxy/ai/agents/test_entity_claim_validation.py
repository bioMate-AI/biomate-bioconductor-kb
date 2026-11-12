"""Entity-claim validation: a grounded answer's asserted entities are checked against
authoritative DBs, and fabrications are flagged. Pure logic (no network); the ClinVar
call itself is covered by the live handler. Spec: docs/20261111_ENTITY_CLAIM_VALIDATION_SPEC.md
"""
from galaxy.ai.agents.research_agent import (
    ResearchAgent,
    _normalize_protein_variant,
    _variant_in_clinvar_titles,
)

# Real ClinVar-style esummary titles for LRRK2 (HGVS notation, as the API returns)
LRRK2_TITLES = [
    "NM_198578.4(LRRK2):c.6055G>A (p.Gly2019Ser)",
    "NM_198578.4(LRRK2):c.4321C>T (p.Arg1441Cys)",
]


def test_variant_normalization_legacy_equals_hgvs():
    # legacy (G2019S) and HGVS (p.Gly2019Ser) canonicalise to the same tuple
    assert _normalize_protein_variant("G2019S") == (2019, "G", "S")
    assert _normalize_protein_variant("p.Gly2019Ser") == (2019, "G", "S")
    assert _normalize_protein_variant("Gly2019Ser") == (2019, "G", "S")
    assert _normalize_protein_variant("R1441C") == (1441, "R", "C")
    assert _normalize_protein_variant("not a variant") is None


def test_match_verifies_real_variants():
    assert _variant_in_clinvar_titles("G2019S", LRRK2_TITLES) is True        # real, legacy
    assert _variant_in_clinvar_titles("p.Gly2019Ser", LRRK2_TITLES) is True  # real, HGVS
    assert _variant_in_clinvar_titles("R1441C", LRRK2_TITLES) is True        # real


def test_match_flags_the_lrrk2_fabrications():
    # the three non-existent variants the live answer led with
    assert _variant_in_clinvar_titles("p.Cys2024Arg", LRRK2_TITLES) is False
    assert _variant_in_clinvar_titles("p.Ala733Glu", LRRK2_TITLES) is False
    assert _variant_in_clinvar_titles("p.Thr475Ala", LRRK2_TITLES) is False


def test_split_claims_parses_and_strips():
    ans = ('LRRK2 G2019S causes PD.\n'
           'CLAIMS: [{"text":"G2019S","type":"variant","subject":"LRRK2"}]')
    body, claims = ResearchAgent._split_claims(ans)
    assert "CLAIMS:" not in body
    assert body == "LRRK2 G2019S causes PD."
    assert claims == [{"text": "G2019S", "type": "variant", "subject": "LRRK2"}]


def test_split_claims_absent_is_noop():
    body, claims = ResearchAgent._split_claims("plain answer, no claims line")
    assert claims == []
    assert body == "plain answer, no claims line"


def test_split_claims_malformed_is_soft():
    body, claims = ResearchAgent._split_claims("answer\nCLAIMS: [not json")
    assert claims == []  # fail-soft, never raises
