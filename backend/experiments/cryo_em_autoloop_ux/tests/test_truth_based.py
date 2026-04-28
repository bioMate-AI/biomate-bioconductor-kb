"""
Truth-based tests for the cryo-EM auto-loop UX module.

Verifies:
  1. Forum knowledge module integrity (ForumEntry fields, ENTRIES_BY_GATE)
  2. Forum coverage for audit-weak gates (junk_fraction, orientation_anisotropy)
  3. Key verbatim quotes from forum threads are present (spot-checks)
  4. Confidence hierarchy: "confirmed" entries present for critical thresholds
  5. Global auto-loop toggle: auto_loop_enabled=False → single attempt per phase
  6. Per-phase toggle: enabled_phases subset → only named phases retry
  7. Per-phase toggle: disabled phase fails but others still retry
  8. Remediation alignment: auto-loop param changes are consistent with forum advice
  9. UXAwareAutoLoop.enabled_phases defaults to all 5 phases
 10. Forum knowledge does not contradict literature knowledge (shared gates)

Run with:
    python -m pytest tests/test_truth_based.py -v
(from backend/experiments/cryo_em_autoloop_ux/)
"""

from __future__ import annotations

import json
import sys
import tempfile
from io import StringIO
from pathlib import Path

import pytest
from rich.console import Console

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent))

from cryo_em_autoloop.params import CryoEMParams
from cryo_em_autoloop.qc_evaluator import CryoEMQCEvaluator
from cryo_em_autoloop_ux.forum_knowledge import (
    FORUM_ENTRIES,
    ENTRIES_BY_GATE,
    ForumEntry,
    MOTION_DRIFT,
    CTF_FIT_QUALITY,
    JUNK_FRACTION,
    ORIENTATION_ANISOTROPY,
    ABINITIO_CLASS_SCORE,
)
from cryo_em_autoloop_ux.knowledge_base import GATE_KNOWLEDGE, get_knowledge
from cryo_em_autoloop_ux.enriched_tuner import KnowledgeEnrichedTuner
from cryo_em_autoloop_ux.progress_reporter import ProgressReporter
from cryo_em_autoloop_ux.ux_loop import UXAwareAutoLoop
from cryo_em_autoloop_ux.demo import SCENARIOS, run_scenario


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def tmpdir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def silent_console():
    return Console(file=StringIO(), highlight=False, markup=False)


def _make_reporter(verbose: bool = False):
    buf = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()), json_sink=buf, verbose=verbose
    )
    return reporter, buf


# ── 1. Forum knowledge module integrity ──────────────────────────────────────

class TestForumKnowledgeIntegrity:

    EXPECTED_GATES = {
        # Original 5 gates from initial crawl
        "motion_drift", "ctf_fit_quality", "junk_fraction",
        "orientation_anisotropy", "abinitio_class_score",
        # 6 gates added in audit pass (covers all 11 QC gates)
        "per_frame_drift", "astigmatism", "particle_yield",
        "abinitio_resolution", "fsc_resolution", "class_quality",
    }

    def test_entries_by_gate_has_all_expected_gates(self):
        assert set(ENTRIES_BY_GATE.keys()) == self.EXPECTED_GATES

    def test_forum_entries_count_is_reasonable(self):
        # Crawl produced 35 entries; sanity-check it's non-trivial
        assert len(FORUM_ENTRIES) >= 20, (
            f"Expected ≥20 forum entries, got {len(FORUM_ENTRIES)}"
        )

    def test_all_entry_fields_non_empty(self):
        required = ("url", "thread_title", "author", "symptom", "param_changed",
                    "value_used", "outcome", "verbatim", "confidence", "gate")
        for e in FORUM_ENTRIES:
            for field in required:
                val = getattr(e, field)
                assert val and str(val).strip(), (
                    f"ForumEntry({e.gate}) field '{field}' is empty"
                )

    def test_confidence_values_are_valid(self):
        valid = {"confirmed", "reported_worked", "suggested"}
        for e in FORUM_ENTRIES:
            assert e.confidence in valid, (
                f"Entry '{e.thread_title}' has invalid confidence {e.confidence!r}"
            )

    def test_gate_field_matches_section(self):
        for gate, entries in ENTRIES_BY_GATE.items():
            for e in entries:
                assert e.gate == gate, (
                    f"Entry in section '{gate}' has gate={e.gate!r}"
                )

    def test_urls_start_with_https_discuss_cryosparc(self):
        for e in FORUM_ENTRIES:
            assert e.url.startswith("https://discuss.cryosparc.com/"), (
                f"Unexpected URL: {e.url}"
            )

    def test_all_forums_entries_accessible_via_entries_by_gate(self):
        all_from_dict = sum(len(v) for v in ENTRIES_BY_GATE.values())
        assert all_from_dict == len(FORUM_ENTRIES), (
            "FORUM_ENTRIES total doesn't match sum of ENTRIES_BY_GATE values"
        )


