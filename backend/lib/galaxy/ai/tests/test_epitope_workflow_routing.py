"""Regression: Plan A queries must route to epitopeprediction, not mhcquant."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_search():
    mod_path = Path(__file__).resolve().parents[1] / "unified_workflow_search.py"
    spec = importlib.util.spec_from_file_location("uws", mod_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    backend = Path(__file__).resolve().parents[4]
    db = backend / "database" / "galaxy_ai_tools.db"
    if not db.is_file():
        db = backend / "galaxy_ai_tools.db"
    return mod.UnifiedWorkflowSearch(str(db))


PLAN_A_QUERY = """
ANDV Plan A vaccine immunoinformatics track.
Use workflow nfcore/epitopeprediction (Galaxy id 12700) — NOT mhcquant.
Please run nf-core epitopeprediction with tools = mhcnuggets, genome_reference = grch37.
""".strip()


def test_plan_a_routes_to_epitopeprediction_not_mhcquant():
    ws = _load_search()
    results = ws.search(PLAN_A_QUERY, limit=5)
    assert results, "expected at least one workflow match"
    top = results[0]
    assert "epitopeprediction" in top.name.lower(), f"top-1 was {top.name}"
    assert top.id == 12700
    names = [m.name.lower() for m in results[:5]]
    assert not any("mhcquant" in n for n in names), f"mhcquant should be filtered: {names}"


def test_explicit_slug_anchor_extraction():
    ws = _load_search()
    slug = ws._extract_explicit_pipeline_slug(PLAN_A_QUERY)
    assert slug == "epitopeprediction"
    assert ws._extract_negated_pipeline_slugs(PLAN_A_QUERY) == {"mhcquant"}
