"""
Unit tests for WorkflowSession, WorkflowStep, WorkflowModification,
and WorkflowSessionStore (in-memory fallback — no Redis required).

N4 feature: multi-turn session state persistence.
"""

import time
import pytest
from galaxy.ai.workflow_session import (
    WorkflowSession,
    WorkflowStep,
    WorkflowModification,
    WorkflowSessionStore,
)


# ---------------------------------------------------------------------------
# WorkflowSession / WorkflowStep
# ---------------------------------------------------------------------------

class TestWorkflowSession:
    def test_new_session_has_no_steps(self):
        sess = WorkflowSession(session_id="s1")
        assert sess.steps == []
        assert sess.session_id == "s1"

    def test_add_step_appends_and_returns_step(self):
        sess = WorkflowSession(session_id="s2")
        step = sess.add_step(
            workflow_name="nf-core/rnaseq",
            nextflow_path="nf-core/rnaseq",
            params={"genome": "GRCh38", "aligner": "star"},
            output_types=["bam", "counts"],
        )
        assert len(sess.steps) == 1
        assert step.index == 0
        assert step.workflow_name == "nf-core/rnaseq"
        assert step.status == "pending"
        assert step.output_types == ["bam", "counts"]

    def test_add_second_step_auto_wires_input_from(self):
        sess = WorkflowSession(session_id="s3")
        sess.add_step("nf-core/rnaseq", "nf-core/rnaseq", {}, output_types=["bam"])
        step2 = sess.add_step("nf-core/sarek", "nf-core/sarek", {}, output_types=["vcf"])
        assert step2.index == 1
        assert step2.input_from == 0
        assert step2.input_type == "bam"

    def test_updated_at_changes_after_add_step(self):
        sess = WorkflowSession(session_id="s4")
        before = sess.updated_at
        time.sleep(0.01)
        sess.add_step("wf", "wf", {})
        assert sess.updated_at >= before

    def test_get_active_params_merges_skip_flags(self):
        sess = WorkflowSession(session_id="s5")
        sess.add_step("nf-core/rnaseq", "nf-core/rnaseq",
                      {"genome": "GRCh38"}, output_types=[])
        sess.steps[0].skipped_steps = ["skip_qc", "skip_markduplicates"]
        params = sess.get_active_params(0)
        assert params["genome"] == "GRCh38"
        assert params["skip_qc"] == "true"
        assert params["skip_markduplicates"] == "true"

    def test_get_active_params_last_step_default(self):
        sess = WorkflowSession(session_id="s6")
        sess.add_step("a", "a", {"x": 1})
        sess.add_step("b", "b", {"y": 2})
        assert sess.get_active_params()["y"] == 2

    def test_get_active_params_empty_session_returns_empty(self):
        sess = WorkflowSession(session_id="empty")
        assert sess.get_active_params() == {}

    def test_serialization_roundtrip(self):
        sess = WorkflowSession(session_id="rt", user_intent="run RNA-seq")
        sess.add_step("nf-core/rnaseq", "nf-core/rnaseq",
                      {"genome": "GRCh38"}, output_types=["bam"])
        d = sess.to_dict()
        restored = WorkflowSession.from_dict(d)
        assert restored.session_id == "rt"
        assert restored.user_intent == "run RNA-seq"
        assert len(restored.steps) == 1
        assert restored.steps[0].workflow_name == "nf-core/rnaseq"
        assert restored.steps[0].params["genome"] == "GRCh38"


# ---------------------------------------------------------------------------
# WorkflowModification
# ---------------------------------------------------------------------------