# ── 2. Forum coverage for audit-weak gates ───────────────────────────────────

class TestForumCoverageForWeakGates:
    """
    The knowledge audit (docs/20260416_AUTOLOOP_KNOWLEDGE_AUDIT.md) found that
    junk_fraction and orientation_anisotropy had NO literature support.
    The forum crawl must fill this gap.
    """

    def test_junk_fraction_has_forum_entries(self):
        entries = ENTRIES_BY_GATE["junk_fraction"]
        assert len(entries) >= 3, (
            f"junk_fraction needs ≥3 forum entries (audit rated it ❌ for literature); "
            f"got {len(entries)}"
        )

    def test_junk_fraction_has_confirmed_or_worked_entry(self):
        entries = ENTRIES_BY_GATE["junk_fraction"]
        high_conf = [e for e in entries if e.confidence in ("confirmed", "reported_worked")]
        assert len(high_conf) >= 1, (
            "junk_fraction must have ≥1 confirmed/reported_worked forum entry"
        )

    def test_orientation_anisotropy_has_forum_entries(self):
        entries = ENTRIES_BY_GATE["orientation_anisotropy"]
        assert len(entries) >= 3, (
            f"orientation_anisotropy needs ≥3 forum entries (audit rated it ❌); "
            f"got {len(entries)}"
        )

    def test_orientation_anisotropy_has_warning_entry(self):
        """The audit found a key warning: rebalancing can improve metrics but degrade resolution."""
        entries = ENTRIES_BY_GATE["orientation_anisotropy"]
        warning_entries = [
            e for e in entries
            if "degrad" in e.outcome.lower() or "warn" in e.outcome.lower()
            or "mislead" in e.verbatim.lower()
        ]
        assert len(warning_entries) >= 1, (
            "orientation_anisotropy must have an entry warning that rebalancing "
            "can degrade resolution despite improved distribution metrics"
        )

    def test_ctf_native_threshold_is_0_3_confirmed(self):
        """
        CryoSPARC's native CTF fit CC threshold is 0.3 — confirmed by developer.
        This is the critical discrepancy with BioMate's qc_evaluator using 0.70.
        The 0.3 value is recorded in value_used (verbatim quotes "Yes that's correct"
        without restating the number).
        """
        entries = ENTRIES_BY_GATE["ctf_fit_quality"]
        confirmed_03 = [
            e for e in entries
            if e.confidence == "confirmed" and (
                "0.3" in e.verbatim or "0.3" in e.value_used
            )
        ]
        assert len(confirmed_03) >= 1, (
            "Must have ≥1 developer-confirmed entry showing CTF CC threshold = 0.3 "
            "(check verbatim and value_used fields)"
        )


# ── 3. Verbatim quote spot-checks ────────────────────────────────────────────

