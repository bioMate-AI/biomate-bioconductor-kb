"""
Tests for cryoem_chain_templates.py (Track A).

Tests:
  A1: register_cryoem_chains() writes 3 chains to a test DB with domain='cryo_em'
  A2: All steps in each chain resolve to workflow names that exist in the prod DB
  A3: suggest_chains_for_run() returns correct chains for cryoSPARC SPA trigger
  A4: suggest_chains_for_run() returns model_building for post-refinement trigger
  A5: suggest_chains_for_run() returns empty list for an unrelated workflow
  A6: Module import is clean (no syntax error, correct exports)
"""

from __future__ import annotations

import json
import sqlite3
import tempfile
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

_REPO_ROOT = Path(__file__).resolve().parents[5]
_AI_DIR = Path(__file__).resolve().parents[1]
_PROD_DB = _REPO_ROOT / "database" / "galaxy_ai_tools.db"

# ---------------------------------------------------------------------------
# A6: module import smoke test (runs before everything else)
# ---------------------------------------------------------------------------

def _import_module():
    """Import cryoem_chain_templates; skip if DB is not accessible."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "cryoem_chain_templates", _AI_DIR / "cryoem_chain_templates.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


try:
    _mod = _import_module()
    CRYOEM_CHAIN_TEMPLATES = _mod.CRYOEM_CHAIN_TEMPLATES
    register_cryoem_chains = _mod.register_cryoem_chains
    suggest_chains_for_run = _mod.suggest_chains_for_run
    _IMPORT_OK = True
except Exception as _import_err:
    _IMPORT_OK = False
    _IMPORT_ERROR = str(_import_err)


def test_a6_module_imports_cleanly():
    """A6 — cryoem_chain_templates.py must import without error."""
    assert _IMPORT_OK, f"Module import failed: {_IMPORT_ERROR if not _IMPORT_OK else ''}"


# ---------------------------------------------------------------------------
# All remaining tests require a clean import
# ---------------------------------------------------------------------------

pytestmark = pytest.mark.skipif(
    not _IMPORT_OK,
    reason="cryoem_chain_templates.py did not import cleanly"
)


# ---------------------------------------------------------------------------
# A1: register_cryoem_chains writes 3 chains to an isolated test DB
# ---------------------------------------------------------------------------

def _make_test_db() -> Path:
    """Create a minimal workflow_chains table in a fresh temp file."""
    tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    conn = sqlite3.connect(tmp.name)
    conn.execute("""
        CREATE TABLE workflow_chains (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            display_name TEXT,
            domain TEXT,
            description TEXT,
            steps TEXT,
            connections TEXT,
            required_inputs TEXT,
            expected_outputs TEXT,
            example_queries TEXT,
            tags TEXT,
            source TEXT,
            usage_count INTEGER DEFAULT 0,
            success_rate REAL DEFAULT 0.0,
            created_at TEXT,
            updated_at TEXT
        )
    """)
    conn.commit()
    conn.close()
    return Path(tmp.name)


def test_a1_register_cryoem_chains_upserts_three():
    """A1 — register_cryoem_chains() inserts 3 chains with domain='cryo_em'."""
    test_db = _make_test_db()
    try:
        n = register_cryoem_chains(db_path=test_db)
        assert n == 3, f"Expected 3 upserted, got {n}"

        conn = sqlite3.connect(str(test_db))
        names = {r[0] for r in conn.execute(
            "SELECT name FROM workflow_chains WHERE domain='cryo_em'"
        )}
        conn.close()

        assert "cryoem_standard_refinement" in names, \
            f"cryoem_standard_refinement missing; got: {names}"
        assert "cryoem_conformational_heterogeneity" in names, \
            f"cryoem_conformational_heterogeneity missing; got: {names}"
        assert "cryoem_model_building" in names, \
            f"cryoem_model_building missing; got: {names}"
    finally:
        test_db.unlink(missing_ok=True)


def test_a1_register_is_idempotent():
    """A1 — calling register_cryoem_chains() twice keeps exactly 3 chains (upsert)."""
    test_db = _make_test_db()
    try:
        register_cryoem_chains(db_path=test_db)
        register_cryoem_chains(db_path=test_db)

        conn = sqlite3.connect(str(test_db))
        count = conn.execute("SELECT COUNT(*) FROM workflow_chains").fetchone()[0]
        conn.close()
        assert count == 3, f"Expected 3 chains after double-register, got {count}"
    finally:
        test_db.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# A2: step workflow_names must exist in the production DB
# ---------------------------------------------------------------------------

@pytest.mark.skipif(
    not _PROD_DB.is_file(),
    reason="Production DB not found — skipping in-DB step validation"
)
def test_a2_steps_resolve_to_db_workflows():
    """A2 — Every step.workflow_name in every chain must be in the workflows table."""
    conn = sqlite3.connect(str(_PROD_DB))
    wf_names_lower = {
        r[0].lower()
        for r in conn.execute("SELECT name FROM workflows")
    }
    conn.close()

    missing = []
    for chain in CRYOEM_CHAIN_TEMPLATES:
        for step in chain.get("steps", []):
            wf = step.get("workflow_name", "")
            if wf.lower() not in wf_names_lower:
                missing.append(f"{chain['name']}: step.workflow_name='{wf}'")

    assert not missing, (
        "The following chain step workflow_names are NOT in the workflows table:\n"
        + "\n".join(f"  {m}" for m in missing)
    )


# ---------------------------------------------------------------------------
# A3: suggest_chains_for_run — cryoSPARC SPA trigger
# ---------------------------------------------------------------------------

def test_a3_suggest_chains_for_cryosparc_spa():
    """A3 — cryoSPARC SPA + cs/mrc outputs suggest refinement + heterogeneity chains."""
    matches = suggest_chains_for_run(
        "CryoSPARC Standard Single-Particle Analysis", ["cs", "mrc"]
    )
    names = [m["name"] for m in matches]
    assert "cryoem_standard_refinement" in names, \
        f"cryoem_standard_refinement not in matches: {names}"
    assert "cryoem_conformational_heterogeneity" in names, \
        f"cryoem_conformational_heterogeneity not in matches: {names}"


def test_a3_top_two_suggestions_for_cryosparc():
    """A3 — The two highest-scoring matches for cryoSPARC are the correct chains."""
    matches = suggest_chains_for_run(
        "cryosparc_standard_spa", ["cs", "mrc"]
    )
    # model_building should have lower score (ext match only, no wf match)
    top_two = {m["name"] for m in matches[:2]}
    assert top_two == {"cryoem_standard_refinement", "cryoem_conformational_heterogeneity"}, \
        f"Unexpected top-2 chains: {top_two}"


def test_a3_lowercase_workflow_name_matches():
    """A3 — suggest_chains_for_run handles lowercase workflow names."""
    matches = suggest_chains_for_run("cryosparc standard single-particle analysis", ["cs"])
    names = [m["name"] for m in matches]
    assert "cryoem_standard_refinement" in names


# ---------------------------------------------------------------------------
# A4: suggest_chains_for_run — model building trigger (post-refinement)
# ---------------------------------------------------------------------------

def test_a4_suggest_model_building_after_local_refinement():
    """A4 — Local Refinement + .mrc outputs trigger cryoem_model_building."""
    matches = suggest_chains_for_run("Local Refinement", ["mrc", "map"])
    names = [m["name"] for m in matches]
    assert "cryoem_model_building" in names, \
        f"cryoem_model_building not in matches: {names}"


def test_a4_suggest_model_building_after_focused_refinement():
    """A4 — Focused Refinement Pipeline + .mrc outputs trigger cryoem_model_building."""
    matches = suggest_chains_for_run("Focused Refinement Pipeline", ["mrc"])
    names = [m["name"] for m in matches]
    assert "cryoem_model_building" in names, \
        f"cryoem_model_building not in matches: {names}"


# ---------------------------------------------------------------------------
# A5: No false-positive suggestions for unrelated workflows
# ---------------------------------------------------------------------------

def test_a5_no_suggestion_for_rnaseq():
    """A5 — nf-core/rnaseq does not trigger any cryo-EM chain."""
    matches = suggest_chains_for_run("nf-core/rnaseq", ["tsv", "bam", "fastq"])
    assert matches == [], f"Unexpected cryo-EM chain suggestions for rnaseq: {[m['name'] for m in matches]}"


def test_a5_no_suggestion_for_sarek():
    """A5 — nf-core/sarek does not trigger any cryo-EM chain."""
    matches = suggest_chains_for_run("nf-core/sarek", ["vcf", "vcf.gz", "bam"])
    assert matches == [], f"Unexpected cryo-EM chain suggestions for sarek: {[m['name'] for m in matches]}"


def test_a5_no_suggestion_for_chipseq():
    """A5 — nf-core/chipseq does not trigger any cryo-EM chain."""
    matches = suggest_chains_for_run("chipseq", ["bed", "narrowPeak", "broadPeak"])
    assert matches == [], f"Unexpected cryo-EM chain suggestions for chipseq: {[m['name'] for m in matches]}"


# ---------------------------------------------------------------------------
# Template structure sanity checks
# ---------------------------------------------------------------------------

def test_chain_templates_have_required_keys():
    """Every chain template must have: name, display_name, domain, steps, connections."""
    required_keys = {"name", "display_name", "domain", "steps", "connections",
                     "required_inputs", "trigger_on_workflows", "trigger_on_output_extensions"}
    for tpl in CRYOEM_CHAIN_TEMPLATES:
        missing = required_keys - set(tpl.keys())
        assert not missing, f"Chain '{tpl.get('name')}' missing keys: {missing}"


def test_chain_steps_are_ordered():
    """Steps in each chain must have sequential 1-based 'order' values."""
    for tpl in CRYOEM_CHAIN_TEMPLATES:
        orders = [s.get("order") for s in tpl.get("steps", [])]
        expected = list(range(1, len(orders) + 1))
        assert orders == expected, \
            f"Chain '{tpl['name']}' step orders {orders} != {expected}"


def test_chain_connections_reference_valid_steps():
    """Connection from_step/to_step values must be in range [1, len(steps)]."""
    for tpl in CRYOEM_CHAIN_TEMPLATES:
        n_steps = len(tpl.get("steps", []))
        for conn in tpl.get("connections", []):
            assert 1 <= conn["from_step"] <= n_steps, \
                f"Chain '{tpl['name']}' connection from_step={conn['from_step']} out of range"
            assert 1 <= conn["to_step"] <= n_steps, \
                f"Chain '{tpl['name']}' connection to_step={conn['to_step']} out of range"


if __name__ == "__main__":
    # Quick standalone run (no pytest required)
    import sys
    tests = [
        test_a6_module_imports_cleanly,
        test_a1_register_cryoem_chains_upserts_three,
        test_a1_register_is_idempotent,
        test_a3_suggest_chains_for_cryosparc_spa,
        test_a3_top_two_suggestions_for_cryosparc,
        test_a3_lowercase_workflow_name_matches,
        test_a4_suggest_model_building_after_local_refinement,
        test_a4_suggest_model_building_after_focused_refinement,
        test_a5_no_suggestion_for_rnaseq,
        test_a5_no_suggestion_for_sarek,
        test_a5_no_suggestion_for_chipseq,
        test_chain_templates_have_required_keys,
        test_chain_steps_are_ordered,
        test_chain_connections_reference_valid_steps,
    ]
    # a2 requires prod DB — skip here
    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            print(f"  PASS  {t.__name__}")
            passed += 1
        except Exception as e:
            print(f"  FAIL  {t.__name__}: {e}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
