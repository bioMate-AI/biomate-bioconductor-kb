"""B3 upstream — pair recorder smoke + round-trip with worker."""
from __future__ import annotations
import json, pytest
from galaxy.ai.drug_discovery import regulatory_pair_recorder as rec
from galaxy.ai.drug_discovery import regulatory_training_jobs as rj
from galaxy.ai.drug_discovery import regulatory_training_worker as rw
from galaxy.ai.drug_discovery.org_rule_compiler import compile_org_rules


@pytest.fixture(autouse=True)
def isolate_paths(tmp_path, monkeypatch):
    """Redirect both the recorder + worker to a tmp customer_pairs.jsonl."""
    pairs = tmp_path / "customer_pairs.jsonl"
    monkeypatch.setattr(rec, "PAIRS_PATH", pairs)
    # The worker reads via rj.DPO_PAIRS_PATH; align it.
    monkeypatch.setattr(rj, "DPO_PAIRS_PATH", pairs)
    monkeypatch.setattr(rj, "JOBS_PATH", tmp_path / "training_jobs.jsonl")
    monkeypatch.setattr(rw, "SIMULATED_TRAIN_SECONDS", 0.0)
    monkeypatch.setattr(rw, "ORG_RULES_DIR", tmp_path / "org_rules")
    yield


def test_record_pair_writes_row():
    row = rec.record_pair(
        user_id="u1", org_id="acme",
        chosen="Per ICH M3(R2) the model is fit for purpose.",
        rejected="The model works.",
        section_type="pbpk",
    )
    assert row["meta"]["org_id"] == "acme"
    assert row["meta"]["section_type"] == "pbpk"
    assert "row_id" in row["meta"]
    # Persisted to disk
    lines = rec.PAIRS_PATH.read_text().splitlines()
    assert len(lines) == 1
    reloaded = json.loads(lines[0])
    assert reloaded["chosen"].startswith("Per ICH M3(R2)")


def test_record_pair_sanitises_org_id():
    row = rec.record_pair(
        user_id="u1", org_id="acme'inc!@#",
        chosen="a", rejected="b",
    )
    assert row["meta"]["org_id"] == "acmeinc"


def test_record_pair_rejects_invalid_org_id():
    with pytest.raises(ValueError, match="invalid org_id"):
        rec.record_pair(user_id="u1", org_id="!!!", chosen="a", rejected="b")


def test_record_pair_rejects_empty_user():
    with pytest.raises(ValueError, match="user_id required"):
        rec.record_pair(user_id="", org_id="acme", chosen="a", rejected="b")


def test_record_pair_rejects_both_sides_empty():
    with pytest.raises(ValueError, match="at least one"):
        rec.record_pair(user_id="u1", org_id="acme", chosen="", rejected="")


def test_record_pair_truncates_runaway_input():
    big = "x" * 50000
    row = rec.record_pair(
        user_id="u1", org_id="acme",
        chosen=big, rejected="ok",
    )
    assert len(row["chosen"]) == 8000


def test_record_pair_appends_does_not_overwrite():
    rec.record_pair(user_id="u1", org_id="acme", chosen="first", rejected="x")
    rec.record_pair(user_id="u1", org_id="acme", chosen="second", rejected="y")
    rec.record_pair(user_id="u1", org_id="acme", chosen="third", rejected="z")
    lines = rec.PAIRS_PATH.read_text().splitlines()
    assert len(lines) == 3


def test_count_for_org_matches_org_and_global():
    # Org-tagged + a global (untagged) row
    rec.record_pair(user_id="u1", org_id="acme", chosen="a", rejected="b")
    rec.record_pair(user_id="u1", org_id="other", chosen="c", rejected="d")
    # Manually drop an untagged row (recorder always tags, so we write it raw)
    with rec.PAIRS_PATH.open("a") as f:
        f.write(json.dumps({"chosen": "global", "rejected": "x", "meta": {}}) + "\n")
    assert rec.count_for_org("acme") == 2     # acme + untagged
    assert rec.count_for_org("other") == 2    # other + untagged
    assert rec.count_for_org("unknown") == 1  # only untagged


def test_count_for_org_missing_file_returns_zero(tmp_path, monkeypatch):
    monkeypatch.setattr(rec, "PAIRS_PATH", tmp_path / "missing.jsonl")
    assert rec.count_for_org("acme") == 0


def test_meta_extra_merged():
    row = rec.record_pair(
        user_id="u1", org_id="acme",
        chosen="a", rejected="b",
        meta_extra={"campaign_id": "BM-0042", "noael_mg_per_kg": 6.0},
    )
    assert row["meta"]["campaign_id"] == "BM-0042"
    assert row["meta"]["noael_mg_per_kg"] == 6.0
    # Core meta keys still present
    assert row["meta"]["org_id"] == "acme"


def test_full_round_trip_recorder_to_worker_to_compiler():
    """The big integration: a pair recorded here is visible to the worker
    via count_edit_pairs, and a prompt_rules tick consumes it into a
    real per-org rule pack."""
    rec.record_pair(
        user_id="u1", org_id="acme",
        chosen="PBPK qualification met EMA/CHMP/EWP/37498/2011 within-2-fold criterion.",
        rejected="PBPK acceptable.",
        section_type="pbpk",
    )
    rec.record_pair(
        user_id="u1", org_id="acme",
        chosen="Per ICH M3(R2) the model is fit for purpose.",
        rejected="Model works.",
        section_type="pbpk",
    )
    # Worker queue picks up the count from the same JSONL
    assert rj.count_edit_pairs("acme") == 2

    # Submit + tick → worker compiles the rule pack
    job = rj.submit(user_id="u1", org_id="acme")
    done = rw.tick(max_jobs=1)
    assert len(done) == 1
    assert done[0].status == "succeeded"

    # The pack must reflect what we just recorded
    pack = compile_org_rules(rec.PAIRS_PATH, "acme")
    assert pack["pairs_observed"] == 2
    cits = pack["preferred_citations"]
    assert any("EMA/CHMP/EWP/37498/2011" in c for c in cits)
