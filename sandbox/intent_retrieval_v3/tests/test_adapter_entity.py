"""Tests for the entity canonical resolution adapter."""
from __future__ import annotations

import pytest

from sandbox.intent_retrieval_v3.adapters.entity import extract_canonical_entities
from sandbox.intent_retrieval_v3.core.canonical_resolver import reset_canonical_cache


@pytest.fixture(autouse=True)
def _clear_cache():
    reset_canonical_cache()


# ─── Basic extraction ────────────────────────────────────────────────────

def test_extract_brca1_variants():
    """All BRCA1 alias forms should resolve to the same canonical_id."""
    for q in ("Show me BRCA1 mutations",
              "What about BRCA-1?",
              "tell me brca 1 in patients",
              "what does RNF53 do",  # alternative HGNC alias
              ):
        out = extract_canonical_entities(q)
        cids = [e["canonical_id"] for e in out]
        assert "BRCA1" in cids, f"BRCA1 missing for query: {q!r}, got {cids}"


def test_extract_multiple_entities():
    """A query with several entities should return them all."""
    q = "I want to study BRCA1 and TP53 mutations in breast cancer"
    out = extract_canonical_entities(q)
    cids = {e["canonical_id"] for e in out}
    assert {"BRCA1", "TP53", "breast_cancer"} <= cids


def test_extract_returns_metadata():
    out = extract_canonical_entities("BRCA1 mutations")
    brca1 = next(e for e in out if e["canonical_id"] == "BRCA1")
    assert brca1["entity_type"] == "gene"
    assert brca1["metadata"]["omim_id"] == "113705"


def test_filter_by_entity_type():
    """Querying with entity_type='gene' should drop disease/drug matches."""
    q = "BRCA1 and breast cancer treated with trastuzumab"
    out_all = extract_canonical_entities(q)
    out_genes = extract_canonical_entities(q, entity_type="gene")
    out_drugs = extract_canonical_entities(q, entity_type="drug")
    all_cids = {e["canonical_id"] for e in out_all}
    gene_cids = {e["canonical_id"] for e in out_genes}
    drug_cids = {e["canonical_id"] for e in out_drugs}
    assert "BRCA1" in all_cids and "BRCA1" in gene_cids
    assert "trastuzumab" in all_cids and "trastuzumab" in drug_cids
    assert "BRCA1" not in drug_cids
    assert "trastuzumab" not in gene_cids


# ─── Word boundary handling ──────────────────────────────────────────────

def test_no_substring_false_match():
    """'brca1' should NOT match inside 'ARLBRCA1X' or similar nonsense words."""
    out = extract_canonical_entities("the ARLBRCA1X invented sequence")
    cids = [e["canonical_id"] for e in out]
    assert "BRCA1" not in cids


def test_hyphenated_aliases_match():
    """Aliases with hyphens (BRCA-1, K-RAS) match the hyphenated form in the query."""
    out = extract_canonical_entities("K-RAS pathway analysis")
    cids = [e["canonical_id"] for e in out]
    assert "KRAS" in cids


def test_longest_alias_wins():
    """If both 'brca' and 'brca1' could match, pick the longer (more specific) alias.

    This is implicit in how resolve_entities iterates from longest alias first.
    """
    out = extract_canonical_entities("BRCA1 vs BRCA2 in cancer")
    cids = {e["canonical_id"] for e in out}
    assert "BRCA1" in cids
    assert "BRCA2" in cids


# ─── Disease + drug ──────────────────────────────────────────────────────

def test_disease_canonical():
    out = extract_canonical_entities("Cystic fibrosis registry data")
    cids = [e["canonical_id"] for e in out]
    assert "cystic_fibrosis" in cids
    cf = next(e for e in out if e["canonical_id"] == "cystic_fibrosis")
    assert cf["metadata"]["omim_id"] == "219700"


def test_drug_canonical_with_brand_alias():
    """'Gleevec' (brand) should resolve to imatinib canonical."""
    out = extract_canonical_entities("Patient was treated with Gleevec for CML")
    cids = [e["canonical_id"] for e in out]
    assert "imatinib" in cids
    im = next(e for e in out if e["canonical_id"] == "imatinib")
    assert im["matched_alias"] == "gleevec"


# ─── Edge cases ─────────────────────────────────────────────────────────

def test_empty_query():
    assert extract_canonical_entities("") == []
    assert extract_canonical_entities("   ") == []


def test_no_known_entities():
    out = extract_canonical_entities("the weather in San Francisco today")
    assert out == []


def test_dedup_within_query():
    """Mention BRCA1 three times → still get exactly ONE result."""
    out = extract_canonical_entities("BRCA1 BRCA1 mutations and brca-1 variants")
    brca1_hits = [e for e in out if e["canonical_id"] == "BRCA1"]
    assert len(brca1_hits) == 1


# ─── Honest test: rare gene canonical (validates ARL6IP1) ───────────────

def test_arl6ip1_canonical_resolution():
    """The 'rare gene' from the OMIM retriever test set should resolve cleanly,
    so downstream OMIM retriever calls use the canonical form."""
    out = extract_canonical_entities("ARL6IP1 in hereditary spastic paraplegia")
    cids = [e["canonical_id"] for e in out]
    assert "ARL6IP1" in cids
    arl = next(e for e in out if e["canonical_id"] == "ARL6IP1")
    # SPG61 disease should also resolve from "spastic paraplegia"
    # — though it requires the exact alias; here we only test the gene
    assert arl["metadata"]["primary_disease"].startswith("Spastic Paraplegia")
