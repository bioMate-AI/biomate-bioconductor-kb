"""
Tests for the tool-catalog retriever (sandbox/retrieval_v2/retrievers/tool_catalog.py).

Runs entirely against the local canonical DB built by:
    python -m sandbox.retrieval_v2.scripts.build_canonical_db

No network calls. Fast.

Validation criteria align with the routing benchmark expectations: well-known
suites must surface in the top results for their canonical queries, and the
hierarchy must round-trip (search → list functions → resolve wrapper) for
real biological queries.
"""
from __future__ import annotations

import pytest

from sandbox.retrieval_v2.retrievers.tool_catalog import (
    search_tool_suites, list_functions, resolve_wrapper, _DB_PATH,
)


def test_db_exists():
    assert _DB_PATH.exists(), (
        f"Canonical DB missing at {_DB_PATH}. "
        "Run `python -m sandbox.retrieval_v2.scripts.build_canonical_db` first."
    )


# ─── search_tool_suites ──────────────────────────────────────────────────

@pytest.mark.parametrize("query,must_contain_suite_id", [
    ("DESeq2 differential expression", "deseq2"),
    ("BWA alignment", "bwa"),
    ("samtools sort BAM", "samtools"),
    ("Picard read groups", "picard"),
    ("GATK4 variant calling", "gatk4"),
    ("EMBOSS sequence analysis", "emboss"),
    ("STAR RNA-seq aligner", "star"),         # may have multiple star-prefix suites
    ("featureCounts read summarization", "featurecounts"),
    ("MultiQC quality report", "multiqc"),
    ("Bowtie2 short read aligner", "bowtie2"),
])
def test_canonical_queries_surface_expected_suite(query, must_contain_suite_id):
    results = search_tool_suites(query, top_k=10)
    assert results, f"No results for query: {query!r}"
    surfaced_ids = [r["suite_id"] for r in results]
    # Match suite_id case-insensitively (allow exact + substring start)
    expected = must_contain_suite_id.lower()
    found = any(
        sid.lower() == expected or sid.lower().startswith(expected + "_")
        or sid.lower().startswith(expected + "-")
        for sid in surfaced_ids
    )
    assert found, (
        f"Expected suite '{must_contain_suite_id}' in top-10 for {query!r}; "
        f"got {surfaced_ids}"
    )


def test_search_empty_query():
    assert search_tool_suites("") == []
    assert search_tool_suites("   ") == []


def test_search_result_shape():
    results = search_tool_suites("alignment", top_k=3)
    assert results
    for r in results:
        assert {"suite_id", "display_name", "description", "top_category",
                "wrapper_count", "function_count", "score"} <= set(r.keys())
        assert isinstance(r["wrapper_count"], int)
        assert 0.0 <= r["score"] <= 1.0


def test_search_top_k_respected():
    results = search_tool_suites("sequence", top_k=5)
    assert len(results) <= 5


def test_search_category_filter():
    results = search_tool_suites("analysis", top_k=10, category="RNA")
    for r in results:
        assert r["top_category"] == "RNA"


# ─── list_functions ──────────────────────────────────────────────────────

def test_list_functions_picard_has_many():
    """Picard wraps ~46 distinct Picard operations; we should list many."""
    fns = list_functions("picard", top_k=100)
    assert len(fns) >= 30, f"Picard should have ≥30 functions, got {len(fns)}"
    fn_names = " ".join(f["display_name"].lower() for f in fns)
    # At least some recognizable Picard operations should appear
    expected_keywords = ["sort", "markduplicates", "mergesam", "fastqtosam",
                         "addorreplacereadgroups", "validatesam"]
    found = sum(1 for kw in expected_keywords if kw in fn_names)
    assert found >= 3, (
        f"Picard functions should include classic ops; only found {found}/6 "
        f"keywords in {fn_names[:300]}"
    )


def test_list_functions_unknown_suite():
    assert list_functions("not_a_real_suite_xyz") == []


def test_list_functions_shape():
    fns = list_functions("bwa")
    assert fns
    for f in fns:
        assert {"function_id", "display_name", "wrapper_count"} <= set(f.keys())
        assert isinstance(f["wrapper_count"], int) and f["wrapper_count"] >= 1


# ─── resolve_wrapper ─────────────────────────────────────────────────────

def test_resolve_wrapper_with_no_function_picks_top():
    r = resolve_wrapper("bwa")
    assert r is not None
    assert r["suite_id"] == "bwa"
    assert r["wrapper_tool_id"]
    assert r["confidence"] >= 0.7


def test_resolve_wrapper_unknown_suite():
    assert resolve_wrapper("not_a_real_suite") is None


def test_resolve_wrapper_platform_preference_galaxy():
    """If we ask for galaxy, we should get a toolshed-prefixed wrapper when one exists."""
    r = resolve_wrapper("samtools", platform_preference="galaxy")
    assert r is not None
    assert r["wrapper_tool_id"].startswith("toolshed."), (
        f"Galaxy preference should yield a toolshed wrapper, got "
        f"{r['wrapper_tool_id']}"
    )


# ─── round-trip flow (UC-style) ──────────────────────────────────────────

def test_end_to_end_rnaseq_alignment_flow():
    """Simulate the LLM's intended path for 'I need to align RNA-seq reads'."""
    # Step 1: search at suite level
    suites = search_tool_suites("RNA-seq spliced read alignment", top_k=8)
    assert suites
    surfaced = [s["suite_id"] for s in suites]
    # At least one classic RNA-seq aligner should appear
    assert any(
        sid.startswith(("star", "hisat", "tophat", "rna_star", "salmon"))
        for sid in surfaced
    ), f"No RNA-seq aligner suite in {surfaced}"


def test_end_to_end_variant_calling_flow():
    suites = search_tool_suites("germline variant calling", top_k=8)
    assert suites
    surfaced = [s["suite_id"] for s in suites]
    # Any well-known variant caller family is acceptable
    _CALLERS = ("gatk", "bcftools", "deepvariant", "varscan", "freebayes",
                "strelka", "clair3", "delly", "lofreq", "pbsv", "manta",
                "octopus", "sniffles")
    assert any(any(c in sid for c in _CALLERS) for sid in surfaced), \
        f"No variant caller suite in {surfaced}"