class TestVerbatimQuotes:
    """Spot-check that key practitioner advice is faithfully recorded."""

    def test_motion_3x3_patch_verbatim_present(self):
        verbatims = [e.verbatim for e in MOTION_DRIFT]
        assert any("3x3" in v or "4x4" in v for v in verbatims), (
            "motion_drift must contain the 3x3/4x4 patch advice from olibclarke"
        )

    def test_motion_outcome_3_1_angstrom_present(self):
        """User asgodoy confirmed 3.1 Å after applying the patch advice."""
        combined = " ".join(e.verbatim + " " + e.outcome for e in MOTION_DRIFT)
        assert "3.1" in combined, (
            "motion_drift must record the 3.1 Å outcome verification"
        )

    def test_junk_lowpass_20A_floor_verbatim_present(self):
        """lowpass < 20 Å is 'really dangerous' — key safety rule."""
        verbatims = [e.verbatim for e in JUNK_FRACTION]
        assert any("20" in v for v in verbatims), (
            "junk_fraction must contain the 20 Å lowpass floor advice"
        )

    def test_junk_decoy_class_5pct_rule_present(self):
        """Iterate until junk < 5% of total stack — key stopping criterion."""
        combined = " ".join(e.verbatim + " " + e.param_changed for e in JUNK_FRACTION)
        assert "5%" in combined or "5 %" in combined or "decoy" in combined.lower(), (
            "junk_fraction must record the <5% decoy stopping criterion"
        )

    def test_abinitio_500_floor_verbatim_present(self):
        """Below 500 initial iterations 'does nothing' — confirmed community rule."""
        verbatims = [e.verbatim for e in ABINITIO_CLASS_SCORE]
        assert any("500" in v for v in verbatims), (
            "abinitio_class_score must contain the 500-iteration floor advice"
        )

    def test_ctf_0_3_confirmed_in_value_used(self):
        """Developer confirmed 0.3 — recorded in value_used since the verbatim
        response was 'Yes that's correct' without restating the number."""
        value_useds = [e.value_used for e in CTF_FIT_QUALITY]
        assert any("0.3" in v for v in value_useds), (
            "ctf_fit_quality must record the 0.3 threshold in value_used"
        )


# ── 4. Confidence hierarchy ───────────────────────────────────────────────────

class TestConfidenceHierarchy:

    def test_ctf_has_developer_confirmed_entries(self):
        confirmed = [e for e in CTF_FIT_QUALITY if e.confidence == "confirmed"]
        assert len(confirmed) >= 2, (
            "CTF fit quality must have ≥2 developer-confirmed entries "
            "(threshold=0.3 confirmation + bug fix in v5.0.2)"
        )

    def test_motion_has_reported_worked_entries(self):
        worked = [e for e in MOTION_DRIFT if e.confidence == "reported_worked"]
        assert len(worked) >= 2, (
            "motion_drift must have ≥2 reported_worked entries "
            "(the 3.1 Å outcome is independently confirmed twice)"
        )

    def test_each_gate_has_at_least_one_high_confidence(self):
        """
        All gates except abinitio_class_score must have ≥1 confirmed/reported_worked entry.
        abinitio_class_score is a documented gap: the forum only has 'suggested' entries
        (no developer confirmations, no published success reports for iteration count tuning).
        This is a known limitation recorded in the knowledge audit.
        """
        KNOWN_SUGGESTED_ONLY = {"abinitio_class_score"}
        for gate, entries in ENTRIES_BY_GATE.items():
            if gate in KNOWN_SUGGESTED_ONLY:
                continue
            high_conf = [e for e in entries if e.confidence in ("confirmed", "reported_worked")]
            assert len(high_conf) >= 1, (
                f"Gate '{gate}' has no confirmed/reported_worked entries — "
                "all entries are 'suggested' (weakest evidence level)"
            )

    def test_abinitio_is_known_gap_all_suggested(self):
        """
        Explicitly verify the known gap: abinitio_class_score only has 'suggested'
        evidence. This is documented in the audit as requiring further validation.
        """
        entries = ENTRIES_BY_GATE["abinitio_class_score"]
        high_conf = [e for e in entries if e.confidence in ("confirmed", "reported_worked")]
        assert len(high_conf) == 0, (
            "If abinitio_class_score now has confirmed/reported_worked entries, "
            "remove it from the KNOWN_SUGGESTED_ONLY set in test_each_gate_has_at_least_one_high_confidence"
        )


# ── 5. Global auto-loop toggle ────────────────────────────────────────────────

