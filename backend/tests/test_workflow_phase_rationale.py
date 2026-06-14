"""Tests for the (why?) rationale endpoint + populate script.

Covers section 1 (schema) + 3 (endpoint) + 5 (populate) of
docs/20260614_RATIONALE_ANCHOR_PLAN.md.
"""
from __future__ import annotations

import os
import sqlite3
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "backend", "lib"))

from galaxy.webapps.galaxy.api.nextflow_executor import (  # noqa: E402
    get_workflow_phase_rationale,
)


def _db_has_table(table: str) -> bool:
    db = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")
    with sqlite3.connect(db) as conn:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            (table,),
        ).fetchone()
    return bool(row)


@pytest.mark.skipif(
    not _db_has_table("workflow_phase_rationale"),
    reason="workflow_phase_rationale table not populated yet — run "
    "scripts/populate_workflow_phase_rationale.py --apply",
)
class TestEndpoint:
    def test_known_bioc_chain_returns_rationale(self):
        r = get_workflow_phase_rationale("bulk_rnaseq_consensus_de_bioc", "B_norm")
        assert r, "expected a rationale row for bulk_rnaseq B_norm"
        assert "DESeqDataSet" in r["rationale_text"]
        assert r["citation"]["doi"] == "10.1186/s13059-014-0550-8"
        assert r["qc_gate_name"] == "deseq2_negative_binomial_fit"
        assert isinstance(r["last_curated_at"], int)

    def test_methylation_dmrcate_phase(self):
        r = get_workflow_phase_rationale("methylation_450k_array_analysis", "D_dmr")
        assert r
        assert "bumphunter" in r["rationale_text"] or "DMR" in r["rationale_text"]
        assert r["citation"]["doi"] == "10.1186/1756-8935-8-6"

    def test_pseudobulk_centerpiece_phase(self):
        r = get_workflow_phase_rationale("scrna_pseudobulk_de_bioc", "E_pseudobulk")
        assert r
        assert "pseudoreplication" in r["rationale_text"]
        assert r["citation"]["doi"] == "10.1038/s41467-020-19894-4"

    def test_unknown_workflow_returns_empty(self):
        assert get_workflow_phase_rationale("does_not_exist_chain", "X") == {}

    def test_known_workflow_unknown_phase_returns_empty(self):
        assert get_workflow_phase_rationale(
            "bulk_rnaseq_consensus_de_bioc", "Z_nonexistent_phase"
        ) == {}

    def test_phase_without_citation_still_returns_text(self):
        # F_viz is a visualisation phase — no paper cited
        r = get_workflow_phase_rationale("bulk_rnaseq_consensus_de_bioc", "F_viz")
        assert r
        assert r["citation"] is None
        assert r["qc_gate_name"] is None
        # rationale_text still present
        assert len(r["rationale_text"]) > 30
