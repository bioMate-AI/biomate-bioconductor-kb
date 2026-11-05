"""description_code_audit: description clauses contradicting the workflow's own code are removed (verbatim, guarded).

Run: cd backend && PYTHONPATH=lib pytest tests/test_description_code_audit.py -v
"""
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "backend" / "lib"))
from galaxy.ai.chain_composer import description_code_audit as D  # noqa: E402

DESC = ("Annotate and filter somatic mutations from a pre-existing VCF. NOTE: it does NOT perform variant calling. "
        "Generates a filtered variant report.")


def _db(tmp_path):
    db = tmp_path / "wf.db"
    c = sqlite3.connect(str(db))
    c.execute("CREATE TABLE workflows (id INTEGER PRIMARY KEY, name TEXT, source TEXT, description TEXT, input_types TEXT, filename TEXT, executable INTEGER)")
    c.execute("INSERT INTO workflows VALUES (3,'somatic','biomni_nextflow',?,'[\"tumor_bam\"]','x/main.nf',1)", (DESC,))
    c.commit(); c.close()
    return db


def test_only_verbatim_clauses_are_kept(tmp_path, monkeypatch):
    db = _db(tmp_path)
    monkeypatch.setattr(D, "_code_path", lambda fn: tmp_path / "main.nf")
    (tmp_path / "main.nf").write_text("params.tumor_bam = null\nprocess X { script: 'gatk Mutect2 -I $params.tumor_bam' }\n")
    llm = lambda _p: json.dumps({"contradictions": [{"clause": "it does NOT perform variant calling.", "code_evidence": "gatk Mutect2"},
                                                     {"clause": "paraphrased, not in the text", "code_evidence": "x"}]})
    r = D.propose(db, llm, workers=1)[0]
    assert [x["clause"] for x in r["contradictions"]] == ["it does NOT perform variant calling."]
    assert r["dropped_nonverbatim"] == 1


def test_nfcore_display_stubs_are_skipped(tmp_path, monkeypatch):
    db = _db(tmp_path)
    c = sqlite3.connect(str(db)); c.execute("UPDATE workflows SET source='nfcore'"); c.commit(); c.close()
    monkeypatch.setattr(D, "_code_path", lambda fn: tmp_path / "main.nf")
    (tmp_path / "main.nf").write_text("params.input = null\n")
    assert D.propose(db, lambda _p: "{}", workers=1) == []


def test_apply_removes_confirmed_clause_guarded_by_original(tmp_path, monkeypatch):
    db = _db(tmp_path)
    monkeypatch.setattr(D, "assert_fts_consistent", lambda _db: None)
    v = {"id": 3, "description": DESC, "confirmed": ["NOTE: it does NOT perform variant calling."]}
    assert D.apply(db, [v]) == 1
    assert "does NOT perform" not in sqlite3.connect(str(db)).execute("select description from workflows").fetchone()[0]
    assert D.apply(db, [v]) == 0  # description changed since the audit → untouched