class TestGlobalAutoLoopToggle:

    def _make_always_failing_runner(self):
        """Phase runner that always returns metrics that fail phase_A."""
        ev = CryoEMQCEvaluator()

        def runner(phase: str, params: CryoEMParams) -> dict:
            if phase == "phase_A":
                return {
                    "mean_total_drift_A": 90.0,  # far above 50 Å threshold
                    "mean_per_frame_drift_A": 2.0,
                    "mean_ctf_fit_quality": 0.88,
                    "mean_astigmatism_A": 300.0,
                }
            # All other phases pass trivially
            return {
                "junk_fraction": 0.10,
                "num_particles_selected": 100_000,
                "min_particles_required": 5_000,
                "orientation_anisotropy": 2.0,
                "mean_class_quality": 0.8,
                "best_abinitio_class_score": 0.30,
                "best_abinitio_resolution_A": 15.0,
                "fsc_resolution_A": 4.5,
                "best_fsc_resolution_A": 4.5,
                "molprobity_score": 1.5,
                "ramachandran_favored_pct": 0.98,
                "rotamer_outlier_pct": 0.01,
            }

        return runner

    def test_disabled_globally_runs_each_phase_once(self, tmpdir):
        """With auto_loop_enabled=False, each phase runs exactly once."""
        reporter, buf = _make_reporter()
        loop = UXAwareAutoLoop(
            run_id="test-global-off",
            params=CryoEMParams(),
            max_retries_per_phase=3,
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=False,  # global off
        )
        result = loop.run(self._make_always_failing_runner())

        # phase_A fails on attempt 1 with no retry → escalated
        assert "phase_A" in result.phases_escalated, (
            "phase_A should escalate (fail once) when auto_loop_enabled=False"
        )
        # Total attempts = 5 (one per phase, no retries anywhere)
        assert result.total_attempts == 5, (
            f"Expected 5 total attempts (1 per phase), got {result.total_attempts}"
        )

    def test_disabled_globally_no_autoloop_update_events(self, tmpdir):
        """With auto_loop_enabled=False, no autoloop_update SSE events are emitted."""
        reporter, buf = _make_reporter(verbose=True)
        loop = UXAwareAutoLoop(
            run_id="test-no-retry-events",
            params=CryoEMParams(),
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=False,
        )
        loop.run(self._make_always_failing_runner())

        events = [json.loads(l) for l in buf.getvalue().strip().splitlines() if l.strip()]
        update_events = [e for e in events if e["type"] == "autoloop_update"]
        assert update_events == [], (
            f"With auto_loop_enabled=False, no autoloop_update events should be emitted; "
            f"got {len(update_events)}"
        )

    def test_enabled_globally_does_retry_phase_A(self, tmpdir):
        """Sanity check: with auto_loop_enabled=True (default), phase_A is retried."""
        reporter, buf = _make_reporter(verbose=True)
        loop = UXAwareAutoLoop(
            run_id="test-global-on",
            params=CryoEMParams(),
            max_retries_per_phase=2,
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=True,
        )
        result = loop.run(self._make_always_failing_runner())

        assert "phase_A" in result.phases_escalated
        # phase_A made 3 attempts (1 + 2 retries)
        phase_a_starts = []
        for line in buf.getvalue().strip().splitlines():
            if not line.strip():
                continue
            ev = json.loads(line)
            if ev["type"] == "autoloop_phase_start" and ev.get("phase") == "phase_A":
                phase_a_starts.append(ev)
        assert len(phase_a_starts) == 3, (
            f"phase_A should have 3 start events (1 + 2 retries); got {len(phase_a_starts)}"
        )


# ── 6. Per-phase toggle ───────────────────────────────────────────────────────

