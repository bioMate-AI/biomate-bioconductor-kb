"""Orphan catalog path self-heal + search filter (2026-11-13 Admet Pred id 14553).

Prefer executable=0 / search exclusion over retargeting an archived drug_discovery
path to a wrong-named live sibling. Durable: runs at schema init (gitignored DB).
"""
import sqlite3
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

# Avoid anaconda numpy SIGFPE on macOS `_mac_os_check` during optional embed import.
# The helpers under test do not need embeddings.
if "numpy" not in sys.modules:
    _np = types.ModuleType("numpy")
    _np.ndarray = type("ndarray", (), {})  # type: ignore[attr-defined]
    sys.modules["numpy"] = _np
if "sentence_transformers" not in sys.modules:
    sys.modules["sentence_transformers"] = types.ModuleType("sentence_transformers")

from galaxy.ai.unified_workflow_search import (  # noqa: E402
    UnifiedWorkflowSearch,
    _ORPHAN_PATH_HEAL_VERSION,
    _primary_nf_path_exists,
)


def test_primary_nf_path_exists_false_for_archived_segment():
    assert _primary_nf_path_exists(
        "biomni_workflows/_archived/drug_discovery/ADMET_pred/main.nf"
    ) is False


def test_primary_nf_path_exists_true_for_live_pharmacology_admet(tmp_path=None):
    # Real tree in this worktree.
    assert _primary_nf_path_exists(
        "nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf"
    ) is True
    assert _primary_nf_path_exists(
        "nextflow_nfcore/subworkflows/drug_discovery/ADMET_pred/main.nf"
    ) is False


def _seed_orphan_db(tmp_path: Path) -> Path:
    db = tmp_path / "wf.db"
    # Init full schema, then insert an orphan biomni row + a live sibling.
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    conn.execute(
        "INSERT INTO workflows(id,name,filename,description,domain,input_types,tags,"
        "tools_used,executable,source,format) VALUES "
        "(14553,'Admet Pred',"
        "'nextflow_nfcore/subworkflows/drug_discovery/ADMET_pred/main.nf',"
        "'ADMET prediction','drug_discovery','[]','[]','[]',1,'biomni_nextflow','nextflow')"
    )
    conn.execute(
        "INSERT INTO workflows(id,name,filename,description,domain,input_types,tags,"
        "tools_used,executable,source,format) VALUES "
        "(12826,'Predict ADMET Properties (AI)',"
        "'nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf',"
        "'ADMET AI','drug_discovery','[]','[]','[]',1,'biomni_nextflow','nextflow')"
    )
    # Force re-heal on next init.
    conn.execute("DELETE FROM ai_meta WHERE key='orphan_path_heal_version'")
    conn.commit()
    conn.close()
    return db


def test_self_heal_retires_orphan_admet_pred(tmp_path):
    db = _seed_orphan_db(tmp_path)
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    row = conn.execute("SELECT executable FROM workflows WHERE id=14553").fetchone()
    assert row and int(row[0]) == 0
    # Live pharmacology path must NOT be retired.
    live = conn.execute("SELECT executable FROM workflows WHERE id=12826").fetchone()
    assert live and int(live[0]) == 1
    v = conn.execute(
        "SELECT value FROM ai_meta WHERE key='orphan_path_heal_version'"
    ).fetchone()
    assert v and str(v[0]) == str(_ORPHAN_PATH_HEAL_VERSION)
    conn.close()


def test_orphan_ids_excluded_from_search_even_when_enforce_executable_off(tmp_path, monkeypatch):
    monkeypatch.setenv("BIOMATE_ENFORCE_EXECUTABLE", "0")
    db = _seed_orphan_db(tmp_path)
    s = UnifiedWorkflowSearch(db_path=db)
    orphans = s._orphan_catalog_ids()
    assert 14553 in orphans
    assert 12826 not in orphans
    # Scope filter drops orphans from a synthetic result list.
    class _M:
        def __init__(self, i): self.id = i
    filtered = s._apply_scope_filter([_M(14553), _M(12826)])
    assert [m.id for m in filtered] == [12826]


def test_indexer_stores_on_disk_folder_not_remapped_domain():
    src = (ROOT / "backend" / "scripts" / "index_all_workflows.py").read_text()
    assert "domain_dir.name" in src
    assert "never index archived" in src or "_archived" in src
    # Must not build filename from remapped `domain` alone for biomni nextflow.
    assert 'subworkflows/{domain_dir.name}/' in src or "subworkflows/{domain_dir.name}/" in src
