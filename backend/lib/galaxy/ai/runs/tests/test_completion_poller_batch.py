"""Tests for the CompletionPoller AWS Batch-terminal branch (2026-09-23).

The poller must finalize a run whose local Nextflow driver never fired its
completion callback (the 282-stuck-run bug) by asking AWS Batch directly.
boto3 is mocked; these verify the policy only.
"""

import time
from unittest.mock import MagicMock, patch

from galaxy.ai.runs.run_state_store import InMemoryRunStateStore
from galaxy.ai.runs.completion_poller import CompletionPoller

_JOB = "11111111-1111-1111-1111-111111111111"


def _batch_client(statuses):
    c = MagicMock()
    c.describe_jobs.return_value = {"jobs": [{"status": s} for s in statuses]}
    return c


def _run(started_ago: float, ids=None):
    # is_batch: these exercise the Batch branch. Without it, a run with no recorded PID is
    # finalized as a local staging orphan (completion_poller, 2026-10-05) before Batch is asked.
    r = {"status": "running", "outdir": "/tmp/x", "started_at": time.time() - started_ago, "is_batch": True}
    if ids is not None:
        r["batch_job_ids"] = ids
    return r


def test_batch_all_succeeded_triggers_completion():
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(
        store,
        lambda rid, rec: calls.append((rid, rec.get("batch_terminal_status"))),
        batch_check_age_s=300.0,
    )
    store.set_run("r1", _run(400, ids=[_JOB]))  # no set_pid → PID unknown → batch branch
    with patch("boto3.client", return_value=_batch_client(["SUCCEEDED"])):
        triggered = poller.tick_once()
    assert triggered == 1
    assert calls == [("r1", "succeeded")]
    assert store.get_run("r1").get("batch_terminal_status") == "succeeded"


def test_batch_any_failed_triggers_failed():
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(
        store,
        lambda rid, rec: calls.append((rid, rec.get("batch_terminal_status"))),
        batch_check_age_s=300.0,
    )
    store.set_run("r1", _run(400, ids=[_JOB, _JOB]))
    with patch("boto3.client", return_value=_batch_client(["SUCCEEDED", "FAILED"])):
        triggered = poller.tick_once()
    assert triggered == 1
    assert calls == [("r1", "failed")]


def test_batch_still_running_does_not_trigger():
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(store, lambda rid, rec: calls.append(rid), batch_check_age_s=300.0)
    store.set_run("r1", _run(400, ids=[_JOB]))
    with patch("boto3.client", return_value=_batch_client(["SUCCEEDED", "RUNNING"])):
        triggered = poller.tick_once()
    assert triggered == 0
    assert calls == []


def test_young_run_not_checked_against_batch():
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(store, lambda rid, rec: calls.append(rid), batch_check_age_s=300.0)
    store.set_run("r1", _run(30, ids=[_JOB]))  # younger than batch_check_age
    with patch("boto3.client", return_value=_batch_client(["SUCCEEDED"])) as m:
        triggered = poller.tick_once()
    assert triggered == 0
    m.assert_not_called()


def test_no_batch_ids_and_no_local_log_does_not_trigger(tmp_path, monkeypatch):
    monkeypatch.setenv("NEXTFLOW_WORK_DIR", str(tmp_path))  # no .nextflow.log there
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(store, lambda rid, rec: calls.append(rid), batch_check_age_s=300.0)
    store.set_run("r1", _run(400))  # no ids, no log
    with patch("boto3.client", return_value=_batch_client(["SUCCEEDED"])) as m:
        triggered = poller.tick_once()
    assert triggered == 0
    assert calls == []
    m.assert_not_called()


def test_batch_terminal_but_head_alive_mid_pipeline_does_not_trigger():
    # Between phases every SUBMITTED job can be terminal while the Nextflow head is still
    # running and about to submit more (rnaseq/mnaseseq/slamseq were finalized "succeeded"
    # mid-pipeline on 2026-11-06).
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(store, lambda rid, rec: calls.append(rid), batch_check_age_s=300.0)
    store.set_run("r1", _run(400, ids=[_JOB]))
    with patch("boto3.client", return_value=_batch_client(["SUCCEEDED"])), \
         patch.object(CompletionPoller, "_nextflow_head_alive", staticmethod(lambda rid, pid=None: True)), \
         patch.object(CompletionPoller, "_nextflow_log_ended", staticmethod(lambda rid: False)):
        assert poller.tick_once() == 0
    assert calls == []


def test_head_alive_after_log_end_finalizes_without_batch_verdict():
    store = InMemoryRunStateStore()
    calls = []
    poller = CompletionPoller(
        store, lambda rid, rec: calls.append((rid, rec.get("batch_terminal_status"))), batch_check_age_s=300.0)
    store.set_run("r1", _run(400, ids=[_JOB, _JOB]))
    with patch("boto3.client", return_value=_batch_client(["FAILED", "SUCCEEDED"])), \
         patch.object(CompletionPoller, "_nextflow_head_alive", staticmethod(lambda rid, pid=None: True)), \
         patch.object(CompletionPoller, "_nextflow_log_ended", staticmethod(lambda rid: True)):
        assert poller.tick_once() == 1
    assert calls == [("r1", None)]  # finalizer reads trace/log; a retried FAILED job is not the verdict


def test_log_ended_reads_marker(tmp_path, monkeypatch):
    monkeypatch.setenv("NEXTFLOW_WORK_DIR", str(tmp_path))
    d = tmp_path / "r1" / "work"
    d.mkdir(parents=True)
    (d / ".nextflow.log").write_text("... Task completed\n")
    assert CompletionPoller._nextflow_log_ended("r1") is False
    (d / ".nextflow.log").write_text("... > Execution complete -- Goodbye\n")
    assert CompletionPoller._nextflow_log_ended("r1") is True
