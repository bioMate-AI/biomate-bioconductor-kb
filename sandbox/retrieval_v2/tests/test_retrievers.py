"""
Tests for backend.lib.galaxy.ai.retrievers.

Covers all 3 retrievers + tool dispatch + cache behavior. Live-API tests are
skipped if `BIOMATE_SKIP_NETWORK_TESTS=1` is set in the environment.

Run with:
    cd /home/yzhang/biomate
    PYTHONPATH=. pytest backend/tests/test_retrievers.py -v

Validation targets are tied to the use cases documented in:
    docs/20260518_RETRIEVAL_TOOLS_PRODUCTIZATION_AND_USE_CASES.md
"""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

import pytest

from sandbox.retrieval_v2.retrievers import (
    fetch_literature_passage,
    search_literature,
    lookup_omim_gene,
    TOOL_SCHEMAS,
    dispatch_tool,
)
from sandbox.retrieval_v2.retrievers.europe_pmc import CACHE_DIR as PMC_CACHE
from sandbox.retrieval_v2.retrievers.omim import CACHE_DIR as OMIM_CACHE


_SKIP_NET = os.environ.get("BIOMATE_SKIP_NETWORK_TESTS") == "1"
skip_network = pytest.mark.skipif(_SKIP_NET, reason="network tests disabled")


# ─────────────────────────────────────────────────────────────────────────────
# Tool schemas (offline)
# ─────────────────────────────────────────────────────────────────────────────

def test_tool_schemas_well_formed():
    assert isinstance(TOOL_SCHEMAS, list)
    assert len(TOOL_SCHEMAS) >= 3
    names = {t["name"] for t in TOOL_SCHEMAS}
    assert names >= {"search_literature", "fetch_literature_passage", "lookup_omim_gene"}
    for t in TOOL_SCHEMAS:
        assert "description" in t
        assert "input_schema" in t
        sch = t["input_schema"]
        assert sch["type"] == "object"
        assert "properties" in sch
        # description must be at least 30 chars (Anthropic best practice)
        assert len(t["description"]) >= 30, t["name"]


def test_dispatch_unknown_tool_returns_error():
    out = dispatch_tool("nonexistent_tool", {})
    assert "error" in out
    assert "Unknown" in out["error"]


def test_dispatch_missing_required_input():
    out = dispatch_tool("lookup_omim_gene", {})
    assert "error" in out


def test_dispatch_fetch_passage_without_doi_or_pmid():
    out = dispatch_tool("fetch_literature_passage", {"query": "anything"})
    assert "error" in out
    assert "doi" in out["error"].lower() or "pmid" in out["error"].lower()


# ─────────────────────────────────────────────────────────────────────────────
# OMIM retriever — UC-1, UC-4
# ─────────────────────────────────────────────────────────────────────────────

@skip_network
def test_omim_brca1_breast_cancer():
    """UC-4: BRCA1 lookup must return the gene MIM (113705) and at least one
    breast-cancer-related disease MIM."""
    result = lookup_omim_gene("BRCA1")
    assert result.get("gene_symbol") == "BRCA1"
    # 113705 is the BRCA1 GENE MIM (not a disease) — returned in gene_mim
    assert result.get("gene_mim") == "113705", f"BRCA1 gene MIM should be 113705, got {result.get('gene_mim')}"
    diseases = result.get("diseases", [])
    assert diseases, "BRCA1 must return ≥1 OMIM disease"
    # At least one disease should mention breast/ovarian cancer (BRCA1's signature association)
    breast_match = any(
        re.search(r"breast|ovarian", d["name"], re.IGNORECASE)
        for d in diseases
    )
    assert breast_match, f"BRCA1 must link to breast/ovarian cancer in {[d['name'] for d in diseases]}"


@skip_network
def test_omim_arl6ip1_spg61():
    """UC-1: ARL6IP1 → Spastic Paraplegia 61 (OMIM 615685). The 'rare gene' case
    that LLM hallucinates as SPG7 without retrieval."""
    result = lookup_omim_gene("ARL6IP1")
    diseases = result.get("diseases", [])
    # Either OMIM 615685 (SPG61) or the name should mention "Spastic Paraplegia"
    found = any(
        d["omim_id"] == "615685" or "spastic paraplegia" in d["name"].lower()
        for d in diseases
    )
    assert found, f"ARL6IP1 should link to SPG61. Got: {diseases}"


@skip_network
def test_omim_unknown_gene_returns_empty_not_error():
    """Robustness: a fake gene symbol returns empty diseases, not an error."""
    result = lookup_omim_gene("FAKEGENE_XYZ123_NOTREAL")
    assert "diseases" in result
    assert result["diseases"] == [] or result.get("error") is None


def test_omim_empty_input_returns_error():
    assert "error" in lookup_omim_gene("")


