"""Unit tests for workflow_chat_narrator — friendly templates + emit()."""

from __future__ import annotations

import logging

from galaxy.ai.workflow_ops.workflow_chat_narrator import emit, render_friendly


def test_static_template_renders_unchanged():
    assert render_friendly("workflow.submitted") == "Got it — starting your workflow now."
    assert render_friendly("workflow.queued") == "Your workflow is in the AWS Batch queue."
    assert render_friendly("workflow.running") == "Workflow is running."


def test_phase_started_with_step_count():
    msg = render_friendly("workflow.phase_started", {"phase_name": "STAR alignment", "n": 2, "of": 5})
    assert msg == "Step 2/5: STAR alignment…"


def test_phase_started_without_step_count():
    msg = render_friendly("workflow.phase_started", {"phase_name": "Quality control"})
    assert msg == "Step Quality control…"


def test_phase_completed_with_detail():
    msg = render_friendly("workflow.phase_completed", {"phase_name": "STAR", "detail": "moved 1.2M reads"})
    assert msg == "STAR done — moved 1.2M reads."


def test_phase_completed_no_detail():
    msg = render_friendly("workflow.phase_completed", {"phase_name": "FastQC"})
    assert msg == "FastQC done."


def test_phase_failed():
    msg = render_friendly("workflow.phase_failed", {"phase_name": "FQ_LINT", "reason": "exit 127"})
    assert "FQ_LINT failed" in msg
    assert "exit 127" in msg


def test_completed_summary_with_counts():
    msg = render_friendly("workflow.completed", {"steps_succeeded": 5, "steps_total": 5})
    assert msg == "Workflow finished. 5/5 steps succeeded."


def test_completed_summary_without_counts():
    assert render_friendly("workflow.completed") == "Workflow finished."


def test_qc_gate_warning():
    msg = render_friendly(
        "workflow.qc_gate_warning",
        {"metric": "hERG", "value": 0.62, "threshold": 0.5},
    )
    assert msg == "QC flagged hERG = 0.62 (threshold 0.5)."


def test_qc_gate_blocked():
    msg = render_friendly("workflow.qc_gate_blocked", {"metric": "hERG"})
    assert msg == "QC blocked on hERG — adjusting parameters."


def test_autoloop_started_with_changes():
    msg = render_friendly("workflow.autoloop_started", {"changes": {"logp_max": 4.5, "mw_max": 480}})
    assert "logp_max=4.5" in msg
    assert "mw_max=480" in msg


def test_failed_msg_with_reason():
    msg = render_friendly("workflow.failed", {"reason": "exit 127"})
    assert "Workflow stopped" in msg
    assert "exit 127" in msg


def test_unknown_kind_is_safe():
    msg = render_friendly("workflow.never_heard_of_it")
    assert "never_heard_of_it" in msg
    assert msg.startswith("Workflow update:")


def test_template_exception_is_swallowed():
    # render_friendly must never raise even if the template hits a KeyError
    msg = render_friendly("workflow.qc_gate_warning", {})  # missing fields
    assert "QC flagged" in msg


def test_emit_returns_payload_with_required_fields():
    payload = emit("inv-test-1", "workflow.running")
    assert payload["kind"] == "workflow.running"
    assert payload["invocation_id"] == "inv-test-1"
    assert payload["friendly_message"] == "Workflow is running."
    assert "ts" in payload
    assert payload["technical"] == {}


def test_emit_invokes_sse_callback_with_chat_progress():
    captured = []

    def fake_sse(event_type, data):
        captured.append((event_type, data))

    payload = emit(
        "inv-test-2",
        "workflow.phase_started",
        technical={"phase_name": "STAR", "n": 2, "of": 5},
        sse_callback=fake_sse,
    )
    assert len(captured) == 1
    event_type, data = captured[0]
    assert event_type == "chat_progress"
    assert data["kind"] == "workflow.phase_started"
    assert data["friendly_message"] == "Step 2/5: STAR…"
    assert data["technical"]["phase_name"] == "STAR"
    assert data is payload  # callback gets the same dict we return


def test_emit_swallows_sse_callback_exceptions():
    def bad_sse(*_a, **_k):
        raise RuntimeError("simulated network failure")

    # Must not raise — sse failure is logged, not propagated
    payload = emit("inv-test-3", "workflow.running", sse_callback=bad_sse)
    assert payload["friendly_message"] == "Workflow is running."


def test_emit_logs_engineer_channel(caplog):
    with caplog.at_level(logging.INFO, logger="galaxy.ai.workflow_ops.workflow_chat_narrator"):
        emit("inv-test-4", "workflow.phase_completed", {"phase_name": "STAR", "detail": "1.2M reads"})
    matching = [r for r in caplog.records if "[WORKFLOW]" in r.getMessage()]
    assert matching, "engineer-channel log line missing"
    record = matching[0]
    assert "inv-test-4" in record.getMessage()
    assert "workflow.phase_completed" in record.getMessage()
    assert "STAR done — 1.2M reads." in record.getMessage()