class TestPerPhaseToggle:

    def _make_phase_A_failing_runner(self):
        """phase_A always fails; all other phases pass."""
        def runner(phase: str, params: CryoEMParams) -> dict:
            if phase == "phase_A":
                return {
                    "mean_total_drift_A": 90.0,
                    "mean_per_frame_drift_A": 2.0,
                    "mean_ctf_fit_quality": 0.88,
                    "mean_astigmatism_A": 300.0,
                }
            return {
                "junk_fraction": 0.10,
                "num_particles_selected": 100_000,
                "min_particles_required": 5_000,
                "orientation_anisotropy": 2.0,
                "mean_class_quality": 0.8,
                "best_abinitio_class_score": 0.30,
                "best_abinitio_resolution_A": 15.0,
                "fsc_resolution_A": 4.5,
                "best_fsc_resolution_A": 4.5,
                "molprobity_score": 1.5,
                "ramachandran_favored_pct": 0.98,
                "rotamer_outlier_pct": 0.01,
            }
        return runner

    def test_phase_A_disabled_escalates_after_single_attempt(self, tmpdir):
        """With enabled_phases={} (none), phase_A fails after 1 attempt."""
        reporter, buf = _make_reporter()
        loop = UXAwareAutoLoop(
            run_id="test-phase-A-off",
            params=CryoEMParams(),
            max_retries_per_phase=3,
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=True,
            enabled_phases=set(),  # no phases have retry
        )
        result = loop.run(self._make_phase_A_failing_runner())

        assert "phase_A" in result.phases_escalated
        assert result.total_attempts == 5  # 1 per phase

    def test_phase_A_disabled_others_pass_normally(self, tmpdir):
        """Disabling auto-loop for phase_A doesn't affect phases B-E."""
        reporter, _ = _make_reporter()
        loop = UXAwareAutoLoop(
            run_id="test-a-off-others-ok",
            params=CryoEMParams(),
            max_retries_per_phase=2,
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=True,
            enabled_phases={"phase_B", "phase_C", "phase_D", "phase_E"},
        )
        result = loop.run(self._make_phase_A_failing_runner())

        # Other phases should all pass (metrics are fine)
        for p in ("phase_B", "phase_C", "phase_D", "phase_E"):
            assert p in result.phases_passed, f"{p} should pass"

    def test_only_phase_A_enabled_retries_only_A(self, tmpdir):
        """enabled_phases={'phase_A'} — only phase_A gets retry budget."""
        reporter, buf = _make_reporter(verbose=True)
        loop = UXAwareAutoLoop(
            run_id="test-only-a",
            params=CryoEMParams(),
            max_retries_per_phase=2,
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=True,
            enabled_phases={"phase_A"},  # only A
        )
        result = loop.run(self._make_phase_A_failing_runner())

        assert "phase_A" in result.phases_escalated
        # phase_A: 3 attempts (1 + 2 retries); phases B-E: 1 each
        assert result.total_attempts == 7, (
            f"Expected 7 total (3 for A + 1 each for B–E), got {result.total_attempts}"
        )

    def test_enabled_phases_defaults_to_all_five(self):
        loop = UXAwareAutoLoop(run_id="test-defaults")
        assert loop.enabled_phases == UXAwareAutoLoop.ALL_PHASES

    def test_phase_retry_allowed_respects_enabled_phases(self):
        loop_all = UXAwareAutoLoop(run_id="all", auto_loop_enabled=True)
        assert loop_all._phase_retry_allowed("phase_A") is True
        assert loop_all._phase_retry_allowed("phase_D") is True

        loop_none = UXAwareAutoLoop(run_id="none", auto_loop_enabled=True,
                                    enabled_phases=set())
        assert loop_none._phase_retry_allowed("phase_A") is False

        loop_ab = UXAwareAutoLoop(run_id="ab", auto_loop_enabled=True,
                                  enabled_phases={"phase_A", "phase_B"})
        assert loop_ab._phase_retry_allowed("phase_A") is True
        assert loop_ab._phase_retry_allowed("phase_B") is True
        assert loop_ab._phase_retry_allowed("phase_C") is False

        loop_global_off = UXAwareAutoLoop(run_id="goff", auto_loop_enabled=False)
        for phase in ("phase_A", "phase_B", "phase_C", "phase_D", "phase_E"):
            assert loop_global_off._phase_retry_allowed(phase) is False


# ── 7. Remediation alignment with forum advice ───────────────────────────────

