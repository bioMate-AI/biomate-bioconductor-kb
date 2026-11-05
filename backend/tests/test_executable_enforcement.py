"""executable=0 rows are not routed (the flag was stored but never enforced), and placeholder code is marked so.

Run: cd backend && PYTHONPATH=lib pytest tests/test_executable_enforcement.py -v
"""
import sqlite3
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "backend" / "lib"))
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.chain_composer import placeholder_audit as P  # noqa: E402


def _search(tmp_path):
    s = UnifiedWorkflowSearch(db_path=tmp_path / "wf.db")
    c = sqlite3.connect(str(tmp_path / "wf.db"))
    c.execute("INSERT INTO workflows(id, name, filename, workflow_json, executable) VALUES (1,'ok','a.nf','{}',1)")
    c.execute("INSERT INTO workflows(id, name, filename, workflow_json, executable) VALUES (2,'off','b.nf','{}',0)")
    c.commit(); c.close()
    s._non_exec_cache = None
    return s


def test_non_executable_rows_are_dropped_from_results_and_single_lookups(tmp_path, monkeypatch):
    monkeypatch.setenv("BIOMATE_ENFORCE_EXECUTABLE", "1")
    s = _search(tmp_path)
    ms = [SimpleNamespace(id=1, name="ok", filename="a.nf"), SimpleNamespace(id=2, name="off", filename="b.nf")]
    assert [m.id for m in s._apply_scope_filter(ms)] == [1]
    assert s._executable_or_none(ms[1]) is None and s._executable_or_none(ms[0]) is ms[0]


def test_enforcement_is_off_unless_enabled(tmp_path, monkeypatch):
    s = _search(tmp_path)
    monkeypatch.delenv("BIOMATE_ENFORCE_EXECUTABLE", raising=False)
    ms = [SimpleNamespace(id=2, name="off", filename="b.nf")]
    assert [m.id for m in s._apply_scope_filter(ms)] == [2]


def test_placeholder_markers_are_the_wrappers_own_words():
    assert P.PLACEHOLDER_MARKERS.search("'''Web search placeholder - actual implementation requires API access.")
    assert P.PLACEHOLDER_MARKERS.search("ERROR: x is a wet-lab bench procedure with no compute equivalent")
    assert not P.PLACEHOLDER_MARKERS.search("ERROR: requires real input/tool (gatk Mutect2); refusing to emit fabricated results")
