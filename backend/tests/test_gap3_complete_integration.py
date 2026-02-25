"""
Complete Gap 3 Integration Test

Tests the full auto-pilot + QC gate + parameter tuning flow:
1. QC gate handler initialises the correct suggester per domain
2. Real file output → metric parsing → threshold check → suggestion generation → SSE event
3. SSE event has the structure the frontend expects (all required keys, camelCase suggestions)
4. JSON serialisability: every value in the SSE event round-trips through json.dumps/loads
"""

import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import Mock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
from galaxy.jobs.parameter_suggester import CryoEMParameterSuggester


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _handler_with_events(work_dir, domain, params=None):
    events = []
    h = NextflowQCGateHandler(
        invocation_id="test123",
        work_dir=work_dir,
        sse_callback=lambda t, d: events.append({"type": t, "data": d}),
        app=Mock(),
        workflow_domain=domain,
        current_parameters=params or {},
    )
    return h, events


def _submit(handler, process_name, hash_prefix, hash_rest, work_dir, file_writer=None):
    subdir = work_dir / hash_prefix / hash_rest
    subdir.mkdir(parents=True, exist_ok=True)
    if file_writer:
        file_writer(subdir)
    handler.handle_process_completion(
        task_id="1",
        process_name=process_name,
        process_hash=f"{hash_prefix}/{hash_rest}",
        status="COMPLETED",
    )


