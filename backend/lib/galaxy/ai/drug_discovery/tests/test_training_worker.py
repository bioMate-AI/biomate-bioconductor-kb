"""B3 — stub worker smoke."""
from __future__ import annotations
import json, pytest
from galaxy.ai.drug_discovery import (
    regulatory_training_jobs as rj,
    regulatory_training_worker as rw,
)


@pytest.fixture(autouse=True)
def fast_worker_and_isolate(tmp_path, monkeypatch):
    monkeypatch.setattr(rj, "JOBS_PATH", tmp_path / "training_jobs.jsonl")
    monkeypatch.setattr(rj, "DPO_PAIRS_PATH", tmp_path / "customer_pairs.jsonl")
    monkeypatch.setattr(rw, "SIMULATED_TRAIN_SECONDS", 0.0)
    yield


def test_tick_on_empty_queue_returns_nothing():
    assert rw.tick(max_jobs=5) == []


def test_tick_succeeds_when_pairs_present():
    rj.DPO_PAIRS_PATH.write_text(
        json.dumps({"meta": {"org_id": "acme"}, "chosen": "a", "rejected": "b"}) + "\n" +
        json.dumps({"meta": {"org_id": "acme"}, "chosen": "c", "rejected": "d"}) + "\n"
    )
    j = rj.submit(user_id="u1", org_id="acme")
    done = rw.tick(max_jobs=1)
    assert len(done) == 1
    assert done[0].status == "succeeded"
    assert "regulatory_llm_v7_acme" in done[0].adapter_path
    assert done[0].adapter_path.endswith("lora_adapter")
    assert rj.get(j.job_id).status == "succeeded"


def test_tick_fails_when_no_pairs():
    j = rj.submit(user_id="u1", org_id="acme")
    done = rw.tick(max_jobs=1)
    assert len(done) == 1
    assert done[0].status == "failed"
    assert "no_edit_pairs_available" in done[0].message


def test_tick_processes_oldest_first():
    j1 = rj.submit(user_id="u1", org_id="acme")
    j2 = rj.submit(user_id="u1", org_id="acme")
    done = rw.tick(max_jobs=1)
    assert done[0].job_id == j1.job_id
    assert rj.get(j2.job_id).status == "queued"


def test_tick_respects_max_jobs():
    for _ in range(5):
        rj.submit(user_id="u1", org_id="acme")
    done = rw.tick(max_jobs=3)
    assert len(done) == 3
    queued = [j for j in rj.list_for_user("u1") if j.status == "queued"]
    assert len(queued) == 2


def test_worker_exception_marks_failed(monkeypatch):
    rj.submit(user_id="u1", org_id="acme")
    def boom(*args, **kwargs):
        raise RuntimeError("simulated SFT crash")
    monkeypatch.setattr(rw, "_process_one", boom)
    done = rw.tick(max_jobs=1)
    assert len(done) == 1
    assert done[0].status == "failed"
    assert "simulated SFT crash" in done[0].message