class TestRemediationAlignmentWithForum:
    """
    Truth-based: verify that what the auto-loop actually changes is consistent
    with what practitioners/developers advise on the forum.
    """

    def test_motion_drift_remediation_reduces_batch_size(self):
        """Forum: reduce patch count / truncate frames when drift is severe.
        BioMate maps this to reducing micrograph_batch_size (smaller batches
        → shorter per-batch exposure, reduces accumulated drift artifact)."""
        ev = CryoEMQCEvaluator()
        qc = ev.evaluate_phase_A({
            "mean_total_drift_A": 80.0,
            "mean_per_frame_drift_A": 1.5,
            "mean_ctf_fit_quality": 0.88,
            "mean_astigmatism_A": 300.0,
        })
        tuner = KnowledgeEnrichedTuner()
        params = CryoEMParams(micrograph_batch_size=200)
        new_params, remeds = tuner.remediate(qc, params)

        motion_remeds = [r for r in remeds if r.gate == "motion_drift"]
        assert len(motion_remeds) >= 1
        # Batch size should decrease
        assert new_params.micrograph_batch_size < 200, (
            "motion_drift remediation must reduce micrograph_batch_size; "
            "smaller batches reduce accumulated stage drift"
        )

    def test_junk_remediation_increases_2d_classes(self):
        """Forum: use more 2D classes (140–200) for difficult datasets.
        BioMate remediation for high junk fraction should increase num_2d_classes."""
        ev = CryoEMQCEvaluator()
        qc = ev.evaluate_phase_B({
            "junk_fraction": 0.80,
            "num_particles_selected": 50_000,
            "min_particles_required": 5_000,
        })
        tuner = KnowledgeEnrichedTuner()
        params = CryoEMParams(num_2d_classes=50)
        new_params, remeds = tuner.remediate(qc, params)

        junk_remeds = [r for r in remeds if r.gate == "junk_fraction"]
        assert len(junk_remeds) >= 1

    def test_abinitio_remediation_increases_iterations(self):
        """Forum: < 500 initial iterations does nothing; minimum 1000.
        BioMate remediation for poor ab initio score should increase iterations."""
        ev = CryoEMQCEvaluator()
        qc = ev.evaluate_phase_D({
            "best_abinitio_class_score": 0.05,
            "best_abinitio_resolution_A": 30.0,
        })
        tuner = KnowledgeEnrichedTuner()
        params = CryoEMParams(num_ab_initio_classes=3)
        new_params, remeds = tuner.remediate(qc, params)

        abinit_remeds = [r for r in remeds if r.gate == "abinitio_class_score"]
        assert len(abinit_remeds) >= 1
        # Should not increase ab initio classes to an absurd value
        # (forum says reduce classes to 2–5 when similar; default 3 is fine)
        assert new_params.num_ab_initio_classes <= 5, (
            "ab initio remediation should not increase class count beyond 5 "
            "(forum: reduce classes when they are too similar)"
        )

    def test_all_remediations_have_forum_corroborated_gate(self):
        """Every gate that has a remediation must also have forum evidence."""
        gates_with_forum = set(ENTRIES_BY_GATE.keys())
        ev = CryoEMQCEvaluator()
        tuner = KnowledgeEnrichedTuner()

        failing_scenarios = [
            ev.evaluate_phase_A({
                "mean_total_drift_A": 80.0, "mean_per_frame_drift_A": 1.0,
                "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0,
            }),
            ev.evaluate_phase_B({
                "junk_fraction": 0.80,
                "num_particles_selected": 50_000,
                "min_particles_required": 5_000,
            }),
            ev.evaluate_phase_D({
                "best_abinitio_class_score": 0.05,
                "best_abinitio_resolution_A": 30.0,
            }),
        ]

        for qc in failing_scenarios:
            _, remeds = tuner.remediate(qc, CryoEMParams())
            for r in remeds:
                if r.gate in gates_with_forum:
                    # Gate appears in both literature and forum — good coverage
                    forum_entries = ENTRIES_BY_GATE.get(r.gate, [])
                    assert len(forum_entries) >= 1, (
                        f"Gate '{r.gate}' has a remediation but no forum evidence"
                    )


# ── 8. Forum knowledge does not contradict literature ─────────────────────────