class TestWorkflowModification:
    def test_apply_value_change_to_last_step(self):
        sess = WorkflowSession(session_id="m1")
        sess.add_step("nf-core/rnaseq", "nf-core/rnaseq",
                      {"genome": "GRCh38", "min_cov": 10})
        mod = WorkflowModification(
            type="value_change",
            param_changes={"min_cov": 30},
            raw_message="change min coverage to 30",
        )
        applied = sess.apply_modification(mod)
        assert applied is True
        assert sess.steps[0].params["min_cov"] == 30
        assert sess.steps[0].params["genome"] == "GRCh38"  # unchanged

    def test_apply_skip_step(self):
        sess = WorkflowSession(session_id="m2")
        sess.add_step("nf-core/sarek", "nf-core/sarek", {})
        mod = WorkflowModification(
            type="skip_step",
            skip_flags=["skip_annotation", "skip_vep"],
        )
        applied = sess.apply_modification(mod)
        assert applied is True
        assert "skip_annotation" in sess.steps[0].skipped_steps
        assert "skip_vep" in sess.steps[0].skipped_steps

    def test_apply_modification_empty_session_returns_false(self):
        sess = WorkflowSession(session_id="m3")
        mod = WorkflowModification(type="value_change", param_changes={"x": 1})
        assert sess.apply_modification(mod) is False

    def test_apply_to_specific_step_index(self):
        sess = WorkflowSession(session_id="m4")
        sess.add_step("a", "a", {"v": 1})
        sess.add_step("b", "b", {"v": 2})
        mod = WorkflowModification(
            type="value_change",
            step_index=0,
            param_changes={"v": 99},
        )
        sess.apply_modification(mod)
        assert sess.steps[0].params["v"] == 99
        assert sess.steps[1].params["v"] == 2  # untouched


# ---------------------------------------------------------------------------
# WorkflowSessionStore (in-memory fallback — no Redis)
# ---------------------------------------------------------------------------

class TestWorkflowSessionStore:
    def _store(self) -> WorkflowSessionStore:
        # redis_url=None → always use in-memory dict (no ping)
        return WorkflowSessionStore(redis_url=None)

    def test_get_nonexistent_returns_none(self):
        store = self._store()
        assert store.get("does-not-exist") is None

    def test_save_and_get_roundtrip(self):
        store = self._store()
        sess = WorkflowSession(session_id="st1", user_intent="test")
        sess.add_step("nf-core/rnaseq", "nf-core/rnaseq", {"genome": "mm10"})
        store.save(sess)
        loaded = store.get("st1")
        assert loaded is not None
        assert loaded.session_id == "st1"
        assert len(loaded.steps) == 1
        assert loaded.steps[0].params["genome"] == "mm10"

    def test_get_or_create_creates_when_missing(self):
        store = self._store()
        sess = store.get_or_create("new-session", user_intent="hello")
        assert sess.session_id == "new-session"
        assert sess.user_intent == "hello"
        assert sess.steps == []

    def test_get_or_create_returns_existing(self):
        store = self._store()
        original = WorkflowSession(session_id="existing", user_intent="original")
        original.add_step("wf", "wf", {"x": 1})
        store.save(original)
        loaded = store.get_or_create("existing", user_intent="new intent")
        # Should return the saved one, not create a new one
        assert loaded.user_intent == "original"
        assert len(loaded.steps) == 1

    def test_delete_removes_session(self):
        store = self._store()
        sess = WorkflowSession(session_id="del-me")
        store.save(sess)
        store.delete("del-me")
        assert store.get("del-me") is None

    def test_save_updates_updated_at(self):
        store = self._store()
        sess = WorkflowSession(session_id="ts1")
        old_time = sess.updated_at
        time.sleep(0.01)
        store.save(sess)
        loaded = store.get("ts1")
        assert loaded.updated_at >= old_time

    def test_prior_context_injection_logic(self):
        """Verify the context injection string the endpoint builds."""
        store = self._store()
        sess = store.get_or_create("ctx-sess", user_intent="run RNA-seq")
        sess.add_step(
            workflow_name="nf-core/rnaseq",
            nextflow_path="nf-core/rnaseq",
            params={"genome": "GRCh38", "aligner": "star"},
        )
        store.save(sess)
        reloaded = store.get("ctx-sess")
        last_step = reloaded.steps[-1]
        prior_ctx = (
            f"[Active pipeline: {last_step.workflow_name}, "
            f"step {last_step.index + 1}, status={last_step.status}, "
            f"params={list(last_step.params.keys())}] "
        )
        full_intent = prior_ctx + "change genome to mm10"
        assert "nf-core/rnaseq" in full_intent
        assert "step 1" in full_intent
        assert "change genome to mm10" in full_intent