class TestGap3CompleteIntegration:
    """Test complete Gap 3: Auto-pilot UX + Parameter Tuning"""

    # ------------------------------------------------------------------
    # 1. Handler initialisation — correct suggester class per domain
    # ------------------------------------------------------------------

    def test_cryo_em_domain_initialises_cryo_em_suggester(self, tmp_path):
        """Handler must initialise CryoEMParameterSuggester for cryo_em domain."""
        h, _ = _handler_with_events(tmp_path, "cryo_em")
        assert h.parameter_suggester is not None
        assert isinstance(h.parameter_suggester, CryoEMParameterSuggester)

    def test_unknown_domain_still_initialises_some_suggester(self, tmp_path):
        """Any domain string must produce a non-None suggester (BaseParameterSuggester fallback)."""
        h, _ = _handler_with_events(tmp_path, "completely_unknown_domain")
        assert h.parameter_suggester is not None

    # ------------------------------------------------------------------
    # 2. Real file → real metrics → real suggestions → SSE event
    # ------------------------------------------------------------------

    def test_motion_correction_high_drift_from_real_file(self, tmp_path):
        """
        Write a realistic MotionCor2 log, run handle_process_completion,
        verify the SSE event contains correct metric values and suggestions.
        No mocking of the parser.
        """
        def write_log(subdir):
            (subdir / "motion.log").write_text(
                "Total motion: 65.3 Å\n"
                "Average per-frame motion: 4.1 Å\n"
            )

        h, events = _handler_with_events(
            tmp_path, "cryo_em",
            {"dose_weighting": False, "patch_size": 3}
        )
        _submit(h, "MOTION_CORRECTION", "ab", "cd001234", tmp_path, write_log)

        assert len(events) == 1, "Expected exactly one QC gate event"
        event = events[0]
        assert event["type"] == "qc_gate_triggered"
        data = event["data"]

        # Metric value comes from the real log file parse
        assert data["qc_metrics"]["total_drift_angstrom"] == pytest.approx(65.3, abs=0.5)

        # Failure structure
        assert len(data["failures"]) >= 1
        drift_fail = next(f for f in data["failures"] if f["metric"] == "total_drift_angstrom")
        assert drift_fail["operator"] == ">"
        assert drift_fail["threshold"] == 50

        # Suggestion from real suggester (not mocked)
        suggestions = data["suggestions"]
        dw = next((s for s in suggestions if s["parameter"] == "dose_weighting"), None)
        assert dw is not None, "Expected dose_weighting suggestion for high drift"
        assert dw["suggestedValue"] is True
        assert dw["confidence"] == pytest.approx(0.85, abs=0.01)
        assert "drift" in dw["reason"].lower() or "Excessive" in dw["reason"]

    def test_ctf_estimation_real_file_triggers_gate_with_suggestions(self, tmp_path):
        """
        Write a CTFFIND4 output file with high astigmatism and low fit score.
        Verify the full pipeline produces correct failures and suggestions.
        """
        def write_ctf(subdir):
            # defocus_u=15000, defocus_v=13500 → astigmatism=1500Å (> 1000Å advisory threshold)
            # fit_score=0.60 (< 0.70 hard gate threshold)
            (subdir / "ctf.txt").write_text("15000.0\t13500.0\t45.0\t0.0\t0.60\n")

        h, events = _handler_with_events(
            tmp_path, "cryo_em",
            {"use_tilt_search": False, "defocus_min": 10000, "defocus_max": 30000}
        )
        _submit(h, "CTF_ESTIMATION", "cd", "ef002345", tmp_path, write_ctf)

        assert len(events) == 1
        data = events[0]["data"]

        assert data["qc_metrics"]["astigmatism_angstrom"] == pytest.approx(1500.0, abs=10)
        assert data["qc_metrics"]["fit_quality"] == pytest.approx(0.60, abs=0.01)

        failed_metrics = {f["metric"] for f in data["failures"]}
        assert "astigmatism_angstrom" in failed_metrics
        assert "fit_quality" in failed_metrics

        # Suggestions must be present
        assert len(data["suggestions"]) > 0

    def test_particle_picking_real_star_file(self, tmp_path):
        """
        Write a STAR coordinate file with 200 particles (below 1000 threshold).
        Verify the gate fires with real particle count and a picking suggestion.
        """
        def write_star(subdir):
            lines = ["_rlnCoordinateX\n_rlnCoordinateY"]
            for i in range(200):
                lines.append(f"{i * 100}.0\t{i * 50}.0")
            (subdir / "particles.star").write_text("\n".join(lines) + "\n")

        h, events = _handler_with_events(
            tmp_path, "cryo_em",
            {"picking_threshold": 0.5, "minimum_separation": 10}
        )
        _submit(h, "PARTICLE_PICKING", "ef", "gh003456", tmp_path, write_star)

        assert len(events) == 1
        data = events[0]["data"]
        assert data["qc_metrics"]["particles_picked"] == 200
        assert data["failures"][0]["metric"] == "particles_picked"
        assert len(data["suggestions"]) > 0

    # ------------------------------------------------------------------
    # 3. SSE event structure — keys the frontend contract requires
    # ------------------------------------------------------------------

    REQUIRED_TOPLEVEL_KEYS = {"invocation_id", "process_name", "qc_metrics",
                              "failures", "suggestions", "timestamp"}
    REQUIRED_FAILURE_KEYS  = {"metric", "value", "threshold", "operator", "message"}
    REQUIRED_SUGGESTION_KEYS = {"parameter", "currentValue", "suggestedValue",
                                "reason", "confidence"}

    def test_sse_event_has_all_required_top_level_keys(self, tmp_path):
        def write_log(subdir):
            (subdir / "motion.log").write_text("Total motion: 70.0 Å\n")

        h, events = _handler_with_events(tmp_path, "cryo_em", {"dose_weighting": False})
        _submit(h, "MOTION_CORRECTION", "ab", "ij004567", tmp_path, write_log)

        assert len(events) == 1
        data = events[0]["data"]
        missing = self.REQUIRED_TOPLEVEL_KEYS - set(data.keys())
        assert not missing, f"SSE event missing top-level keys: {missing}"

    def test_sse_failure_dicts_have_required_keys(self, tmp_path):
        def write_log(subdir):
            (subdir / "motion.log").write_text("Total motion: 70.0 Å\n")

        h, events = _handler_with_events(tmp_path, "cryo_em", {})
        _submit(h, "MOTION_CORRECTION", "ab", "kl005678", tmp_path, write_log)

        for failure in events[0]["data"]["failures"]:
            missing = self.REQUIRED_FAILURE_KEYS - set(failure.keys())
            assert not missing, f"Failure dict missing keys: {missing}"

    def test_sse_suggestion_dicts_have_required_camelcase_keys(self, tmp_path):
        """Suggestions must use camelCase keys for frontend JSON consumption."""
        def write_log(subdir):
            (subdir / "motion.log").write_text("Total motion: 70.0 Å\n")

        h, events = _handler_with_events(tmp_path, "cryo_em", {"dose_weighting": False})
        _submit(h, "MOTION_CORRECTION", "ab", "mn006789", tmp_path, write_log)

        for suggestion in events[0]["data"]["suggestions"]:
            missing = self.REQUIRED_SUGGESTION_KEYS - set(suggestion.keys())
            assert not missing, f"Suggestion dict missing keys: {missing}"
            # Verify camelCase (not snake_case) — frontend contract
            assert "current_value" not in suggestion, "Should be currentValue (camelCase)"
            assert "suggested_value" not in suggestion, "Should be suggestedValue (camelCase)"

    def test_sse_invocation_id_matches_handler(self, tmp_path):
        def write_log(subdir):
            (subdir / "motion.log").write_text("Total motion: 70.0 Å\n")

        events = []
        h = NextflowQCGateHandler(
            invocation_id="my-unique-invocation-42",
            work_dir=tmp_path,
            sse_callback=lambda t, d: events.append(d),
            app=Mock(),
            workflow_domain="cryo_em",
        )
        subdir = tmp_path / "ab" / "op007890"
        subdir.mkdir(parents=True)
        write_log(subdir)
        h.handle_process_completion("t1", "MOTION_CORRECTION", "ab/op007890", "COMPLETED")

        assert events[0]["invocation_id"] == "my-unique-invocation-42"

    # ------------------------------------------------------------------
    # 4. JSON serialisability — real parsed data must round-trip
    # ------------------------------------------------------------------

    def test_full_event_is_json_serialisable(self, tmp_path):
        """
        Every value in the SSE event dict produced from a real motion log
        must survive json.dumps → json.loads without error or data loss.
        """
        def write_log(subdir):
            (subdir / "motion.log").write_text(
                "Total motion: 65.3 Å\n"
                "Average per-frame motion: 4.1 Å\n"
            )

        h, events = _handler_with_events(tmp_path, "cryo_em", {"dose_weighting": False})
        _submit(h, "MOTION_CORRECTION", "ab", "qr008901", tmp_path, write_log)

        assert len(events) == 1
        data = events[0]["data"]

        # Must not raise
        json_str = json.dumps(data)
        parsed = json.loads(json_str)

        # Round-trip preserves metric values
        assert parsed["qc_metrics"]["total_drift_angstrom"] == pytest.approx(65.3, abs=0.5)
        assert parsed["process_name"] == "MOTION_CORRECTION"
        # All confidence values survive as floats
        for s in parsed["suggestions"]:
            assert isinstance(s["confidence"], float)
            assert 0.0 <= s["confidence"] <= 1.0

    def test_ctf_event_is_json_serialisable(self, tmp_path):
        """CTF event with Å unicode characters serialises correctly."""
        def write_ctf(subdir):
            (subdir / "ctf.txt").write_text("20000.0\t18000.0\t30.0\t0.0\t0.55\n")

        h, events = _handler_with_events(tmp_path, "cryo_em", {})
        _submit(h, "CTF_ESTIMATION", "st", "uv009012", tmp_path, write_ctf)

        assert len(events) == 1
        # Must not raise for unicode Å in message strings
        json_str = json.dumps(events[0]["data"], ensure_ascii=False)
        parsed = json.loads(json_str)
        # Å character preserved in failure messages
        messages = [f["message"] for f in parsed["failures"]]
        assert any("Å" in m or "astigmatism" in m.lower() for m in messages)

    # ------------------------------------------------------------------
    # 5. Suggester unit tests (real CryoEMParameterSuggester, no mocks)
    # ------------------------------------------------------------------

    def test_cryo_em_suggester_motion_correction(self):
        """Real CryoEMParameterSuggester: high drift + low correlation → 3 suggestions."""
        suggester = CryoEMParameterSuggester()
        suggestions = suggester.suggest(
            process_name="MOTION_CORRECTION",
            qc_metrics={
                "total_drift_angstrom": 65.3,
                "correlation_score": 0.42
            },
            current_parameters={
                "dose_weighting": False,
                "patch_size": 3,
                "alignment_frames": 1
            },
            failures=[
                "Excessive drift: 65.3Å (threshold: 50Å)",
                "Low correlation: 0.42 (threshold: 0.5)"
            ]
        )

        assert len(suggestions) == 3

        dw = next(s for s in suggestions if s.parameter == "dose_weighting")
        assert dw.current_value is False
        assert dw.suggested_value is True
        assert dw.confidence == 0.85

        ps = next(s for s in suggestions if s.parameter == "patch_size")
        assert ps.current_value == 3
        assert ps.suggested_value == 5
        assert ps.confidence == 0.75

        af = next(s for s in suggestions if s.parameter == "alignment_frames")
        assert af.current_value == 1
        assert af.suggested_value == 3
        assert af.confidence == 0.70

    def test_cryo_em_suggester_ctf_estimation(self):
        """Real CryoEMParameterSuggester: high astigmatism + low fit → 2 suggestions."""
        suggester = CryoEMParameterSuggester()
        suggestions = suggester.suggest(
            process_name="CTF_ESTIMATION",
            qc_metrics={"astigmatism_angstrom": 1500, "fit_quality": 0.6},
            current_parameters={
                "use_tilt_search": False,
                "defocus_min": 10000,
                "defocus_max": 30000
            },
            failures=[
                "Elevated astigmatism: 1500Å (advisory: 1000Å)",
                "Poor CTF fit: 0.6 (threshold: 0.7)"
            ]
        )

        assert len(suggestions) == 2

        tilt = next(s for s in suggestions if s.parameter == "use_tilt_search")
        assert tilt.suggested_value is True
        assert tilt.confidence == 0.80

        defocus = next(s for s in suggestions if s.parameter == "defocus_search_range")
        assert defocus.suggested_value == {"defocus_min": 5000, "defocus_max": 50000}
        assert defocus.confidence == 0.75

    def test_cryo_em_suggester_particle_picking_too_few(self):
        """Low particle count → picking_threshold suggestion (lower to pick more)."""
        suggester = CryoEMParameterSuggester()
        suggestions = suggester.suggest(
            process_name="PARTICLE_PICKING",
            qc_metrics={"particles_picked": 500, "duplicate_fraction": 0.05},
            current_parameters={"picking_threshold": 0.5, "minimum_separation": 10},
            failures=["Too few particles: 500 (threshold: 1000)"]
        )

        assert len(suggestions) == 1
        assert suggestions[0].parameter == "picking_threshold"
        assert suggestions[0].suggested_value == pytest.approx(0.4, abs=0.01)
        assert suggestions[0].confidence == 0.65

    def test_cryo_em_suggester_particle_picking_high_duplicates(self):
        """High duplicate_fraction → minimum_separation suggestion (increase to space particles)."""
        suggester = CryoEMParameterSuggester()
        suggestions = suggester.suggest(
            process_name="PARTICLE_PICKING",
            qc_metrics={"particles_picked": 5000, "duplicate_fraction": 0.35},
            current_parameters={"picking_threshold": 0.3, "minimum_separation": 10},
            failures=["High duplicate fraction: 0.35 (threshold: 0.2)"]
        )

        assert len(suggestions) == 1
        assert suggestions[0].parameter == "minimum_separation"
        assert suggestions[0].suggested_value == 20
        assert suggestions[0].confidence == 0.80

    # ------------------------------------------------------------------
    # 6. No gate when metrics pass (regression from previous hollow test)
    # ------------------------------------------------------------------

    def test_good_motion_log_no_sse_event(self, tmp_path):
        """A motion log with only 12Å drift must not fire the QC gate."""
        def write_log(subdir):
            (subdir / "motion.log").write_text(
                "Total motion: 12.4 Å\n"
                "Average per-frame motion: 0.8 Å\n"
            )

        h, events = _handler_with_events(tmp_path, "cryo_em", {})
        _submit(h, "MOTION_CORRECTION", "ab", "wx010123", tmp_path, write_log)
        assert events == []

    def test_good_ctf_no_sse_event(self, tmp_path):
        """CTF output with 200Å astigmatism and fit=0.92 must not fire the gate."""
        def write_ctf(subdir):
            (subdir / "ctf.txt").write_text("15000.0\t14800.0\t30.0\t0.0\t0.92\n")

        h, events = _handler_with_events(tmp_path, "cryo_em", {})
        _submit(h, "CTF_ESTIMATION", "cd", "yz011234", tmp_path, write_ctf)
        assert events == []
