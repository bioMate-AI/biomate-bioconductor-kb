"""Unit tests for backend.lib.galaxy.ai.chain_planner.

Uses an in-memory style temp SQLite DB so the tests don't depend on the
real 3,094-row catalog — keeps them fast and deterministic.
"""

import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "lib" / "galaxy" / "ai"))

import chain_planner  # noqa: E402


def _make_db(rows):
    """Create a temp SQLite DB matching the production `workflows` schema (minimal columns)."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE workflows (
            id INTEGER PRIMARY KEY,
            name TEXT,
            domain TEXT,
            description TEXT,
            input_types TEXT,
            output_types TEXT,
            executable INTEGER DEFAULT 1
        )
        """
    )
    for r in rows:
        conn.execute(
            "INSERT INTO workflows VALUES (?,?,?,?,?,?,?)",
            (
                r["id"],
                r["name"],
                r.get("domain", ""),
                r.get("description", ""),
                json.dumps(r["input_types"]),
                json.dumps(r["output_types"]),
                r.get("executable", 1),
            ),
        )
    conn.commit()
    conn.close()
    return Path(path)


@pytest.fixture
def linear_chain_db():
    """fastq → counts → DEG → enrichment, plus a noise workflow."""
    db = _make_db([
        {"id": 1, "name": "rnaseq", "domain": "transcriptomics",
         "input_types": ["fastq"], "output_types": ["counts_matrix"]},
        {"id": 2, "name": "deseq2", "domain": "transcriptomics",
         "input_types": ["counts_matrix"], "output_types": ["deg_table"]},
        {"id": 3, "name": "enrichgo", "domain": "transcriptomics",
         "input_types": ["deg_table"], "output_types": ["enrichment_results"]},
        {"id": 4, "name": "noise", "domain": "proteomics",
         "input_types": ["mzml"], "output_types": ["protein_groups"]},
    ])
    try:
        yield db
    finally:
        db.unlink(missing_ok=True)


def test_linear_three_step_chain_found(linear_chain_db):
    plans = chain_planner.plan_chains(
        start_input_types=["fastq"],
        goal_output_types=["enrichment_results"],
        max_steps=4,
        top_k=3,
        db_path=linear_chain_db,
    )
    assert plans, "should find at least one plan"
    # The 3-step plan rnaseq → deseq2 → enrichgo must appear.
    names_per_plan = [[s["workflow_name"] for s in p.steps] for p in plans]
    assert ["rnaseq", "deseq2", "enrichgo"] in names_per_plan


def test_respects_max_steps(linear_chain_db):
    plans = chain_planner.plan_chains(
        start_input_types=["fastq"],
        goal_output_types=["enrichment_results"],
        max_steps=2,
        db_path=linear_chain_db,
    )
    # No plan can be longer than max_steps.
    assert all(len(p.steps) <= 2 for p in plans)
    # The valid 3-step path must NOT appear truncated as a 2-step plan
    # that claims to reach enrichment.
    for p in plans:
        if any("enrichment_results" in s["output_types"] for s in p.steps):
            assert len(p.steps) <= 2


def test_impossible_goal_returns_empty(linear_chain_db):
    plans = chain_planner.plan_chains(
        start_input_types=["fastq"],
        goal_output_types=["nonexistent_type_xyz"],
        db_path=linear_chain_db,
    )
    assert plans == []


def test_no_start_types_returns_empty(linear_chain_db):
    assert chain_planner.plan_chains(start_input_types=[], db_path=linear_chain_db) == []


def test_deduplicates_paths():
    # Two parallel single-step workflows from fastq → bam. BFS should not emit
    # the same workflow twice as a "plan" via different aliases.
    db = _make_db([
        {"id": 1, "name": "aligner_a", "domain": "x",
         "input_types": ["fastq", "reads"], "output_types": ["bam"]},
        {"id": 2, "name": "aligner_b", "domain": "x",
         "input_types": ["fastq"], "output_types": ["bam"]},
    ])
    try:
        plans = chain_planner.plan_chains(
            start_input_types=["fastq"],
            goal_output_types=["bam"],
            top_k=10,
            db_path=db,
        )
        sigs = [tuple(s["workflow_id"] for s in p.steps) for p in plans]
        assert len(sigs) == len(set(sigs)), f"duplicate plans emitted: {sigs}"
    finally:
        db.unlink(missing_ok=True)


def test_score_prefers_shorter_chain_on_ties():
    """Given two paths with the same goal-keyword bonus, the shorter one must rank higher."""
    db = _make_db([
        # Short path: fastq → enrich_direct (one hop)
        {"id": 1, "name": "enrich_direct", "domain": "x",
         "description": "enrichment from fastq",
         "input_types": ["fastq"], "output_types": ["enrichment_results"]},
        # Long path: fastq → counts → enrich_via_counts
        {"id": 2, "name": "rnaseq2", "domain": "x",
         "input_types": ["fastq"], "output_types": ["counts_matrix"]},
        {"id": 3, "name": "enrich_via_counts", "domain": "x",
         "description": "enrichment from counts",
         "input_types": ["counts_matrix"], "output_types": ["enrichment_results"]},
    ])
    try:
        plans = chain_planner.plan_chains(
            start_input_types=["fastq"],
            goal="enrichment",
            goal_output_types=["enrichment_results"],
            top_k=5,
            db_path=db,
        )
        assert plans, "expected plans"
        # First plan should be the shorter one.
        assert len(plans[0].steps) == 1
        assert plans[0].steps[0]["workflow_name"] == "enrich_direct"
        # Score of shorter plan must be >= score of any longer plan.
        for p in plans[1:]:
            if len(p.steps) > 1:
                assert plans[0].total_score >= p.total_score
    finally:
        db.unlink(missing_ok=True)


def test_connections_record_bridge_types(linear_chain_db):
    plans = chain_planner.plan_chains(
        start_input_types=["fastq"],
        goal_output_types=["enrichment_results"],
        db_path=linear_chain_db,
    )
    three_step = next(p for p in plans if len(p.steps) == 3)
    assert len(three_step.connections) == 2
    # Each connection has a non-empty `via` list.
    assert all(c.get("via") for c in three_step.connections)
    # Step 1→2 bridge should mention counts_matrix.
    first_conn = three_step.connections[0]
    assert any("counts_matrix" in pair for pair in first_conn["via"])
