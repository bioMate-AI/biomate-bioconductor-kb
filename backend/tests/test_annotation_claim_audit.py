"""annotation_claim_audit: removal-only, verbatim, two-model, guarded by the original text.

Run: cd backend && PYTHONPATH=lib pytest tests/test_annotation_claim_audit.py -v
"""
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "backend" / "lib"))
from galaxy.ai.chain_composer import annotation_claim_audit as A  # noqa: E402

ANN = "label-free quantification LFQ OpenMS mzML MaxQuant output processing proteinGroups isobaric labeling TMT iTRAQ quantitative proteomics"


def _db(tmp_path, ann=ANN):
    db = tmp_path / "wf.db"
    c = sqlite3.connect(str(db))
    c.execute("CREATE TABLE workflows (name TEXT, source TEXT, description TEXT, input_kinds TEXT, annotation TEXT, executable INTEGER)")
    c.execute("INSERT INTO workflows VALUES ('lfq','nfcore','OpenMS LFQ from mzML','[\"raw_spectra\"]',?,1)", (ann,))
    c.commit(); c.close()
    return db


def test_propose_keeps_only_verbatim_phrases(tmp_path):
    llm = lambda _p: json.dumps({"remove": ["MaxQuant output processing", "TMT", "not in text"], "reason": "x"})
    r = A.propose(_db(tmp_path), llm, workers=1)[0]
    assert r["remove"] == ["MaxQuant output processing", "TMT"] and r["dropped_nonverbatim"] == 1


def test_verify_applies_only_confirmed_phrases():
    p = {"name": "lfq", "description": "", "kinds": "[]", "annotation": ANN, "remove": ["TMT", "OpenMS"]}
    llm = lambda _p: json.dumps({"confirm": {"TMT": True, "OpenMS": False}})
    assert A.verify([p], llm, workers=1)[0]["confirmed"] == ["TMT"]


def test_cleaned_removes_phrases_and_collapses_space():
    out = A.cleaned(ANN, ["MaxQuant output processing", "proteinGroups", "TMT"])
    assert "MaxQuant" not in out and "TMT" not in out and "  " not in out
    assert out.startswith("label-free quantification") and "iTRAQ" in out


def test_apply_is_guarded_by_original_text(tmp_path):
    db = _db(tmp_path)
    v = {"name": "lfq", "annotation": ANN, "confirmed": ["TMT"]}
    assert A.apply(db, [v]) == 1
    assert A.apply(db, [v]) == 0  # annotation changed since the audit → left alone
    assert "TMT" not in sqlite3.connect(str(db)).execute("select annotation from workflows").fetchone()[0]


def test_failed_llm_proposes_nothing(tmp_path):
    r = A.propose(_db(tmp_path), lambda _p: "garbage", workers=1)[0]
    assert r["remove"] is None and r["status"] == "llm_failed"