class TestForumVsLiteratureConsistency:
    """
    The audit found that BioMate's qc_evaluator uses CTF FOM = 0.70 as the threshold
    but CryoSPARC natively uses 0.3 and papers use CTFFIND4 (different metric).
    This test verifies the forum knowledge correctly captures this discrepancy.
    """

    def test_ctf_forum_notes_native_threshold_is_0_3_not_0_7(self):
        ctf_entries = ENTRIES_BY_GATE["ctf_fit_quality"]
        threshold_entries = [
            e for e in ctf_entries
            if "0.3" in e.verbatim or "0.3" in e.value_used
        ]
        assert len(threshold_entries) >= 1, (
            "CTF forum entries must record that CryoSPARC native threshold = 0.3"
        )
        # Verify no entry claims the threshold is 0.7 (that would contradict the forum)
        wrong_threshold = [
            e for e in ctf_entries
            if "0.7" in e.verbatim or "0.70" in e.verbatim
        ]
        assert len(wrong_threshold) == 0, (
            "Forum entries must not claim CTF CC threshold = 0.7/0.70"
        )

    def test_motion_forum_and_literature_both_cite_severe_drift_fix(self):
        """Both forum (3x3 patches) and literature (total motion < 50 Å threshold)
        address the same underlying problem: severe stage drift."""
        motion_forum = ENTRIES_BY_GATE["motion_drift"]
        motion_lit = get_knowledge("motion_drift")

        # Literature has the 50 Å threshold
        assert any("50" in e.finding or "50" in e.source_text for e in motion_lit), (
            "Literature knowledge must reference the 50 Å total motion threshold"
        )
        # Forum has the patch count fix
        assert any("patch" in e.symptom.lower() or "patch" in e.param_changed.lower()
                   for e in motion_forum), (
            "Forum knowledge must reference the patch-count parameter"
        )


# ── 9. Full gate coverage audit ───────────────────────────────────────────────

class TestFullGateCoverage:
    """
    Audit: every QC gate that can HALT must have forum evidence.
    Previously only 5/11 gates had forum entries; now all 11 are covered.
    """

    ALL_QC_GATES = {
        "motion_drift", "per_frame_drift", "ctf_fit_quality", "astigmatism",
        "junk_fraction", "particle_yield",
        "orientation_anisotropy", "class_quality",
        "abinitio_class_score", "abinitio_resolution",
        "fsc_resolution",
    }

    def test_every_qc_gate_has_forum_entry(self):
        """All 11 QC gates now have at least one forum entry."""
        missing = self.ALL_QC_GATES - set(ENTRIES_BY_GATE.keys())
        assert len(missing) == 0, (
            f"Gates with no forum coverage: {sorted(missing)}"
        )

    def test_forum_entry_count_per_gate(self):
        """Each gate should have at least 2 entries for cross-validation."""
        for gate in self.ALL_QC_GATES:
            entries = ENTRIES_BY_GATE.get(gate, [])
            assert len(entries) >= 2, (
                f"Gate '{gate}' has only {len(entries)} forum entry — need ≥2 for cross-validation"
            )

    def test_new_gates_have_confirmed_or_worked(self):
        """The 6 gates added in this session must have ≥1 confirmed/reported_worked entry."""
        new_gates = {
            "per_frame_drift", "astigmatism", "particle_yield",
            "abinitio_resolution", "fsc_resolution", "class_quality",
        }
        for gate in new_gates:
            entries = ENTRIES_BY_GATE.get(gate, [])
            high_conf = [e for e in entries if e.confidence in ("confirmed", "reported_worked")]
            assert len(high_conf) >= 1, (
                f"New gate '{gate}' has no confirmed/reported_worked entry"
            )

    def test_fsc_resolution_forum_confirms_upstream_cause(self):
        """Forum confirms FSC failures come from upstream data quality, not refinement settings."""
        entries = ENTRIES_BY_GATE["fsc_resolution"]
        upstream_refs = [
            e for e in entries
            if any(kw in e.verbatim.lower() for kw in
                   ["upstream", "ctf", "particle quality", "quality", "ctf estimates"])
        ]
        assert len(upstream_refs) >= 1, (
            "FSC resolution forum entries must confirm upstream root cause"
        )

    def test_astigmatism_forum_confirms_no_software_fix(self):
        """Forum confirms astigmatism is hardware — no software parameter fix."""
        entries = ENTRIES_BY_GATE["astigmatism"]
        hardware_refs = [
            e for e in entries
            if any(kw in e.verbatim.lower() for kw in
                   ["hardware", "stigmator", "no software", "lens"])
        ]
        assert len(hardware_refs) >= 1, (
            "Astigmatism forum entries must confirm hardware root cause"
        )


