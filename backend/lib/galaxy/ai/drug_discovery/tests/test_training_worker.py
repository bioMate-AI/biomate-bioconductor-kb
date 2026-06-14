"""B3 — per-mode worker dispatch + harness gating."""
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
    monkeypatch.setattr(rw, "ORG_RULES_DIR", tmp_path / "org_rules")
    monkeypatch.setattr(rw, "ORG_FEWSHOT_DIR", tmp_path / "org_fewshot")
    monkeypatch.setattr(rw, "HARNESS_WITNESS", tmp_path / "witness.json")
    monkeypatch.setattr(rw, "SIMULATED_TRAIN_SECONDS", 0.0)
    yield


def test_tick_on_empty_queue_returns_nothing():
    assert rw.tick(max_jobs=5) == []


def test_default_mode_is_prompt_rules():
    """A bare submit (no mode) defaults to prompt_rules and succeeds without
    needing edit pairs because the rule compile is cheap."""
    j = rj.submit(user_id="u1", org_id="acme")
    assert j.adaptation_mode == "prompt_rules"
    done = rw.tick(max_jobs=1)
    assert len(done) == 1
    assert done[0].status == "succeeded"
    assert "prompt_rules" in done[0].message
    # Should have written a rule YAML at the adapter_path
    out = rw.ORG_RULES_DIR / "acme.yaml"
    assert out.exists()
    assert done[0].adapter_path == str(out)


def test_few_shot_index_writes_placeholder():
    j = rj.submit(user_id="u1", org_id="acme", adaptation_mode="few_shot_index")
    rj.DPO_PAIRS_PATH.write_text(
        json.dumps({"meta": {"org_id": "acme"}, "chosen": "a", "rejected": "b"}) + "\n"
    )
    done = rw.tick(max_jobs=1)
    assert done[0].status == "succeeded"
    assert "few_shot_index" in done[0].message
    assert (rw.ORG_FEWSHOT_DIR / "acme.jsonl").exists()


def test_post_train_lora_refused_without_harness_witness():
    """GPU training MUST refuse to run until the cross-judge harness has
    shown local > frontier on the org's task mix. Witness absence ≡ refusal."""
    j = rj.submit(user_id="u1", org_id="acme", adaptation_mode="post_train_lora")
    done = rw.tick(max_jobs=1)
    assert len(done) == 1
    assert done[0].status == "failed"
    assert "harness_witness_missing" in done[0].message


def test_post_train_lora_runs_when_witness_present_and_pairs_present(tmp_path):
    rw.HARNESS_WITNESS.write_text(json.dumps({
        "local_macro": 0.62,
        "frontier_macro": 0.53,
        "ci_overlap": False,
    }))
    rj.DPO_PAIRS_PATH.write_text(
        json.dumps({"meta": {"org_id": "acme"}, "chosen": "a", "rejected": "b"}) + "\n" +
        json.dumps({"meta": {"org_id": "acme"}, "chosen": "c", "rejected": "d"}) + "\n"
    )
    j = rj.submit(user_id="u1", org_id="acme", adaptation_mode="post_train_lora")
    done = rw.tick(max_jobs=1)
    assert done[0].status == "succeeded"
    assert "regulatory_llm_v7_acme" in done[0].adapter_path


def test_post_train_lora_witness_present_but_no_pairs_fails():
    rw.HARNESS_WITNESS.write_text(json.dumps({"local_macro": 0.62, "frontier_macro": 0.53}))
    j = rj.submit(user_id="u1", org_id="acme", adaptation_mode="post_train_lora")
    done = rw.tick(max_jobs=1)
    assert done[0].status == "failed"
    assert "no_edit_pairs_available" in done[0].message


def test_unknown_mode_at_submit_raises():
    with pytest.raises(ValueError, match="invalid adaptation_mode"):
        rj.submit(user_id="u1", org_id="acme", adaptation_mode="quantum_teleport")


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
        raise RuntimeError("simulated handler crash")
    monkeypatch.setattr(rw, "_process_one", boom)
    done = rw.tick(max_jobs=1)
    assert done[0].status == "failed"
    assert "simulated handler crash" in done[0].message


def test_legacy_jsonl_row_backfills_mode(tmp_path, monkeypatch):
    """Job rows written before adaptation_mode existed should load and
    default to prompt_rules instead of raising TypeError on TrainingJob()."""
    legacy = {
        "job_id": "abc123def456789",
        "user_id": "u1",
        "org_id": "acme",
        "status": "queued",
        "submitted_at": 1000.0,
        "updated_at": 1000.0,
        "edit_pair_count": 0,
        "message": "",
        "adapter_path": "",
        # NO adaptation_mode field
    }
    rj.JOBS_PATH.parent.mkdir(parents=True, exist_ok=True)
    rj.JOBS_PATH.write_text(json.dumps(legacy) + "\n")
    jobs = rj.list_for_user("u1")
    assert len(jobs) == 1
    assert jobs[0].adaptation_mode == "prompt_rules"
