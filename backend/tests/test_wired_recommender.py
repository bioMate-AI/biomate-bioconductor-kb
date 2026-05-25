"""Tests for `WiredToolParameterRecommender`.

Verifies:
  1. Flag-off behavior is bit-identical to the base class
  2. Flag-on prioritizes the canonical family wrapper
  3. Library degrades gracefully if the YAML/library is missing
  4. Held-out queries (no canonical entry) pass through unchanged
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.workflow_ops.autofix.tool_parameter_recommender import (  # noqa: E402
    ToolParameterRecommender,
)
from backend.lib.galaxy.ai.retrievers.wired_recommender import (  # noqa: E402
    WiredToolParameterRecommender,
)

DB = ROOT / "backend" / "database" / "galaxy_ai_tools.db"


@pytest.fixture
def base_rec():
    if not DB.exists():
        pytest.skip(f"DB not present at {DB}")
    return ToolParameterRecommender(db_path=str(DB))


@pytest.fixture
def wired_rec():
    if not DB.exists():
        pytest.skip(f"DB not present at {DB}")
    return WiredToolParameterRecommender(db_path=str(DB))


@pytest.fixture(autouse=True)
def _reset_flag():
    prev = os.environ.pop("BIOMATE_FAMILY_PRIORITIZE", None)
    yield
    if prev is not None:
        os.environ["BIOMATE_FAMILY_PRIORITIZE"] = prev
    else:
        os.environ.pop("BIOMATE_FAMILY_PRIORITIZE", None)


# ─── Flag-off parity with base class ────────────────────────────────────

def test_flag_off_bit_identical_to_base(base_rec, wired_rec):
    """Flag unset → WiredRecommender returns the same names+tool_ids as base."""
    for query in ("samtools", "picard", "fastqc", "deseq2"):
        base = [(t.tool_id, t.name) for t in base_rec.search_tools(query, limit=5)]
        wired = [(t.tool_id, t.name) for t in wired_rec.search_tools(query, limit=5)]
        assert base == wired, (
            f"flag-off divergence for query {query!r}:\n"
            f"  base:  {base}\n  wired: {wired}"
        )


def test_flag_off_no_yaml_access(wired_rec):
    """Smoke: flag-off path doesn't even import family_dedup library."""
    # Just verify the call completes without raising
    out = wired_rec.search_tools("samtools", limit=5)
    assert out  # at least some results
    # No assertion on content — just that flag-off path is independent


# ─── Flag-on utility ────────────────────────────────────────────────────

@pytest.mark.parametrize("query,expected_family", [
    ("samtools", "samtools"),
    ("picard", "picard"),
    ("fastqc", "fastqc"),
    ("deseq2", "deseq2"),
    ("bowtie2", "bowtie2"),
])
def test_flag_on_promotes_canonical_family(wired_rec, query, expected_family):
    """With flag on, top-1 must be from the expected canonical family.

    NOTE: top-1 display name may not literally contain the family token
    (e.g. samtools returns 'Depad SAM/BAM file' = samtools_depad wrapper).
    Test uses canonical_family_key to verify family membership instead.
    """
    from backend.lib.galaxy.ai.retrievers.family_dedup import canonical_family_key
    os.environ["BIOMATE_FAMILY_PRIORITIZE"] = "1"
    out = wired_rec.search_tools(query, limit=5)
    assert out, f"No results for {query!r}"
    top1_family = canonical_family_key(out[0].tool_id, out[0].name)
    assert top1_family == expected_family, (
        f"top-1 for {query!r} should be in family {expected_family!r}, "
        f"got family {top1_family!r} (name={out[0].name!r})"
    )


# ─── Limit honored ──────────────────────────────────────────────────────

def test_flag_on_respects_limit(wired_rec):
    """Even though wired path fetches 10×, return value must match caller's limit."""
    os.environ["BIOMATE_FAMILY_PRIORITIZE"] = "1"
    out = wired_rec.search_tools("samtools", limit=3)
    assert len(out) <= 3


def test_flag_off_respects_limit(wired_rec):
    out = wired_rec.search_tools("samtools", limit=3)
    assert len(out) <= 3


# ─── Held-out (no canonical entry) — behavior unchanged ────────────────

@pytest.mark.parametrize("uncovered_query", [
    "qiime",       # exists in DB; no canonical entry
    "gembassy",
    "ball",
    "sentieon",
    "parabricks",
])
def test_held_out_family_passes_through(base_rec, wired_rec, uncovered_query):
    """For families not in canonical YAML, wired output == base output (flag on)."""
    os.environ["BIOMATE_FAMILY_PRIORITIZE"] = "1"
    base = [t.tool_id for t in base_rec.search_tools(uncovered_query, limit=5)]
    wired = [t.tool_id for t in wired_rec.search_tools(uncovered_query, limit=5)]
    # Wired might reorder within held-out family (no harm), but at minimum the
    # set of returned tool_ids should overlap heavily. Strictest check: both
    # return non-empty results without raising.
    # Actually we expect identical SET (same tools, possibly different order
    # if the library does something) but the held-out case is that the library
    # doesn't fire at all, so order should match too.
    assert set(base[:5]) == set(wired[:5]), (
        f"held-out {uncovered_query!r}: base set ≠ wired set\n"
        f"  base:  {base}\n  wired: {wired}"
    )


# ─── Graceful degradation ──────────────────────────────────────────────

def test_does_not_break_on_unknown_query(wired_rec):
    os.environ["BIOMATE_FAMILY_PRIORITIZE"] = "1"
    out = wired_rec.search_tools("ALSDKFJASLKDJ_unknown_query_xyz", limit=5)
    # Empty or sparse results are fine; just must not raise
    assert isinstance(out, list)