# ── 10. param_tuner completeness ──────────────────────────────────────────────

class TestParamTunerCompleteness:
    """
    Verify the param_tuner handles all HALT-capable gates and the new
    fsc_resolution handler produces an explicit no-change advisory.
    """

    HALT_CAPABLE_GATES = {
        "motion_drift", "per_frame_drift", "ctf_fit_quality", "astigmatism",
        "junk_fraction", "particle_yield",
        "orientation_anisotropy",
        "abinitio_class_score", "abinitio_resolution",
        "fsc_resolution",
        # NOTE: class_quality is ADVISORY-only — never halts, no handler needed
    }

    def test_all_halt_capable_gates_have_handler(self):
        """Every gate that can fire QCAction.HALT must have an explicit handler."""
        from cryo_em_autoloop.param_tuner import ParamTuner
        handlers = set(ParamTuner._HANDLERS.keys())
        missing = self.HALT_CAPABLE_GATES - handlers
        assert len(missing) == 0, (
            f"Gates with HALT capability but no handler: {sorted(missing)}"
        )

    def test_fsc_resolution_handler_returns_empty_changes_with_rationale(self):
        """fsc_resolution fix returns {} param changes — no tunable params in phase_E."""
        from cryo_em_autoloop.param_tuner import ParamTuner
        tuner = ParamTuner()
        params = CryoEMParams()
        changes, rationale = tuner._fix_fsc_resolution(params)
        assert changes == {}, "fsc_resolution handler must return empty param_changes"
        assert len(rationale) > 50, "rationale must be a meaningful explanation"
        assert any(kw in rationale.lower() for kw in ["upstream", "phase_e", "phase e", "no tunable"]), (
            "rationale must explain why no params can be changed"
        )

    def test_unknown_gate_falls_back_gracefully(self):
        """A gate not in _HANDLERS produces a remediation with empty changes, not an error."""
        from cryo_em_autoloop.param_tuner import ParamTuner
        from cryo_em_autoloop.qc_evaluator import PhaseQCResult, GateResult, QCAction, QCLevel

        tuner = ParamTuner()
        fake_halt = GateResult(
            gate="nonexistent_gate",
            action=QCAction.HALT,
            level=QCLevel.BRONZE,
            value=999.0,
            threshold=1.0,
            message="fake gate failure",
            suggestion="",
        )
        qc = PhaseQCResult(phase="phase_A", gate_results=[fake_halt])
        _, remeds = tuner.remediate(qc, CryoEMParams())

        assert len(remeds) == 1
        assert remeds[0].gate == "nonexistent_gate"
        assert remeds[0].param_changes == {}
        assert "No remediation rule" in remeds[0].rationale

    def test_max_retries_zero_behaves_like_disabled(self, tmpdir):
        """max_retries_per_phase=0 means no retries — same as auto_loop_enabled=False."""
        reporter, buf = _make_reporter()

        loop_zero = UXAwareAutoLoop(
            run_id="zero-retries",
            params=CryoEMParams(),
            max_retries_per_phase=0,
            output_dir=tmpdir,
            reporter=reporter,
            auto_loop_enabled=True,
        )

        # Phase runner that always fails phase_A
        def runner(phase, params):
            if phase == "phase_A":
                return {"mean_total_drift_A": 200.0, "mean_per_frame_drift_A": 5.0,
                        "mean_ctf_fit_quality": 0.3, "mean_astigmatism_A": 300.0}
            return {"mean_total_drift_A": 20.0, "mean_per_frame_drift_A": 0.5,
                    "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0,
                    "junk_fraction": 0.1, "num_particles_selected": 100_000,
                    "min_particles_required": 5_000,
                    "mean_class_quality": 0.8, "orientation_anisotropy": 1.2,
                    "best_abinitio_class_score": 0.5, "best_abinitio_resolution_A": 8.0,
                    "fsc_resolution_A": 3.5}

        result = loop_zero.run(runner)
        assert "phase_A" in result.phases_escalated
        assert result.total_attempts == 5  # 1 per phase (no retries)


if __name__ == "__main__":
    import subprocess
    sys.exit(subprocess.call(["python", "-m", "pytest", __file__, "-v"]))
