"""
L3 Connector offline schema tests — §4.1-4.3 of TEST_PLAN.md.

These tests validate the connector interface contracts without any outbound
network calls or heavy third-party dependencies.  They are designed to run in
the main backend CI (pytest.ini adds backend/lib to pythonpath, so
``from mcp import tools_manifest`` works).

Coverage:
  4.1 — Every connectors/<surface>/mcp-snippet.json is auto-discovered and
        structurally valid (mcpServers.biomate.{command,args,env}, a cred key).
  4.2 — VALID_SAMPLES in this file must not reference tools removed from the
        manifest.  Stale entries → fail immediately, before adapter regen.
  4.3 — Every required param in every tool must carry a 'description' field.
        Failing here catches gaps before any directory submission.

Run:
    cd backend && python -m pytest tests/test_connector_l3.py -v
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import List

import pytest

from mcp import tools_manifest as tm  # pytest.ini: pythonpath = lib

# ---------------------------------------------------------------------------
# Repo layout
# ---------------------------------------------------------------------------

# backend/tests/ → backend/ → repo root
REPO_ROOT = Path(__file__).resolve().parents[2]

# ---------------------------------------------------------------------------
# §4.2 reference: tool names that have known-good sample inputs.
# Update this dict when tools are added/removed from tools_manifest.py.
# ---------------------------------------------------------------------------

VALID_SAMPLES = {
    # Core workflow tools
    "biomate_session",
    "search_workflow",
    "run_workflow",
    "get_workflow_spec",
    "list_runs",
    "get_run",
    "watch_run",
    "cancel_run",
    # Output / results
    "export_report",
    "analyze_results",
    "preview_file",
    "upload_file",
    # Data retrieval
    "fetch_public_data",
    "browse_data",
    "query_database",
    "resolve_accession",
    "search_literature",
    # Utility
    "explain_error",
    "recall_memory",
}


# ---------------------------------------------------------------------------
# 4.1 — Surface adapter auto-discovery
# ---------------------------------------------------------------------------

def test_surface_adapters_auto_discovered_and_valid():
    """§4.1 — Every connectors/<surface>/mcp-snippet.json is valid.

    Adding a new surface adapter only requires dropping mcp-snippet.json in
    connectors/<surface>/ — this test covers it automatically.

    Validates per snippet:
      • valid JSON
      • mcpServers.biomate present
      • command, args, env keys present
      • env block contains at least one credential/token key
    """
    snippets = sorted((REPO_ROOT / "connectors").glob("*/mcp-snippet.json"))
    assert snippets, (
        "No mcp-snippet.json found under connectors/ — at least one surface "
        "adapter must exist for this suite to be meaningful."
    )
    for snippet_path in snippets:
        surface = snippet_path.parent.name
        try:
            cfg = json.loads(snippet_path.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"{surface}/mcp-snippet.json: invalid JSON: {exc}")

        assert "mcpServers" in cfg, f"{surface}: missing top-level 'mcpServers'"
        assert "biomate" in cfg["mcpServers"], (
            f"{surface}: mcpServers must have a 'biomate' entry"
        )
        biomate = cfg["mcpServers"]["biomate"]
        for key in ("command", "args", "env"):
            assert key in biomate, f"{surface}: mcpServers.biomate missing '{key}'"

        has_cred = any(
            k for k in biomate["env"] if "TOKEN" in k.upper() or "KEY" in k.upper()
        )
        assert has_cred, (
            f"{surface}: mcpServers.biomate.env has no credential key "
            "(need a key containing 'TOKEN' or 'KEY')"
        )


# ---------------------------------------------------------------------------
# 4.2 — VALID_SAMPLES stale-entry guard
# ---------------------------------------------------------------------------

def test_valid_samples_no_stale_entries():
    """§4.2 — VALID_SAMPLES must not reference tools removed from the manifest.

    When a tool is deleted from tools_manifest.py, this dict must be updated
    in the same commit.  A stale entry means adapter regeneration was missed.
    """
    known = {t.name for t in tm.TOOL_SCHEMAS}
    stale = set(VALID_SAMPLES) - known
    assert not stale, (
        f"VALID_SAMPLES references tools no longer in the manifest: {stale}. "
        "Remove the stale entries and regenerate any adapters that referenced "
        "the deleted tool."
    )


# ---------------------------------------------------------------------------
# 4.3 — Required params must have descriptions
# ---------------------------------------------------------------------------

def test_every_required_param_has_description():
    """§4.3 — Every param in a tool's required[] list must carry a description.

    Missing descriptions break SDK auto-documentation, Claude Skills inline
    display, and directory reviewer expectations.
    """
    failures: List[str] = []
    for t in tm.TOOL_SCHEMAS:
        props = t.input_schema.get("properties", {})
        required = t.input_schema.get("required", [])
        for param_name in required:
            desc = props.get(param_name, {}).get("description", "").strip()
            if not desc:
                failures.append(f"{t.name}.{param_name}")
    assert not failures, (
        f"Required params missing 'description': {failures}. "
        "Every required param must document its purpose."
    )
