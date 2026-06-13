"""B3 — per-org retrain queue smoke."""
from __future__ import annotations
import pytest, json
from galaxy.ai.drug_discovery import regulatory_training_jobs as rj


@pytest.fixture(autouse=True)
def isolate_store(tmp_path, monkeypatch):
    """Redirect JSONL + DPO_PAIRS to a tmp dir per-test."""
    monkeypatch.setattr(rj, "JOBS_PATH", tmp_path / "training_jobs.jsonl")
    monkeypatch.setattr(rj, "DPO_PAIRS_PATH", tmp_path / "customer_pairs.jsonl")
    yield


def test_submit_returns_queued_job():
    j = rj.submit(user_id="u1", org_id="acme-bio")
    assert j.user_id == "u1"
    assert j.org_id == "acme-bio"
    assert j.status == "queued"
    assert j.job_id and len(j.job_id) >= 16


def test_submit_sanitises_org_id():
    j = rj.submit(user_id="u1", org_id="acme'bio$$inc!")
    assert j.org_id == "acmebioinc"


def test_submit_rejects_invalid_org_id():
    with pytest.raises(ValueError):
        rj.submit(user_id="u1", org_id="!!!")


def test_submit_rejects_empty_user():
    with pytest.raises(ValueError):
        rj.submit(user_id="", org_id="acme")


def test_list_for_user_newest_first():
    j1 = rj.submit(user_id="u1", org_id="acme")
    j2 = rj.submit(user_id="u1", org_id="acme")
    jobs = rj.list_for_user("u1")
    assert [j.job_id for j in jobs] == [j2.job_id, j1.job_id]


def test_list_filters_by_user():
    rj.submit(user_id="u1", org_id="acme")
    rj.submit(user_id="u2", org_id="acme")
    assert len(rj.list_for_user("u1")) == 1
    assert len(rj.list_for_user("u2")) == 1


def test_mark_status_updates_record():
    j = rj.submit(user_id="u1", org_id="acme")
    updated = rj.mark_status(j.job_id, "running", message="started")
    assert updated.status == "running"
    assert updated.message == "started"
    assert rj.get(j.job_id).status == "running"


def test_mark_status_invalid_rejected():
    j = rj.submit(user_id="u1", org_id="acme")
    with pytest.raises(ValueError):
        rj.mark_status(j.job_id, "exploded")


def test_mark_status_succeeded_carries_adapter_path():
    j = rj.submit(user_id="u1", org_id="acme")
    out = rj.mark_status(j.job_id, "succeeded", adapter_path="models/regulatory_llm_v7_acme/lora_adapter")
    assert out.adapter_path.endswith("acme/lora_adapter")


def test_get_unknown_returns_none():
    assert rj.get("does-not-exist") is None


def test_count_edit_pairs_zero_when_file_missing():
    assert rj.count_edit_pairs("acme") == 0


def test_count_edit_pairs_matches_org_and_global(tmp_path, monkeypatch):
    pairs = tmp_path / "customer_pairs.jsonl"
    pairs.write_text(
        json.dumps({"meta": {"org_id": "acme"}, "chosen": "a", "rejected": "b"}) + "\n" +
        json.dumps({"meta": {"org_id": "other"}, "chosen": "a", "rejected": "b"}) + "\n" +
        json.dumps({"chosen": "a", "rejected": "b"}) + "\n"
    )
    monkeypatch.setattr(rj, "DPO_PAIRS_PATH", pairs)
    assert rj.count_edit_pairs("acme") == 2
    assert rj.count_edit_pairs("other") == 2


def test_jsonl_round_trip_survives_restart(monkeypatch, tmp_path):
    monkeypatch.setattr(rj, "JOBS_PATH", tmp_path / "j.jsonl")
    j = rj.submit(user_id="u1", org_id="acme")
    rj.mark_status(j.job_id, "running")
    jobs = rj.list_for_user("u1")
    assert len(jobs) == 1
    assert jobs[0].status == "running"