@skip_network
def test_omim_cache_hit_fast(tmp_path, monkeypatch):
    """Second lookup of same gene must hit cache and return in <200ms."""
    result1 = lookup_omim_gene("TP53")
    assert result1.get("gene_symbol") == "TP53"

    t0 = time.time()
    result2 = lookup_omim_gene("TP53")
    elapsed_ms = (time.time() - t0) * 1000
    assert result2 == result1
    assert elapsed_ms < 200, f"Cache hit took {elapsed_ms:.0f} ms (expected <200)"


# ─────────────────────────────────────────────────────────────────────────────
# Europe PMC search — UC-2, UC-1
# ─────────────────────────────────────────────────────────────────────────────

@skip_network
def test_search_literature_returns_papers():
    """UC-2: free-text search returns real papers with PMIDs."""
    results = search_literature("CRISPR knockout TP53 cancer", max_results=3)
    assert isinstance(results, list)
    assert len(results) >= 1
    # At least one result should have a PMID
    assert any(r.get("pmid") for r in results), f"No PMIDs in {results}"
    for r in results:
        assert "title" in r
        assert "year" in r


@skip_network
def test_search_literature_year_filter():
    results = search_literature("BRD4 essentiality cancer", year_min=2022, max_results=3)
    for r in results:
        year = r.get("year")
        if year and str(year).isdigit():
            assert int(year) >= 2022, f"Year {year} violates year_min=2022"


def test_search_literature_empty_query():
    # Should not raise; may return [] or some result
    results = search_literature("", max_results=1)
    assert isinstance(results, list)


# ─────────────────────────────────────────────────────────────────────────────
# Europe PMC full-text passage — UC-1, UC-3, UC-5
# ─────────────────────────────────────────────────────────────────────────────

@skip_network
def test_fetch_passage_by_pmid_open_access():
    """Known open-access paper (PMID 36287100, Nature 2022 — pyroptosis)."""
    passage = fetch_literature_passage(
        query="caspase gasdermin pyroptosis",
        pmid="36287100",
        max_chars=1500,
    )
    # May be empty if paper isn't in PMC open access, so check the shape
    assert isinstance(passage, str)
    if passage:
        assert len(passage) <= 1600  # max_chars + a little slack for paragraph rounding


@skip_network
def test_fetch_passage_unknown_pmid_returns_empty():
    """Non-existent PMID returns empty string, not error."""
    passage = fetch_literature_passage(query="x", pmid="999999999999")
    assert passage == ""


@skip_network
def test_fetch_passage_cache_hit(tmp_path):
    """Second fetch of same (query, paper) is a fast cache hit."""
    # Use a paper that's known to be in PMC
    q = "BRCA1 DNA repair"
    pmid = "11149905"  # well-known BRCA1 paper, in PMC
    _ = fetch_literature_passage(query=q, pmid=pmid)
    t0 = time.time()
    _ = fetch_literature_passage(query=q, pmid=pmid)
    elapsed_ms = (time.time() - t0) * 1000
    assert elapsed_ms < 200, f"Passage cache hit took {elapsed_ms:.0f} ms"


# ─────────────────────────────────────────────────────────────────────────────
# End-to-end smoke: simulate use case via dispatch_tool
# ─────────────────────────────────────────────────────────────────────────────

@skip_network
def test_uc1_chat_literature_qa_smoke():
    """UC-1 smoke: 'What's known about ARL6IP1 in hereditary spastic paraplegia?'

    Simulates the production flow:
      1. LLM extracts gene=ARL6IP1
      2. lookup_omim_gene tool call
      3. search_literature tool call
      4. LLM (mock) would synthesize from both
    """
    # Step 1: OMIM lookup
    omim = dispatch_tool("lookup_omim_gene", {"gene_symbol": "ARL6IP1"})
    assert "diseases" in omim
    spg_match = any(
        "spastic paraplegia" in d["name"].lower() or d["omim_id"] == "615685"
        for d in omim["diseases"]
    )
    assert spg_match, "UC-1: ARL6IP1 → SPG must be retrievable"

    # Step 2: Literature search
    lit = dispatch_tool("search_literature", {
        "query": "ARL6IP1 spastic paraplegia",
        "max_results": 3,
    })
    assert "results" in lit
    # At least one paper should mention ARL6IP1 in title/abstract
    matched = any(
        "ARL6IP1" in (r.get("title") or "") + (r.get("abstract") or "")
        for r in lit["results"]
    )
    assert matched, f"UC-1: search should return ARL6IP1 papers. Got: {[r.get('title') for r in lit['results']]}"


@skip_network
def test_uc2_cro_compliance_search_smoke():
    """UC-2 smoke: hERG safety literature, post-2020, ≥3 PMIDs."""
    lit = dispatch_tool("search_literature", {
        "query": "hERG liability piperazine cardiac safety",
        "year_min": 2020,
        "max_results": 5,
    })
    results = lit.get("results", [])
    pmids = [r["pmid"] for r in results if r.get("pmid")]
    assert len(pmids) >= 3, f"UC-2: need ≥3 PMIDs from search, got {len(pmids)}"
    # Each PMID is a valid integer string
    for p in pmids:
        assert re.fullmatch(r"\d+", p), f"Bad PMID: {p}"
