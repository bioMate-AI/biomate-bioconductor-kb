"""Regression: ANDV inhibitor chained E2E queries must route to the named workflow."""

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


DOCKING_CHAINED_QUERY = """
ANDV inhibitor chained UI test — step 4 AutoDock Vina docking.
Use top pocket from step 1 for the docking box when available. pdb_input = 1IEP.
Show AutoDock Vina workflow card.
""".strip()

POCKET_QUERY = """
ANDV inhibitor chained UI test — step 1 pocket detection and druggability.
pdb_input = 1IEP, min_druggability = 0.35, min_volume = 200.
Show the workflow card so I can Run.
""".strip()


def test_inh_c4_docking_routes_to_autodock_vina_not_structure_prediction():
    ws = _load_search()
    results = ws.search(DOCKING_CHAINED_QUERY, limit=5)
    assert results, "expected at least one workflow match"
    top = results[0]
    assert top.id in (12824, 10773), f"top-1 was id={top.id} name={top.name!r}"
    assert "autodock" in top.name.lower() and "vina" in top.name.lower()
    names = [m.name.lower() for m in results[:3]]
    assert not names[0].startswith("structure prediction"), f"wrong top hit: {names}"


def test_inh_c4_biomni_anchor_from_autodock_vina_phrase():
    ws = _load_search()
    import sqlite3

    conn = sqlite3.connect(str(ws.db_path))
    try:
        anchor = ws._extract_biomni_subworkflow_anchor(
            "Show AutoDock Vina workflow card with Run button.", conn.cursor()
        )
    finally:
        conn.close()
    assert anchor in ("docking_autodock_vina", "autodock_vina", "autodock")


def test_inh_c1_pocket_routes_to_fpocket_druggability():
    ws = _load_search()
    results = ws.search(POCKET_QUERY, limit=5)
    assert results, "expected at least one workflow match"
    top = results[0]
    assert "pocket" in top.name.lower() or "druggability" in top.name.lower()
