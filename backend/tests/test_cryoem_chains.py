"""
Unit tests for galaxy.ai.cryoem_chain_templates.

Run with:
    cd backend && PYTHONPATH=lib python3 tests/test_cryoem_chains.py
or:
    cd backend && PYTHONPATH=lib python3 -m pytest tests/test_cryoem_chains.py -v
"""

import json
import sqlite3
import sys
import tempfile
from pathlib import Path

# Make the galaxy package importable when running directly.
_BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_BACKEND / "lib"))

from galaxy.ai.cryoem_chain_templates import (  # noqa: E402
    CRYOEM_CHAIN_TEMPLATES,
    register_cryoem_chains,
    suggest_chains_for_run,
)

# Path to the production DB for step-name resolution tests.
_PROD_DB = _BACKEND / "database" / "galaxy_ai_tools.db"


# ── Helpers ────────────────────────────────────────────────────────────────────

def _make_temp_db() -> Path:
    """Create a minimal SQLite DB with the workflow_chains table."""
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp.close()
    conn = sqlite3.connect(tmp.name)
    conn.execute(
        """
        CREATE TABLE workflow_chains (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT UNIQUE NOT NULL,
            display_name TEXT,
            domain      TEXT,
            description TEXT,
            steps       TEXT,
            connections TEXT,
            required_inputs  TEXT,
            expected_outputs TEXT,
            example_queries  TEXT,
            tags        TEXT,
            source      TEXT,
            usage_count INTEGER DEFAULT 0,
            success_rate REAL DEFAULT 0.0,
            created_at  TEXT,
            updated_at  TEXT
        )
        """
    )
    conn.commit()
    conn.close()
    return Path(tmp.name)


# ── Tests ──────────────────────────────────────────────────────────────────────

def test_register_cryoem_chains_upserts_to_db():
    """register_cryoem_chains() must write all 3 chain names to a temp DB."""
    db = _make_temp_db()
    try:
        n = register_cryoem_chains(db_path=db)
        assert n == 3, f"expected 3 chains upserted, got {n}"
        conn = sqlite3.connect(str(db))
        names = {r[0] for r in conn.execute(
            "SELECT name FROM workflow_chains WHERE domain='cryo_em'"
        )}
        conn.close()
        assert "cryoem_standard_refinement" in names, "cryoem_standard_refinement not in DB"
        assert "cryoem_conformational_heterogeneity" in names, \
            "cryoem_conformational_heterogeneity not in DB"
        assert "cryoem_model_building" in names, "cryoem_model_building not in DB"
    finally:
        db.unlink(missing_ok=True)


def test_all_three_chains_present():
    """CRYOEM_CHAIN_TEMPLATES must contain all 3 chain names."""
    names = {c["name"] for c in CRYOEM_CHAIN_TEMPLATES}
    assert "cryoem_standard_refinement" in names
    assert "cryoem_conformational_heterogeneity" in names
    assert "cryoem_model_building" in names


def test_step_count():
    """Refinement chain has 5 steps; heterogeneity chain has 2 steps; model_building has 3."""
    by_name = {c["name"]: c for c in CRYOEM_CHAIN_TEMPLATES}

    refinement = by_name["cryoem_standard_refinement"]
    assert len(refinement["steps"]) == 5, (
        f"expected 5 steps in refinement chain, got {len(refinement['steps'])}"
    )

    heterogeneity = by_name["cryoem_conformational_heterogeneity"]
    assert len(heterogeneity["steps"]) == 2, (
        f"expected 2 steps in heterogeneity chain, got {len(heterogeneity['steps'])}"
    )

    model_building = by_name["cryoem_model_building"]
    assert len(model_building["steps"]) == 3, (
        f"expected 3 steps in model_building chain, got {len(model_building['steps'])}"
    )


def test_suggest_for_cryosparc_spa_returns_refinement_and_heterogeneity():
    """suggest_chains_for_run() with cryoSPARC SPA + .cs/.mrc must return refinement and heterogeneity."""
    matches = suggest_chains_for_run(
        "CryoSPARC Standard Single-Particle Analysis", ["cs", "mrc"]
    )
    names = [m["name"] for m in matches]
    assert "cryoem_standard_refinement" in names, (
        f"cryoem_standard_refinement not in suggestions: {names}"
    )
    assert "cryoem_conformational_heterogeneity" in names, (
        f"cryoem_conformational_heterogeneity not in suggestions: {names}"
    )


def test_suggest_for_local_refinement_returns_model_building():
    """suggest_chains_for_run() with local_refinement + .mrc must return model_building chain."""
    matches = suggest_chains_for_run("Local Refinement", ["mrc", "map"])
    names = [m["name"] for m in matches]
    assert "cryoem_model_building" in names, (
        f"cryoem_model_building not in suggestions for local_refinement: {names}"
    )


def test_suggest_for_unrelated_workflow_returns_empty():
    """suggest_chains_for_run() with an unrelated workflow must return []."""
    matches = suggest_chains_for_run("nf-core/rnaseq", ["tsv", "bam"])
    assert matches == [], f"expected no suggestions for rnaseq, got: {[m['name'] for m in matches]}"


def test_all_step_workflow_names_nonempty():
    """Every step in every chain must have a non-empty workflow_name."""
    for chain in CRYOEM_CHAIN_TEMPLATES:
        for step in chain["steps"]:
            assert step.get("workflow_name"), (
                f"Chain '{chain['name']}' step {step.get('order')} has empty workflow_name"
            )


def test_connections_reference_valid_step_orders():
    """For each connection, from_step and to_step must be within [1, len(steps)]."""
    for chain in CRYOEM_CHAIN_TEMPLATES:
        n_steps = len(chain["steps"])
        for conn in chain.get("connections", []):
            assert 1 <= conn["from_step"] <= n_steps, (
                f"Chain '{chain['name']}' connection from_step={conn['from_step']} "
                f"out of range [1, {n_steps}]"
            )
            assert 1 <= conn["to_step"] <= n_steps, (
                f"Chain '{chain['name']}' connection to_step={conn['to_step']} "
                f"out of range [1, {n_steps}]"
            )


# ── Main (standalone runner) ───────────────────────────────────────────────────

if __name__ == "__main__":
    tests = [
        test_register_cryoem_chains_upserts_to_db,
        test_all_three_chains_present,
        test_step_count,
        test_suggest_for_cryosparc_spa_returns_refinement_and_heterogeneity,
        test_suggest_for_local_refinement_returns_model_building,
        test_suggest_for_unrelated_workflow_returns_empty,
        test_all_step_workflow_names_nonempty,
        test_connections_reference_valid_step_orders,
    ]
    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
            passed += 1
        except Exception as exc:
            print(f"  FAIL  {t.__name__}: {exc}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    if failed:
        sys.exit(1)
