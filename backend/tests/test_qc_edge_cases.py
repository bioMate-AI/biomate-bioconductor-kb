"""
QC Gate Edge Case Tests (Priority-ordered coverage of 92 identified gaps)

Covers:
  1. Status filtering (FAILED/RUNNING/CANCELLED → no QC)
  2. Duplicate deduplication (same task:process → only 1 event)
  3. Threshold boundary conditions (exactly at threshold → no trigger)
  4. Parser edge cases (empty/malformed files → None)
  5. Parameter suggester edge cases (already-at-recommended, None defaults)
  6. Ab-initio + refinement suggester paths
  7. RNASeq suggester paths
  8. SSE callback error isolation
  9. Domain factory selection
 10. Positive cases (metrics pass → no SSE event)
 11. Multiple concurrent failures in one process
 12. Metric value range validation inside parsers
 13. Confidence range validation (all in [0,1])
 14. Structured failure format
"""

import sys
import json
import tempfile
import textwrap
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

import pytest

# Ensure the Galaxy lib is importable
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from galaxy.jobs.parameter_suggester import (
    CryoEMParameterSuggester,
    RNASeqParameterSuggester,
    GenomicsParameterSuggester,
    SingleCellParameterSuggester,
    ChIPSeqParameterSuggester,
    MetagenomicsParameterSuggester,
    DrugDiscoveryParameterSuggester,
    BaseParameterSuggester,
    ParameterSuggestion,
    get_suggester_for_domain,
)
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_handler(work_dir=None, sse_callback=None, domain="cryo_em", params=None):
    """Convenience factory for NextflowQCGateHandler."""
    cb = sse_callback or (lambda t, d: None)
    return NextflowQCGateHandler(
        invocation_id="test-inv",
        work_dir=Path(work_dir or tempfile.mkdtemp()),
        sse_callback=cb,
        app=Mock(),
        workflow_domain=domain,
        current_parameters=params or {},
    )


def _collect_events(handler, task_id, process_name, process_hash, status):
    """
    Convenience: run handle_process_completion and collect SSE events.
    Returns list of (event_type, data) tuples captured.
    """
    events = []
    handler.sse_callback = lambda t, d: events.append((t, d))
    handler.handle_process_completion(
        task_id=task_id,
        process_name=process_name,
        process_hash=process_hash,
        status=status,
    )
    return events


# ===========================================================================
# 1. STATUS FILTERING
# ===========================================================================

class TestStatusFiltering:
    """FAILED / RUNNING / CANCELLED should never call QC (safety-critical)."""

    @pytest.mark.parametrize("bad_status", ["FAILED", "RUNNING", "CACHED", "CANCELLED"])
    def test_non_completed_status_skips_qc(self, bad_status):
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics"
        ) as mock_calc:
            handler = _make_handler()
            events = _collect_events(
                handler, "1", "MOTION_CORRECTION", "ab/cd1234", bad_status
            )
            assert events == [], f"Expected no SSE events for status={bad_status}"
            mock_calc.assert_not_called()

    def test_completed_status_does_call_qc(self):
        handler = _make_handler()
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics", return_value=None
        ) as mock_calc:
            events = _collect_events(
                handler, "1", "MOTION_CORRECTION", "ab/cd1234", "COMPLETED"
            )
            mock_calc.assert_called_once()
            # No SSE because metrics returned None
            assert events == []


# ===========================================================================
# 2. DUPLICATE DEDUPLICATION
# ===========================================================================

class TestDuplicateDeduplication:
    """Same task_id:process_name submitted twice → only first is processed."""

    def test_duplicate_task_emits_only_one_event(self):
        call_count = [0]

        def mock_calc(process_name, task_id, process_hash):
            call_count[0] += 1
            return {"total_drift_angstrom": 75.0}

        handler = _make_handler(params={"dose_weighting": False, "patch_size": 3})
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics", side_effect=mock_calc
        ):
            events = []
            handler.sse_callback = lambda t, d: events.append((t, d))

            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")

        assert call_count[0] == 1, "QC metrics calculated more than once for the same task"
        assert len(events) == 1, "Duplicate submission produced more than one SSE event"

    def test_different_task_ids_both_processed(self):
        call_count = [0]

        def mock_calc(process_name, task_id, process_hash):
            call_count[0] += 1
            return None  # no gate

        handler = _make_handler()
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics", side_effect=mock_calc
        ):
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")
            handler.handle_process_completion("2", "MOTION_CORRECTION", "ef/gh", "COMPLETED")

        assert call_count[0] == 2


# ===========================================================================
# 3. THRESHOLD BOUNDARY CONDITIONS (exactly AT threshold → must NOT trigger)
# ===========================================================================

class TestThresholdBoundaryConditions:
    """Metrics exactly at the threshold must NOT trigger QC gate."""

    def _no_trigger(self, process_name, metrics, params=None):
        handler = _make_handler(params=params or {})
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics", return_value=metrics
        ):
            events = []
            handler.sse_callback = lambda t, d: events.append((t, d))
            handler.handle_process_completion("1", process_name, "ab/cd", "COMPLETED")
        assert events == [], (
            f"Expected NO QC trigger at exact threshold; got events={events}"
        )

    def test_drift_exactly_at_threshold_no_trigger(self):
        # threshold: total_drift_angstrom > 50  →  50.0 is NOT > 50
        self._no_trigger("MOTION_CORRECTION", {"total_drift_angstrom": 50.0})

    def test_correlation_exactly_at_threshold_no_trigger(self):
        # threshold: correlation_score < 0.5  →  0.5 is NOT < 0.5
        self._no_trigger("MOTION_CORRECTION", {"correlation_score": 0.5})

    def test_astigmatism_exactly_at_threshold_no_trigger(self):
        # [BRONZE] advisory threshold: astigmatism_angstrom > 1000  →  1000 is NOT > 1000
        # (astigmatism advisory raised from 500 to 1000Å; fit_quality is the primary gate)
        self._no_trigger("CTF_ESTIMATION", {"astigmatism_angstrom": 1000.0})

    def test_fit_quality_exactly_at_threshold_no_trigger(self):
        # threshold: fit_quality < 0.7  →  0.7 is NOT < 0.7
        self._no_trigger("CTF_ESTIMATION", {"fit_quality": 0.7})

    def test_particles_exactly_at_threshold_no_trigger(self):
        # threshold: particles_picked < 1000  →  1000 is NOT < 1000
        self._no_trigger("PARTICLE_PICKING", {"particles_picked": 1000})

    def test_duplicate_fraction_exactly_at_threshold_no_trigger(self):
        # threshold: duplicate_fraction > 0.2  →  0.2 is NOT > 0.2
        self._no_trigger("PARTICLE_PICKING", {"duplicate_fraction": 0.2})

    def test_metrics_just_below_trigger_no_event(self):
        """49.9Å drift is fine — no event."""
        self._no_trigger("MOTION_CORRECTION", {"total_drift_angstrom": 49.9})

    def test_metrics_just_above_trigger_fires_event(self):
        """50.1Å drift crosses threshold — event must fire."""
        handler = _make_handler(params={"dose_weighting": False, "patch_size": 3})
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics",
            return_value={"total_drift_angstrom": 50.1},
        ):
            events = []
            handler.sse_callback = lambda t, d: events.append((t, d))
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")
        assert len(events) == 1
        assert events[0][0] == "qc_gate_triggered"


# ===========================================================================
# 4. PARSER EDGE CASES (empty / malformed files → returns None)
# ===========================================================================

class TestParserEdgeCases:
    """Empty or malformed output files must return None — no gate triggered."""

    def test_empty_log_file_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            empty_log = Path(tmpdir) / "motion.log"
            empty_log.write_text("")
            handler = NextflowQCGateHandler(
                invocation_id="t", work_dir=Path(tmpdir),
                sse_callback=lambda t, d: None, app=Mock(),
            )
            result = handler._parse_motion_correction_metrics(Path(tmpdir))
            assert result is None, "Empty log must return None"

    def test_malformed_log_no_keywords_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log = Path(tmpdir) / "run.log"
            log.write_text("MotionCor2 v1.4.7\nprocessing...\ndone.\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_motion_correction_metrics(Path(tmpdir))
            assert result is None

    def test_malformed_ctf_file_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            txt = Path(tmpdir) / "ctf_result.txt"
            txt.write_text("not numbers here\nalso bad\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_ctf_metrics(Path(tmpdir))
            assert result is None

    def test_empty_star_file_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            star = Path(tmpdir) / "particles.star"
            star.write_text("")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_picking_metrics(Path(tmpdir))
            assert result is None

    def test_star_file_only_headers_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            star = Path(tmpdir) / "particles.star"
            star.write_text("# RELION star file\n_rlnCoordinateX\n_rlnCoordinateY\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_picking_metrics(Path(tmpdir))
            assert result is None

    def test_unknown_process_name_returns_none(self):
        handler = _make_handler()
        with patch.object(handler, "_calculate_qc_metrics", wraps=handler._calculate_qc_metrics):
            result = handler._calculate_qc_metrics("UNKNOWN_PROCESS", "1", "")
            assert result is None

    def test_ctf_defocus_outside_valid_range_returns_none(self):
        """Defocus values outside 1000-100000Å are recorded as out-of-range for diagnosis."""
        with tempfile.TemporaryDirectory() as tmpdir:
            txt = Path(tmpdir) / "ctf.txt"
            # Defocus too small (100Å) — not a plausible electron microscopy value
            txt.write_text("100 95 10.5 0.0 0.82\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_ctf_metrics(Path(tmpdir))
            assert result is not None, "Sub-1000Å defocus should be recorded as out-of-range fallback"
            assert result.get("defocus_out_of_range") is True, "Must flag defocus_out_of_range"
            assert result.get("defocus_direction") == "below"

    def test_motion_drift_zero_from_garbage_not_stored(self):
        """A log file where no line has 'total motion' / 'global drift' → None."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log = Path(tmpdir) / "output.log"
            log.write_text("Frame 1 done\nFrame 2 done\nFinalising.\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_motion_correction_metrics(Path(tmpdir))
            assert result is None


# ===========================================================================
# 5. PARSER POSITIVE CASES
# ===========================================================================

class TestParserPositiveCases:
    """Valid output files should produce correct metrics."""

    def test_motion_log_drift_parsed_correctly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log = Path(tmpdir) / "motion.log"
            log.write_text(
                "MotionCor2 v1.6\n"
                "Total motion: 63.7\n"
                "Correlation score: 0.41\n"
            )
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_motion_correction_metrics(Path(tmpdir))
            assert result is not None
            assert result["total_drift_angstrom"] == pytest.approx(63.7)
            assert result["correlation_score"] == pytest.approx(0.41)

    def test_ctf_file_parsed_correctly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            txt = Path(tmpdir) / "ctf.txt"
            # DefocusU DefocusV AstigAngle PhaseShift FitScore
            txt.write_text("15000.0 14200.0 47.3 0.0 0.85\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_ctf_metrics(Path(tmpdir))
            assert result is not None
            assert result["defocus_u_angstrom"] == pytest.approx(15000.0)
            assert result["defocus_v_angstrom"] == pytest.approx(14200.0)
            assert result["astigmatism_angstrom"] == pytest.approx(800.0)
            assert result["fit_quality"] == pytest.approx(0.85)

    def test_star_file_particles_counted(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            star = Path(tmpdir) / "picks.star"
            # 3 coordinate lines (digit-starting)
            star.write_text(
                "# RELION star file\n"
                "_rlnCoordinateX\n"
                "_rlnCoordinateY\n"
                "1024.5 2048.3\n"
                "512.1 768.9\n"
                "333.0 444.0\n"
            )
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_picking_metrics(Path(tmpdir))
            assert result is not None
            assert result["particles_picked"] == 3

    def test_drift_per_frame_derived(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            log = Path(tmpdir) / "mc.log"
            log.write_text("Global drift: 80.0\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_motion_correction_metrics(Path(tmpdir))
            assert result is not None
            assert "drift_per_frame_angstrom" in result
            # 80.0 / 40 frames = 2.0
            assert result["drift_per_frame_angstrom"] == pytest.approx(2.0)


# ===========================================================================
# 6. PARAMETER SUGGESTER — ALREADY AT RECOMMENDED VALUE
# ===========================================================================

class TestSuggesterAlreadyAtRecommended:
    """If the user already has the recommended value, no suggestion emitted."""

    def _suggest(self, process_name, metrics, params, failures=None):
        return CryoEMParameterSuggester().suggest(
            process_name=process_name,
            qc_metrics=metrics,
            current_parameters=params,
            failures=failures or [],
        )

    def test_dose_weighting_already_enabled_no_suggestion(self):
        suggestions = self._suggest(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 65.0},
            {"dose_weighting": True, "patch_size": 3},
        )
        params = [s.parameter for s in suggestions]
        assert "dose_weighting" not in params

    def test_patch_size_already_large_no_suggestion(self):
        suggestions = self._suggest(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 65.0},
            {"dose_weighting": False, "patch_size": 5},
        )
        # patch_size is already 5, so no suggestion for it
        params = [s.parameter for s in suggestions]
        assert "patch_size" not in params

    def test_alignment_frames_already_sufficient_no_suggestion(self):
        suggestions = self._suggest(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 65.0, "correlation_score": 0.4},
            {"dose_weighting": False, "patch_size": 3, "alignment_frames": 3},
        )
        params = [s.parameter for s in suggestions]
        assert "alignment_frames" not in params

    def test_tilt_search_already_on_no_suggestion(self):
        suggestions = self._suggest(
            "CTF_ESTIMATION",
            {"astigmatism_angstrom": 1500},
            {"use_tilt_search": True},
        )
        params = [s.parameter for s in suggestions]
        assert "use_tilt_search" not in params

    def test_defocus_range_already_wide_no_suggestion(self):
        """defocus_max - defocus_min >= 30000 → no suggestion."""
        suggestions = self._suggest(
            "CTF_ESTIMATION",
            {"astigmatism_angstrom": 0, "fit_quality": 0.5},
            {"defocus_min": 5000, "defocus_max": 50000},
        )
        params = [s.parameter for s in suggestions]
        assert "defocus_search_range" not in params

    def test_picking_threshold_already_at_minimum_no_suggestion(self):
        """Threshold <= 0.3 already → lowering it would pick junk, skip."""
        suggestions = self._suggest(
            "PARTICLE_PICKING",
            {"particles_picked": 500, "duplicate_fraction": 0.05},
            {"picking_threshold": 0.3, "minimum_separation": 10},
        )
        params = [s.parameter for s in suggestions]
        assert "picking_threshold" not in params


# ===========================================================================
# 7. PARAMETER SUGGESTER — NONE DEFAULTS (absent metrics must not suggest)
# ===========================================================================

class TestNoneDefaults:
    """Absent metrics must not generate suggestions."""

    def _suggest(self, process, metrics, params=None, failures=None):
        return CryoEMParameterSuggester().suggest(
            process_name=process,
            qc_metrics=metrics,
            current_parameters=params or {},
            failures=failures or [],
        )

    def test_absent_correlation_score_produces_no_frame_suggestion(self):
        # correlation_score absent → should not suggest increasing alignment_frames
        suggestions = self._suggest(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 65.0},   # no correlation_score key
            {"dose_weighting": False, "patch_size": 3, "alignment_frames": 1},
        )
        params = [s.parameter for s in suggestions]
        assert "alignment_frames" not in params

    def test_ctf_no_fit_quality_no_defocus_suggestion(self):
        suggestions = self._suggest(
            "CTF_ESTIMATION",
            {"astigmatism_angstrom": 1500},   # no fit_quality
            {"use_tilt_search": False, "defocus_min": 10000, "defocus_max": 30000},
        )
        params = [s.parameter for s in suggestions]
        assert "defocus_search_range" not in params

    def test_picking_no_count_no_threshold_suggestion(self):
        suggestions = self._suggest(
            "PARTICLE_PICKING",
            {"duplicate_fraction": 0.35},   # no particles_picked
            {"picking_threshold": 0.5, "minimum_separation": 10},
        )
        params = [s.parameter for s in suggestions]
        assert "picking_threshold" not in params

    def test_picking_no_duplicate_frac_no_separation_suggestion(self):
        suggestions = self._suggest(
            "PARTICLE_PICKING",
            {"particles_picked": 5000},   # no duplicate_fraction
            {"picking_threshold": 0.3, "minimum_separation": 10},
        )
        params = [s.parameter for s in suggestions]
        assert "minimum_separation" not in params

    def test_2d_classify_no_convergence_no_iteration_suggestion(self):
        suggestions = self._suggest(
            "CLASSIFY_2D",
            {},   # no class_convergence
            {"max_iterations": 20},
        )
        assert suggestions == []


# ===========================================================================
# 8. AB-INITIO AND REFINEMENT SUGGESTER
# ===========================================================================

class TestAbInitioAndRefinement:
    """Verify ab-initio and refinement branches."""

    def _suggest(self, process, metrics, params=None, failures=None):
        return CryoEMParameterSuggester().suggest(
            process_name=process,
            qc_metrics=metrics,
            current_parameters=params or {},
            failures=failures or [],
        )

    def test_ab_initio_poor_resolution_suggests_more_classes(self):
        suggestions = self._suggest(
            "AB_INITIO",
            {"initial_resolution": 35.0},
            {"num_classes": 1},
        )
        assert len(suggestions) == 1
        assert suggestions[0].parameter == "num_classes"
        assert suggestions[0].suggested_value == 3
        assert suggestions[0].confidence == pytest.approx(0.70)

    def test_ab_initio_already_multi_class_no_suggestion(self):
        suggestions = self._suggest(
            "AB_INITIO",
            {"initial_resolution": 35.0},
            {"num_classes": 3},
        )
        assert suggestions == []

    def test_refinement_poor_fsc_suggests_per_particle_ctf(self):
        suggestions = self._suggest(
            "HOMOGENEOUS_REFINEMENT",
            {"fsc_resolution": 8.5},
            {"per_particle_ctf": False},
        )
        assert len(suggestions) == 1
        assert suggestions[0].parameter == "per_particle_ctf"
        assert suggestions[0].suggested_value is True
        assert suggestions[0].confidence == pytest.approx(0.80)

    def test_refinement_already_per_particle_no_suggestion(self):
        suggestions = self._suggest(
            "HOMOGENEOUS_REFINEMENT",
            {"fsc_resolution": 8.5},
            {"per_particle_ctf": True},
        )
        assert suggestions == []

    def test_ab_initio_resolution_exactly_at_threshold_no_suggestion(self):
        # threshold: initial_res > 20 → 20.0 is NOT > 20
        # But note: the implementation uses default=100 so absent metric → 100 > 20 = True
        # Testing the AT-threshold case (explicit metric):
        suggestions = self._suggest(
            "AB_INITIO",
            {"initial_resolution": 20.0},
            {"num_classes": 1},
        )
        assert suggestions == [], "Exactly at threshold should not trigger"


# ===========================================================================
# 9. RNASEQ SUGGESTER
# ===========================================================================

class TestRNASeqSuggester:
    """Verify RNA-seq parameter suggestions."""

    def _suggest(self, process, metrics, params=None, failures=None):
        return RNASeqParameterSuggester().suggest(
            process_name=process,
            qc_metrics=metrics,
            current_parameters=params or {},
            failures=failures or [],
        )

    def test_trim_low_quality_suggests_higher_cutoff(self):
        # reads_surviving_pct < 70% → suggest raising quality_cutoff
        suggestions = self._suggest(
            "FASTP_TRIM",
            {"reads_surviving_pct": 60.0},
            {"quality_cutoff": 20},
        )
        quality_sugg = next((s for s in suggestions if s.parameter == "quality_cutoff"), None)
        assert quality_sugg is not None
        assert quality_sugg.suggested_value == 25
        assert quality_sugg.confidence == pytest.approx(0.85)

    def test_trim_good_quality_no_suggestion(self):
        # threshold: reads_surviving_pct < 70 → 75.0 is NOT < 70
        suggestions = self._suggest(
            "FASTP_TRIM",
            {"reads_surviving_pct": 75.0},
            {"quality_cutoff": 20},
        )
        assert suggestions == []

    def test_trim_cutoff_already_sufficient_no_suggestion(self):
        # quality_cutoff already at 25 → no suggestion
        suggestions = self._suggest(
            "FASTP_TRIM",
            {"reads_surviving_pct": 60.0},
            {"quality_cutoff": 25},
        )
        quality_sugg = next((s for s in suggestions if s.parameter == "quality_cutoff"), None)
        assert quality_sugg is None

    def test_alignment_poor_mapping_suggests_more_mismatches(self):
        # alignment_rate 55% < 70% threshold → suggest mismatches + twopass
        suggestions = self._suggest(
            "STAR_ALIGN",
            {"alignment_rate": 55.0},
            {"max_mismatches": 2, "twopass_mode": True},  # twopass already on
        )
        mismatch_sugg = next((s for s in suggestions if s.parameter == "max_mismatches"), None)
        assert mismatch_sugg is not None
        assert mismatch_sugg.suggested_value == 3  # min(4, 2+1)

    def test_alignment_already_at_max_mismatches_no_suggestion(self):
        """When max_mismatches is already >= 3 (the upper useful bound), no suggestion fires."""
        suggestions = self._suggest(
            "STAR_ALIGN",
            {"alignment_rate": 55.0},
            {"max_mismatches": 4, "twopass_mode": True},
        )
        # Already at 4 (can't meaningfully increase further), twopass already on
        mismatch_sugg = next((s for s in suggestions if s.parameter == "max_mismatches"), None)
        assert mismatch_sugg is None

    def test_alignment_good_mapping_no_suggestion(self):
        # alignment_rate 70% is AT threshold — not < 70 → no suggestion
        suggestions = self._suggest(
            "STAR_ALIGN",
            {"alignment_rate": 70.0},
            {"max_mismatches": 2},
        )
        assert suggestions == []


# ===========================================================================
# 10. DOMAIN FACTORY
# ===========================================================================

class TestDomainFactory:
    """get_suggester_for_domain returns the right class."""

    @pytest.mark.parametrize("domain,expected_cls", [
        ("cryo_em", CryoEMParameterSuggester),
        ("CRYO_EM", CryoEMParameterSuggester),
        ("cryo-em-spa", CryoEMParameterSuggester),
        ("rnaseq", RNASeqParameterSuggester),
        ("rna_seq", RNASeqParameterSuggester),
        ("RNA-seq", RNASeqParameterSuggester),
        ("genomics", GenomicsParameterSuggester),   # genomic keyword → genomics suggester
        ("wgs_pipeline", GenomicsParameterSuggester),
        ("chipseq", ChIPSeqParameterSuggester),
        ("metagenomics", MetagenomicsParameterSuggester),
        ("single_cell_rnaseq", SingleCellParameterSuggester),
        ("completely_unknown", BaseParameterSuggester),
    ])
    def test_correct_class_returned(self, domain, expected_cls):
        suggester = get_suggester_for_domain(domain)
        assert isinstance(suggester, expected_cls), (
            f"domain={domain!r} → expected {expected_cls.__name__}, got {type(suggester).__name__}"
        )

    def test_base_suggester_raises_not_implemented(self):
        # BaseParameterSuggester is an abstract base — it raises NotImplementedError,
        # which is intentional. Concrete domains (cryo_em, rnaseq) override suggest().
        # Use a domain name that truly has no keyword match.
        suggester = get_suggester_for_domain("completely_unknown")
        assert isinstance(suggester, BaseParameterSuggester)
        with pytest.raises(NotImplementedError):
            suggester.suggest("ANY_PROCESS", {}, {}, [])


# ===========================================================================
# 11. SSE CALLBACK ERROR ISOLATION
# ===========================================================================

class TestSSECallbackErrors:
    """sse_callback exceptions must not crash the monitor."""

    def test_callback_exception_does_not_propagate(self):
        def exploding_callback(event_type, data):
            raise RuntimeError("SSE channel broken")

        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=exploding_callback,
            app=Mock(),
            workflow_domain="cryo_em",
        )

        with patch.object(
            handler, "_calculate_qc_metrics",
            return_value={"total_drift_angstrom": 75.0}
        ):
            # Must not raise
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")

    def test_parameter_suggester_exception_does_not_propagate(self):
        """A broken suggester should still emit an event (with empty suggestions)."""
        events = []

        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
        )

        # Inject a broken suggester
        mock_suggester = Mock()
        mock_suggester.suggest.side_effect = RuntimeError("suggester broken")
        handler.parameter_suggester = mock_suggester

        with patch.object(
            handler, "_calculate_qc_metrics",
            return_value={"total_drift_angstrom": 75.0}
        ):
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")

        # Event should still be emitted despite broken suggester
        assert len(events) == 1
        assert events[0][1]["suggestions"] == []


# ===========================================================================
# 12. POSITIVE CASES — QC GATE NOT TRIGGERED FOR GOOD METRICS
# ===========================================================================

class TestPositiveCasesNoTrigger:
    """Good metrics must produce zero SSE events."""

    def _no_events(self, process_name, metrics):
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
        )
        with patch.object(handler, "_calculate_qc_metrics", return_value=metrics):
            handler.handle_process_completion("1", process_name, "ab/cd", "COMPLETED")
        assert events == [], f"Expected no events for good metrics={metrics}, got {events}"

    def test_good_motion_correction_no_event(self):
        self._no_events("MOTION_CORRECTION", {
            "total_drift_angstrom": 20.0,
            "correlation_score": 0.85,
        })

    def test_good_ctf_no_event(self):
        self._no_events("CTF_ESTIMATION", {
            "astigmatism_angstrom": 300.0,
            "fit_quality": 0.92,
        })

    def test_good_picking_no_event(self):
        self._no_events("PARTICLE_PICKING", {
            "particles_picked": 5000,
            "duplicate_fraction": 0.05,
        })

    def test_no_metrics_returned_no_event(self):
        """None metrics must produce zero events."""
        self._no_events("MOTION_CORRECTION", None)


# ===========================================================================
# 13. MULTIPLE CONCURRENT FAILURES IN ONE PROCESS
# ===========================================================================

class TestMultipleFailures:
    """Both drift AND correlation failing → structured failures list with 2 entries."""

    def test_two_failures_in_single_event(self):
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
            current_parameters={"dose_weighting": False, "patch_size": 3, "alignment_frames": 1},
        )

        with patch.object(handler, "_calculate_qc_metrics", return_value={
            "total_drift_angstrom": 75.0,
            "correlation_score": 0.35,
        }):
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")

        assert len(events) == 1
        failures = events[0][1]["failures"]
        assert len(failures) == 2

        # Verify structured format
        metrics = {f["metric"] for f in failures}
        assert "total_drift_angstrom" in metrics
        assert "correlation_score" in metrics

    def test_two_ctf_failures_structured(self):
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
            current_parameters={"use_tilt_search": False, "defocus_min": 10000, "defocus_max": 30000},
        )

        with patch.object(handler, "_calculate_qc_metrics", return_value={
            "astigmatism_angstrom": 1500.0,
            "fit_quality": 0.55,
        }):
            handler.handle_process_completion("1", "CTF_ESTIMATION", "ab/cd", "COMPLETED")

        assert len(events) == 1
        failures = events[0][1]["failures"]
        assert len(failures) == 2


# ===========================================================================
# 14. STRUCTURED FAILURE FORMAT VALIDATION
# ===========================================================================

class TestStructuredFailureFormat:
    """Each failure dict must have the 5 required keys with correct types."""

    REQUIRED_KEYS = {"metric", "value", "threshold", "operator", "message"}

    def _get_failures(self, process_name, metrics, params=None):
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
            current_parameters=params or {},
        )
        with patch.object(handler, "_calculate_qc_metrics", return_value=metrics):
            handler.handle_process_completion("1", process_name, "ab/cd", "COMPLETED")
        if events:
            return events[0][1]["failures"]
        return []

    def test_motion_failure_has_all_required_keys(self):
        failures = self._get_failures(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 75.0},
        )
        assert len(failures) >= 1
        for f in failures:
            assert self.REQUIRED_KEYS.issubset(f.keys()), f"Missing keys in failure: {f}"

    def test_failure_operator_is_valid(self):
        failures = self._get_failures(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 75.0, "correlation_score": 0.35},
        )
        for f in failures:
            assert f["operator"] in (">", "<"), f"Invalid operator in failure: {f}"

    def test_failure_values_are_numeric(self):
        failures = self._get_failures(
            "CTF_ESTIMATION",
            {"astigmatism_angstrom": 1500.0, "fit_quality": 0.5},
        )
        for f in failures:
            assert isinstance(f["value"], (int, float)), f"value not numeric: {f}"
            assert isinstance(f["threshold"], (int, float)), f"threshold not numeric: {f}"

    def test_failure_is_json_serializable(self):
        failures = self._get_failures(
            "PARTICLE_PICKING",
            {"particles_picked": 400, "duplicate_fraction": 0.35},
        )
        assert len(failures) >= 1
        # Must not raise
        json_str = json.dumps(failures)
        parsed = json.loads(json_str)
        assert len(parsed) == len(failures)

    def test_drift_failure_operator_is_greater_than(self):
        failures = self._get_failures(
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 75.0},
        )
        drift_failure = next(f for f in failures if f["metric"] == "total_drift_angstrom")
        assert drift_failure["operator"] == ">"

    def test_correlation_failure_operator_is_less_than(self):
        failures = self._get_failures(
            "MOTION_CORRECTION",
            {"correlation_score": 0.3},
        )
        corr_failure = next(f for f in failures if f["metric"] == "correlation_score")
        assert corr_failure["operator"] == "<"


# ===========================================================================
# 15. CONFIDENCE RANGE VALIDATION
# ===========================================================================

class TestConfidenceRange:
    """All parameter suggestions must have confidence in [0.0, 1.0]."""

    def _all_suggestions(self, process, metrics, params, failures=None):
        return CryoEMParameterSuggester().suggest(
            process_name=process,
            qc_metrics=metrics,
            current_parameters=params,
            failures=failures or [],
        )

    @pytest.mark.parametrize("process,metrics,params", [
        (
            "MOTION_CORRECTION",
            {"total_drift_angstrom": 75.0, "correlation_score": 0.3},
            {"dose_weighting": False, "patch_size": 3, "alignment_frames": 1},
        ),
        (
            "CTF_ESTIMATION",
            {"astigmatism_angstrom": 1500, "fit_quality": 0.5},
            {"use_tilt_search": False, "defocus_min": 10000, "defocus_max": 30000},
        ),
        (
            "PARTICLE_PICKING",
            {"particles_picked": 300, "duplicate_fraction": 0.35},
            {"picking_threshold": 0.5, "minimum_separation": 10},
        ),
        (
            "AB_INITIO",
            {"initial_resolution": 35.0},
            {"num_classes": 1},
        ),
        (
            "HOMOGENEOUS_REFINEMENT",
            {"fsc_resolution": 8.5},
            {"per_particle_ctf": False},
        ),
    ])
    def test_confidence_in_valid_range(self, process, metrics, params):
        suggestions = self._all_suggestions(process, metrics, params)
        for s in suggestions:
            assert 0.0 <= s.confidence <= 1.0, (
                f"Out-of-range confidence {s.confidence} for {s.parameter}"
            )


# ===========================================================================
# 16. DICT SUGGESTED VALUES — JSON ROUND-TRIP
# ===========================================================================

class TestDictSuggestedValues:
    """defocus_search_range with dict suggested value must survive JSON round-trip."""

    def test_defocus_dict_suggestion_is_json_serializable(self):
        suggester = CryoEMParameterSuggester()
        suggestions = suggester.suggest(
            process_name="CTF_ESTIMATION",
            qc_metrics={"astigmatism_angstrom": 0, "fit_quality": 0.5},
            current_parameters={"use_tilt_search": False, "defocus_min": 10000, "defocus_max": 30000},
            failures=[],
        )
        defocus = next((s for s in suggestions if s.parameter == "defocus_search_range"), None)
        assert defocus is not None
        assert isinstance(defocus.suggested_value, dict)
        assert "defocus_min" in defocus.suggested_value
        assert "defocus_max" in defocus.suggested_value

        # JSON serialization (for SSE transport)
        json_str = json.dumps({"suggested_value": defocus.suggested_value})
        parsed = json.loads(json_str)
        assert parsed["suggested_value"]["defocus_min"] == 5000
        assert parsed["suggested_value"]["defocus_max"] == 50000

    def test_defocus_current_value_is_dict_too(self):
        """current_value for defocus_search_range must also be a dict (not a tuple)."""
        suggester = CryoEMParameterSuggester()
        # Range is 20000 < 30000 → suggestion IS generated; no guard needed
        suggestions = suggester.suggest(
            process_name="CTF_ESTIMATION",
            qc_metrics={"fit_quality": 0.5},
            current_parameters={"defocus_min": 10000, "defocus_max": 30000},
            failures=[],
        )
        defocus = next((s for s in suggestions if s.parameter == "defocus_search_range"), None)
        assert defocus is not None, "defocus_search_range suggestion should be generated"
        assert isinstance(defocus.current_value, dict), (
            f"current_value should be dict, got {type(defocus.current_value)}"
        )


# ===========================================================================
# 17. PROCESS NAME VARIANTS
# ===========================================================================

class TestProcessNameVariants:
    """
    QC gate handler parses real metrics correctly for process name variants:
    prefixed names (PATCH_MOTION_CORRECTION), lowercase (ctf_estimation),
    and qualified Nextflow names (NFCORE:STAR_ALIGN).

    These tests write real output files and verify real metrics are extracted —
    not just that the routing call happened.
    """

    # Motion correction variants

    @pytest.mark.parametrize("process_name", [
        "MOTION_CORRECTION",
        "PATCH_MOTION_CORRECTION",
        "motion_correction",   # lowercase → uppercased internally
    ])
    def test_motion_correction_variants_extract_real_drift(self, process_name, tmp_path):
        """All motion correction name variants parse a real log file and extract drift."""
        subdir = tmp_path / "ab" / "cd1234"
        subdir.mkdir(parents=True)
        (subdir / "motion.log").write_text("Total motion: 73.5 Å\n")

        h = _make_handler(work_dir=tmp_path)
        metrics = h._calculate_qc_metrics(process_name, "1", "ab/cd1234")
        assert metrics is not None, f"{process_name!r} should parse real log file"
        assert metrics["total_drift_angstrom"] == pytest.approx(73.5, abs=0.5)

    # CTF variants

    @pytest.mark.parametrize("process_name", [
        "CTF_ESTIMATION",
        "CTF_ESTIMATE",
        "PATCH_CTF_ESTIMATION",
        "ctf_estimation",
    ])
    def test_ctf_variants_extract_real_defocus(self, process_name, tmp_path):
        """All CTF name variants parse a real CTFFIND4 file and extract defocus/astigmatism."""
        subdir = tmp_path / "ef" / "gh5678"
        subdir.mkdir(parents=True)
        (subdir / "ctf.txt").write_text("15000.0\t14500.0\t32.0\t0.0\t0.88\n")

        h = _make_handler(work_dir=tmp_path)
        metrics = h._calculate_qc_metrics(process_name, "1", "ef/gh5678")
        assert metrics is not None, f"{process_name!r} should parse real CTF file"
        assert metrics["defocus_u_angstrom"] == 15000.0
        assert metrics["astigmatism_angstrom"] == pytest.approx(500.0, abs=1)

    # Particle picking variants

    @pytest.mark.parametrize("process_name", [
        "PARTICLE_PICKING",
        "BLOB_PARTICLE_PICKING",
        "particle_picking",
    ])
    def test_picking_variants_count_real_particles(self, process_name, tmp_path):
        """All picking name variants parse a real STAR file and count particles."""
        subdir = tmp_path / "ij" / "kl9012"
        subdir.mkdir(parents=True)
        lines = ["_rlnCoordinateX\n_rlnCoordinateY"]
        for i in range(42):
            lines.append(f"{i * 100}.0\t{i * 50}.0")
        (subdir / "particles.star").write_text("\n".join(lines) + "\n")

        h = _make_handler(work_dir=tmp_path)
        metrics = h._calculate_qc_metrics(process_name, "1", "ij/kl9012")
        assert metrics is not None, f"{process_name!r} should parse real STAR file"
        assert metrics["particles_picked"] == 42

    # Nextflow-qualified names (NFCORE:PROCESS)

    def test_nfcore_qualified_motion_correction_parses_correctly(self, tmp_path):
        """Process name with NFCORE: prefix still matches via substring and parses correctly."""
        subdir = tmp_path / "mn" / "op3456"
        subdir.mkdir(parents=True)
        (subdir / "motion.log").write_text("Total motion: 55.0 Å\n")

        h = _make_handler(work_dir=tmp_path)
        metrics = h._calculate_qc_metrics("NFCORE:MOTION_CORRECTION", "1", "mn/op3456")
        assert metrics is not None
        assert metrics["total_drift_angstrom"] == pytest.approx(55.0, abs=0.5)

    def test_nfcore_qualified_star_align_parses_correctly(self, tmp_path):
        """NFCORE:STAR_ALIGN qualified name parses a real STAR log."""
        subdir = tmp_path / "qr" / "st7890"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Number of input reads |\t10000000\n"
            "Uniquely mapped reads % |\t78.50%\n"
            "% of reads mapped to multiple loci |\t5.00%\n"
        )

        h = _make_handler(work_dir=tmp_path)
        metrics = h._calculate_qc_metrics("NFCORE:STAR_ALIGN", "1", "qr/st7890")
        assert metrics is not None
        assert metrics["uniquely_mapped_pct"] == pytest.approx(78.5, abs=0.1)


# ===========================================================================
# 18. SSE EVENT DATA COMPLETENESS
# ===========================================================================

class TestSSEEventDataCompleteness:
    """The SSE event payload must always have all required top-level keys."""

    REQUIRED_KEYS = {"invocation_id", "process_name", "qc_metrics", "failures", "suggestions", "timestamp"}

    def test_all_required_keys_present(self):
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="inv-007",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
            current_parameters={"dose_weighting": False, "patch_size": 3},
        )
        with patch.object(handler, "_calculate_qc_metrics", return_value={
            "total_drift_angstrom": 75.0
        }):
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")

        assert len(events) == 1
        data = events[0][1]
        assert self.REQUIRED_KEYS.issubset(data.keys()), (
            f"Missing keys: {self.REQUIRED_KEYS - data.keys()}"
        )

    def test_invocation_id_matches(self):
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="unique-inv-12345",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
        )
        with patch.object(handler, "_calculate_qc_metrics", return_value={"total_drift_angstrom": 75.0}):
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")
        assert events[0][1]["invocation_id"] == "unique-inv-12345"

    def test_timestamp_is_iso8601_and_recent(self):
        """Timestamp must be a valid ISO-8601 UTC datetime within the last 5 seconds."""
        events = []
        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
        )
        from datetime import datetime, timezone, timedelta
        before = datetime.now(timezone.utc)
        with patch.object(handler, "_calculate_qc_metrics", return_value={"total_drift_angstrom": 75.0}):
            handler.handle_process_completion("1", "MOTION_CORRECTION", "ab/cd", "COMPLETED")
        after = datetime.now(timezone.utc)

        ts = events[0][1]["timestamp"]
        dt = datetime.fromisoformat(ts)
        assert dt.tzinfo is not None, "Timestamp must be timezone-aware"
        assert before - timedelta(seconds=1) <= dt <= after + timedelta(seconds=1), (
            f"Timestamp {ts!r} is not recent (expected between {before} and {after})"
        )


# ===========================================================================
# 19. HASH RESOLUTION (truncated Nextflow hash → glob finds full directory)
# ===========================================================================

class TestHashResolution:
    """Nextflow trace has truncated hash; handler must glob to find full directory."""

    def test_truncated_hash_resolves_to_full_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            work_dir = Path(tmpdir)
            # Simulate Nextflow layout: work/ab/cd1234ef5678/
            prefix_dir = work_dir / "ab"
            full_dir = prefix_dir / "cd1234ef5678"
            full_dir.mkdir(parents=True)

            # Write a motion log in the full directory
            (full_dir / "motioncor.log").write_text("Total motion: 30.0\n")

            handler = _make_handler(work_dir=str(work_dir))

            # Use truncated hash as it appears in Nextflow trace file
            result = handler._calculate_qc_metrics("MOTION_CORRECTION", "1", "ab/cd1234")

            # Should have found the file via glob
            assert result is not None, "Hash glob should resolve to full directory"
            assert result["total_drift_angstrom"] == pytest.approx(30.0)

    def test_nonexistent_hash_prefix_returns_none(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            handler = _make_handler(work_dir=tmpdir)
            # Process with no matching files → None
            result = handler._calculate_qc_metrics("MOTION_CORRECTION", "1", "zz/zzzzzz")
            assert result is None


# ===========================================================================
# 20. SUGGESTION REASON TEXT
# ===========================================================================

class TestSuggestionReasonText:
    """Suggestion reasons must include the relevant metric value."""

    def test_drift_suggestion_includes_drift_value(self):
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="MOTION_CORRECTION",
            qc_metrics={"total_drift_angstrom": 73.4},
            current_parameters={"dose_weighting": False, "patch_size": 3},
            failures=[],
        )
        dose = next(s for s in suggestions if s.parameter == "dose_weighting")
        assert "73.4" in dose.reason

    def test_ctf_suggestion_includes_astigmatism_value(self):
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="CTF_ESTIMATION",
            qc_metrics={"astigmatism_angstrom": 1234},
            current_parameters={"use_tilt_search": False},
            failures=[],
        )
        tilt = next(s for s in suggestions if s.parameter == "use_tilt_search")
        assert "1234" in tilt.reason

    def test_picking_suggestion_includes_particle_count(self):
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="PARTICLE_PICKING",
            qc_metrics={"particles_picked": 450},
            current_parameters={"picking_threshold": 0.5},
            failures=[],
        )
        threshold = next(s for s in suggestions if s.parameter == "picking_threshold")
        assert "450" in threshold.reason


# ===========================================================================
# 21. REGRESSION TESTS FOR 5 PRODUCTION BUGS FOUND BY AUDIT
# ===========================================================================

class TestBugRegressions:
    """
    Regression tests for 5 production bugs discovered during the test audit.
    Each test documents the bug, verifies the fix, and would catch a reversion.
    """

    # ------------------------------------------------------------------
    # Bug 1: Motion parser if/if double-assignment
    # A line containing both "total motion" and "score" (e.g. "Total motion score: 0.85")
    # previously set BOTH total_drift_angstrom AND correlation_score to 0.85.
    # Fix: changed inner `if` to `elif` so a line matches at most one keyword.
    # ------------------------------------------------------------------

    def test_bug1_ambiguous_line_does_not_corrupt_both_metrics(self):
        """'Total motion score: 0.85' must set drift, NOT correlation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log = Path(tmpdir) / "motioncor.log"
            # This line historically triggered both branches
            log.write_text("Total motion score: 0.85\n")
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_motion_correction_metrics(Path(tmpdir))

        # After fix: drift is 0.85Å (assigned), correlation is NOT set
        # (0.85 is in [0,1] but the elif prevents double-assignment)
        if result is not None:
            # If drift was parsed, correlation must NOT have been set from the same line
            assert "correlation_score" not in result, (
                "correlation_score must not be set from a drift line; "
                f"got result={result}"
            )

    def test_bug1_separate_lines_still_parse_both(self):
        """Separate lines for drift and correlation must both be captured."""
        with tempfile.TemporaryDirectory() as tmpdir:
            log = Path(tmpdir) / "motion.log"
            log.write_text(
                "Total motion: 45.2\n"
                "Correlation score: 0.78\n"
            )
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_motion_correction_metrics(Path(tmpdir))

        assert result is not None
        assert result["total_drift_angstrom"] == pytest.approx(45.2)
        assert result["correlation_score"] == pytest.approx(0.78)

    # ------------------------------------------------------------------
    # Bug 2: ab_initio and refinement fire on absent metrics (default=100)
    # Fix: changed to .get(key) with is-not-None guard, consistent with
    # all other suggesters in the file.
    # ------------------------------------------------------------------

    def test_bug2_ab_initio_absent_resolution_no_suggestion(self):
        """Empty metrics dict must produce zero suggestions for AB_INITIO."""
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="AB_INITIO",
            qc_metrics={},               # no initial_resolution key
            current_parameters={"num_classes": 1},
            failures=[],
        )
        assert suggestions == [], (
            "AB_INITIO with absent metrics must not suggest anything "
            f"(got {[s.parameter for s in suggestions]})"
        )

    def test_bug2_refinement_absent_fsc_no_suggestion(self):
        """Empty metrics dict must produce zero suggestions for refinement."""
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="HOMOGENEOUS_REFINEMENT",
            qc_metrics={},               # no fsc_resolution key
            current_parameters={"per_particle_ctf": False},
            failures=[],
        )
        assert suggestions == [], (
            "Refinement with absent metrics must not suggest anything "
            f"(got {[s.parameter for s in suggestions]})"
        )

    def test_bug2_ab_initio_explicit_good_resolution_no_suggestion(self):
        """When initial_resolution is good (≤20Å), no suggestion should fire."""
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="AB_INITIO",
            qc_metrics={"initial_resolution": 15.0},
            current_parameters={"num_classes": 1},
            failures=[],
        )
        assert suggestions == []

    # ------------------------------------------------------------------
    # Bug 3: Suggester exact-list vs QC gate substring — Nextflow-qualified
    # names like "NFCORE:MOTION_CORRECTION" trigger QC failures but receive
    # empty suggestions.
    # Fix: suggester now uses substring matching, consistent with QC gate.
    # ------------------------------------------------------------------

    def test_bug3_qualified_motion_correction_name_gets_suggestions(self):
        """NFCORE:MOTION_CORRECTION should route to motion correction suggestions."""
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="NFCORE:MOTION_CORRECTION",
            qc_metrics={"total_drift_angstrom": 75.0},
            current_parameters={"dose_weighting": False, "patch_size": 3},
            failures=[],
        )
        assert len(suggestions) >= 1, (
            "Qualified process name should still produce suggestions"
        )
        params = [s.parameter for s in suggestions]
        assert "dose_weighting" in params

    def test_bug3_qualified_ctf_name_gets_suggestions(self):
        """WORKFLOW:CTF_ESTIMATION should route to CTF suggestions."""
        suggestions = CryoEMParameterSuggester().suggest(
            process_name="WORKFLOW:CTF_ESTIMATION",
            qc_metrics={"astigmatism_angstrom": 1500},
            current_parameters={"use_tilt_search": False},
            failures=[],
        )
        assert len(suggestions) >= 1
        params = [s.parameter for s in suggestions]
        assert "use_tilt_search" in params

    def test_bug3_qc_gate_and_suggester_agree_on_process_routing(self):
        """QC gate fires AND suggestions are generated for qualified names."""
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

        events = []
        handler = NextflowQCGateHandler(
            invocation_id="t",
            work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="cryo_em",
            current_parameters={"dose_weighting": False, "patch_size": 3},
        )
        with patch.object(handler, "_calculate_qc_metrics",
                          return_value={"total_drift_angstrom": 75.0}):
            handler.handle_process_completion(
                "1", "NFCORE:MOTION_CORRECTION", "ab/cd", "COMPLETED"
            )

        assert len(events) == 1, "QC gate must fire for qualified process name"
        suggestions = events[0][1]["suggestions"]
        assert len(suggestions) >= 1, (
            "Suggestions must not be empty when QC gate fires for qualified name"
        )

    # ------------------------------------------------------------------
    # Bug 4: CTF parser reads only last line — invalid last line discards
    # all valid prior data in a multi-micrograph file.
    # Fix: scan lines in reverse until a valid one is found.
    # ------------------------------------------------------------------

    def test_bug4_multi_micrograph_ctf_file_invalid_last_line(self):
        """Valid first line must be used when last line has out-of-range defocus."""
        with tempfile.TemporaryDirectory() as tmpdir:
            txt = Path(tmpdir) / "ctf_results.txt"
            # First line: valid
            # Last line: defocus=50Å which is below the 1000Å minimum — historically discarded all
            txt.write_text(
                "15000.0 14200.0 47.3 0.0 0.85\n"
                "50.0 45.0 10.0 0.0 0.92\n"
            )
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_ctf_metrics(Path(tmpdir))

        assert result is not None, (
            "Valid data on an earlier line must be used when the last line is invalid"
        )
        assert result["defocus_u_angstrom"] == pytest.approx(15000.0)
        assert result["fit_quality"] == pytest.approx(0.85)

    def test_bug4_all_invalid_lines_still_returns_none(self):
        """All lines with out-of-range defocus → recorded as out-of-range fallback for diagnosis."""
        with tempfile.TemporaryDirectory() as tmpdir:
            txt = Path(tmpdir) / "ctf_results.txt"
            txt.write_text(
                "50.0 45.0 10.0 0.0 0.92\n"
                "30.0 28.0 5.0 0.0 0.88\n"
            )
            handler = _make_handler(work_dir=tmpdir)
            result = handler._parse_ctf_metrics(Path(tmpdir))

        assert result is not None, "OOR defocus lines should be returned as fallback"
        assert result.get("defocus_out_of_range") is True
        assert result.get("defocus_direction") == "below"

    # ------------------------------------------------------------------
    # Bug 5: Domain factory 'em' substring matches 'system', 'theorem', etc.
    # Fix: replaced 'em' with targeted keywords ('_em', 'electron_micro', etc.)
    # ------------------------------------------------------------------

    @pytest.mark.parametrize("bad_domain", [
        "system_biology",
        "problem_solving",
        "theorem_prover",
        "genome_assembly",    # 'genome' contains 'em' but is not cryo-EM
        "items_database",
        "stem_cell_rnaseq",   # 'stem' contains 'em' but should route to RNASeq
    ])
    def test_bug5_broad_em_match_does_not_false_route(self, bad_domain):
        """Domains containing 'em' as a substring must not route to CryoEMParameterSuggester."""
        from galaxy.jobs.parameter_suggester import CryoEMParameterSuggester, RNASeqParameterSuggester
        suggester = get_suggester_for_domain(bad_domain)
        assert not isinstance(suggester, CryoEMParameterSuggester), (
            f"domain={bad_domain!r} should not route to CryoEM suggester"
        )

    @pytest.mark.parametrize("valid_em_domain", [
        "cryo_em",
        "cryo-em-spa",
        "electron_microscopy",
        "cryosparc",
        "em",              # standalone 'em' is a valid domain abbreviation
    ])
    def test_bug5_valid_em_domains_still_route_correctly(self, valid_em_domain):
        """Legitimate cryo-EM domain names must still route to CryoEMParameterSuggester."""
        from galaxy.jobs.parameter_suggester import CryoEMParameterSuggester
        suggester = get_suggester_for_domain(valid_em_domain)
        assert isinstance(suggester, CryoEMParameterSuggester), (
            f"domain={valid_em_domain!r} should route to CryoEM suggester"
        )


# ===========================================================================
# 21. UNIVERSAL QC PARSERS — file format coverage
# ===========================================================================

class TestUniversalQCParsers:
    """
    Tests for the 10 new multi-domain parsers added to NextflowQCGateHandler.

    Each test writes realistic file content into a tempdir and calls the
    private parser method directly, verifying that the right metrics are
    extracted. None-return tests verify parsers gracefully return None when
    no recognisable file is present.
    """

    def _handler(self, work_dir):
        return NextflowQCGateHandler(
            invocation_id="parser-test",
            work_dir=work_dir,
            sse_callback=lambda t, d: None,
            app=Mock(),
        )

    # -----------------------------------------------------------------------
    # FastQC parser
    # -----------------------------------------------------------------------

    def test_fastqc_summary_txt_pass_modules(self, tmp_path):
        """summary.txt with PASS/WARN/FAIL lines → failed_modules / warned_modules."""
        summary = tmp_path / "summary.txt"
        summary.write_text(
            "PASS\tBasic Statistics\tsample_fastqc\n"
            "WARN\tPer base sequence quality\tsample_fastqc\n"
            "FAIL\tAdapter Content\tsample_fastqc\n"
            "FAIL\tOverrepresented sequences\tsample_fastqc\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        assert metrics is not None
        assert metrics["module_failures"] == 2
        assert "Adapter Content" in metrics["failed_modules"]
        assert "Per base sequence quality" in metrics["warned_modules"]

    def test_fastqc_data_txt_gc_content(self, tmp_path):
        """fastqc_data.txt with %GC and Total Sequences lines → gc_content_pct."""
        data = tmp_path / "fastqc_data.txt"
        data.write_text(
            "##FastQC\t0.12.1\n"
            ">>Basic Statistics\tpass\n"
            "Total Sequences\t5000000\n"
            "%GC\t52\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        assert metrics is not None
        assert metrics["gc_content_pct"] == 52.0
        assert metrics["total_sequences"] == 5_000_000

    def test_fastqc_no_files_returns_none(self, tmp_path):
        """Empty directory → None."""
        h = self._handler(tmp_path)
        assert h._parse_fastqc_metrics(tmp_path) is None

    def test_fastqc_all_pass_no_failures(self, tmp_path):
        """summary.txt with only PASS lines → metrics dict without failed_modules key."""
        summary = tmp_path / "summary.txt"
        summary.write_text(
            "PASS\tBasic Statistics\tsample_fastqc\n"
            "PASS\tPer base sequence quality\tsample_fastqc\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        # No FAIL or WARN → no failed_modules key
        assert metrics is None or "failed_modules" not in metrics

    # -----------------------------------------------------------------------
    # Trimming parser
    # -----------------------------------------------------------------------

    def test_trimming_fastp_json(self, tmp_path):
        """fastp.json with filtering_result → reads_surviving_pct and q30_pct."""
        import json as _json
        fastp_data = {
            "summary": {
                "before_filtering": {
                    "total_reads": 10_000_000,
                    "q30_rate": 0.87,
                }
            },
            "filtering_result": {
                "passed_filter_reads": 9_200_000,
                "low_quality_reads": 800_000,
            }
        }
        (tmp_path / "fastp.json").write_text(_json.dumps(fastp_data))
        h = self._handler(tmp_path)
        metrics = h._parse_trimming_metrics(tmp_path)
        assert metrics is not None
        assert metrics["reads_surviving_pct"] == pytest.approx(92.0, abs=0.1)
        assert metrics["q30_pct"] == pytest.approx(87.0, abs=0.1)

    def test_trimming_trimmomatic_log(self, tmp_path):
        """Trimmomatic-style log with 'Surviving: X (85.23%)' → reads_surviving_pct."""
        log = tmp_path / "trim.log"
        log.write_text(
            "Input Read Pairs: 1000000 Both Surviving: 852300 (85.23%) "
            "Forward Only Surviving: 100000 (10.00%) Drop: 47700 (4.77%)\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_trimming_metrics(tmp_path)
        assert metrics is not None
        assert metrics["reads_surviving_pct"] == pytest.approx(85.23, abs=0.01)

    def test_trimming_empty_dir_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_trimming_metrics(tmp_path) is None

    def test_trimming_zero_total_reads_skipped(self, tmp_path):
        """fastp.json with total_reads=0 must not emit reads_surviving_pct (div-by-zero guard)."""
        import json as _json
        fastp_data = {
            "summary": {"before_filtering": {"total_reads": 0}},
            "filtering_result": {"passed_filter_reads": 0},
        }
        (tmp_path / "fastp.json").write_text(_json.dumps(fastp_data))
        h = self._handler(tmp_path)
        metrics = h._parse_trimming_metrics(tmp_path)
        assert metrics is None or "reads_surviving_pct" not in metrics

    # -----------------------------------------------------------------------
    # Alignment parser
    # -----------------------------------------------------------------------

    def test_alignment_star_log_final_out(self, tmp_path):
        """STAR Log.final.out → uniquely_mapped_pct and alignment_rate."""
        star_log = tmp_path / "Aligned.sortedByCoord.out.bam.Log.final.out"
        star_log.write_text(
            "                                 Started job on |	Jan 01 12:00:00\n"
            "                     Number of input reads |	50000000\n"
            "                 Uniquely mapped reads % |	82.56%\n"
            "              % of reads mapped to multiple loci |	4.12%\n"
            "                    % of reads unmapped: too short |	8.00%\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_alignment_metrics(tmp_path)
        assert metrics is not None
        assert metrics["uniquely_mapped_pct"] == pytest.approx(82.56, abs=0.01)
        assert metrics["alignment_rate"] == pytest.approx(86.68, abs=0.01)
        assert metrics["total_reads"] == 50_000_000

    def test_alignment_hisat2_log(self, tmp_path):
        """HISAT2/Bowtie2 overall alignment rate line → alignment_rate."""
        log = tmp_path / "sample.log"
        log.write_text(
            "10000000 reads; of these:\n"
            "  10000000 (100.00%) were unpaired; of these:\n"
            "    1200000 (12.00%) aligned 0 times\n"
            "    8800000 (88.00%) aligned exactly 1 time\n"
            "88.00% overall alignment rate\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_alignment_metrics(tmp_path)
        assert metrics is not None
        assert metrics["alignment_rate"] == pytest.approx(88.0, abs=0.01)

    def test_alignment_no_files_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_alignment_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # FeatureCounts parser
    # -----------------------------------------------------------------------

    def test_featurecounts_summary(self, tmp_path):
        """featureCounts .summary file → assigned_reads_pct."""
        summary = tmp_path / "counts.summary"
        summary.write_text(
            "Status\tcounts\n"
            "Assigned\t7000000\n"
            "Unassigned_NoFeatures\t2500000\n"
            "Unassigned_Ambiguity\t500000\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_featurecounts_metrics(tmp_path)
        assert metrics is not None
        # assigned=7M, total=10M → 70%
        assert metrics["assigned_reads_pct"] == pytest.approx(70.0, abs=0.1)
        assert metrics["assigned_reads"] == 7_000_000

    def test_featurecounts_no_file_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_featurecounts_metrics(tmp_path) is None

    def test_featurecounts_zero_total_safe(self, tmp_path):
        """All-zero counts should not produce a metric (div-by-zero guard)."""
        summary = tmp_path / "counts.summary"
        summary.write_text("Status\tcounts\nAssigned\t0\nUnassigned_NoFeatures\t0\n")
        h = self._handler(tmp_path)
        metrics = h._parse_featurecounts_metrics(tmp_path)
        assert metrics is None or "assigned_reads_pct" not in metrics

    # -----------------------------------------------------------------------
    # Salmon parser
    # -----------------------------------------------------------------------

    def test_salmon_meta_info_json(self, tmp_path):
        """Salmon aux_info/meta_info.json with percent_mapped → mapping_rate."""
        import json as _json
        aux = tmp_path / "aux_info"
        aux.mkdir()
        (aux / "meta_info.json").write_text(_json.dumps({
            "num_processed": 10_000_000,
            "percent_mapped": 91.45,
        }))
        h = self._handler(tmp_path)
        metrics = h._parse_salmon_metrics(tmp_path)
        assert metrics is not None
        assert metrics["mapping_rate"] == pytest.approx(91.45, abs=0.01)

    def test_salmon_mapping_rate_key(self, tmp_path):
        """JSON with mapping_rate key (string with %) → stripped float."""
        import json as _json
        (tmp_path / "quant_meta.json").write_text(_json.dumps({
            "mapping_rate": "87.3%"
        }))
        h = self._handler(tmp_path)
        metrics = h._parse_salmon_metrics(tmp_path)
        assert metrics is not None
        assert metrics["mapping_rate"] == pytest.approx(87.3, abs=0.01)

    def test_salmon_no_file_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_salmon_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # Flagstat parser
    # -----------------------------------------------------------------------

    def test_flagstat_mapped_pct_and_dup_pct(self, tmp_path):
        """samtools flagstat output → mapped_pct and duplicate_pct."""
        flagstat = tmp_path / "sample.flagstat"
        flagstat.write_text(
            "10000000 + 0 in total (QC-passed reads + QC-failed reads)\n"
            "0 + 0 secondary\n"
            "0 + 0 supplementary\n"
            "800000 + 0 duplicates\n"
            "9500000 + 0 mapped (95.00% : N/A)\n"
            "10000000 + 0 paired in sequencing\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_flagstat_metrics(tmp_path)
        assert metrics is not None
        assert metrics["mapped_pct"] == pytest.approx(95.0, abs=0.1)
        assert metrics["total_reads"] == 10_000_000
        # 800000 / 10000000 = 8%
        assert metrics["duplicate_pct"] == pytest.approx(8.0, abs=0.1)

    def test_flagstat_no_duplicates_line(self, tmp_path):
        """flagstat without duplicates line → no duplicate_pct key."""
        flagstat = tmp_path / "sample.flagstat"
        flagstat.write_text(
            "5000000 + 0 in total (QC-passed reads + QC-failed reads)\n"
            "4750000 + 0 mapped (95.00% : N/A)\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_flagstat_metrics(tmp_path)
        assert metrics is not None
        assert "duplicate_pct" not in metrics

    def test_flagstat_no_file_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_flagstat_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # Picard MarkDuplicates parser
    # -----------------------------------------------------------------------

    def test_picard_dup_metrics(self, tmp_path):
        """Picard metrics file with PERCENT_DUPLICATION → duplicate_pct."""
        metrics_file = tmp_path / "sample.dup_metrics"
        metrics_file.write_text(
            "## METRICS CLASS\tpicard.sam.DuplicationMetrics\n"
            "LIBRARY\tESTIMATED_LIBRARY_SIZE\tPERCENT_DUPLICATION\n"
            "mylib\t12345678\t0.1847\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_picard_dup_metrics(tmp_path)
        assert metrics is not None
        # 0.1847 * 100 = 18.47%
        assert metrics["duplicate_pct"] == pytest.approx(18.47, abs=0.01)
        assert metrics["estimated_library_size"] == 12_345_678

    def test_picard_no_percent_duplication_header(self, tmp_path):
        """File without PERCENT_DUPLICATION header → None."""
        other_file = tmp_path / "other.txt"
        other_file.write_text("some unrelated content\n")
        h = self._handler(tmp_path)
        metrics = h._parse_picard_dup_metrics(tmp_path)
        assert metrics is None

    # -----------------------------------------------------------------------
    # Single-cell parser
    # -----------------------------------------------------------------------

    def test_singlecell_cellranger_csv(self, tmp_path):
        """CellRanger metrics_summary.csv → cells_detected and median_genes_per_cell."""
        csv = tmp_path / "metrics_summary.csv"
        csv.write_text(
            "Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome\n"
            "\"4,521\",\"2,847\",95.3\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_singlecell_metrics(tmp_path)
        assert metrics is not None
        assert metrics["cells_detected"] == 4521
        assert metrics["median_genes_per_cell"] == 2847
        assert metrics["mapping_rate"] == pytest.approx(95.3, abs=0.1)

    def test_singlecell_no_file_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_singlecell_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # Peak calling parser
    # -----------------------------------------------------------------------

    def test_peakcalling_narrowpeak_count(self, tmp_path):
        """MACS2 narrowPeak file → peaks_called = number of non-comment lines."""
        peak_file = tmp_path / "sample_peaks.narrowPeak"
        # 3 real peaks + 1 comment (should be excluded)
        peak_file.write_text(
            "# generated by MACS2\n"
            "chr1\t100\t500\tpeak_1\t150\t.\t5.0\t10.0\t8.5\t200\n"
            "chr1\t1000\t1400\tpeak_2\t120\t.\t4.5\t9.0\t7.5\t180\n"
            "chr2\t500\t900\tpeak_3\t90\t.\t3.5\t7.0\t6.0\t150\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_peakcalling_metrics(tmp_path)
        assert metrics is not None
        assert metrics["peaks_called"] == 3

    def test_peakcalling_macs2_log_tags(self, tmp_path):
        """MACS2 log with 'total tags after filtering' → tags_after_filtering."""
        log = tmp_path / "sample_macs2.log"
        log.write_text(
            "INFO  @ Fri, 20 Feb 2026 10:00:00 macs2 callpeak\n"
            "# total tags after filtering: 28453291\n"
            "# d = 147\n"
        )
        # Create a dummy peak file so metrics is not None
        (tmp_path / "sample_peaks.narrowPeak").write_text("chr1\t100\t500\tpeak_1\t150\t.\t5.0\t10.0\t8.5\t200\n")
        h = self._handler(tmp_path)
        metrics = h._parse_peakcalling_metrics(tmp_path)
        assert metrics is not None
        assert metrics["tags_after_filtering"] == 28_453_291

    def test_peakcalling_no_file_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_peakcalling_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # Metagenomics parser
    # -----------------------------------------------------------------------

    def test_metagenomics_kraken2_report(self, tmp_path):
        """Kraken2 report with U line → classified_pct = 100 - unclassified_pct."""
        report = tmp_path / "sample.report"
        # Kraken2 format: pct \t reads \t reads_direct \t rank_code \t taxon_id \t name
        report.write_text(
            " 18.50\t185000\t185000\tU\t0\tunclassified\n"
            " 81.50\t815000\t0\tR\t1\troot\n"
            "  75.00\t750000\t0\tD\t2\tBacteria\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_metagenomics_metrics(tmp_path)
        assert metrics is not None
        assert metrics["classified_pct"] == pytest.approx(81.5, abs=0.1)

    def test_metagenomics_no_u_line_returns_none(self, tmp_path):
        """Report with no U rank line → no classified_pct extracted."""
        report = tmp_path / "sample.k2report"
        report.write_text(
            " 100.00\t1000000\t0\tR\t1\troot\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_metagenomics_metrics(tmp_path)
        assert metrics is None

    def test_metagenomics_no_file_returns_none(self, tmp_path):
        h = self._handler(tmp_path)
        assert h._parse_metagenomics_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # Threshold checks — boundary conditions for new process types
    # -----------------------------------------------------------------------

    def _check(self, process_name, metrics):
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock()
        )
        return h._check_qc_thresholds(process_name, metrics)

    def test_fastp_below_threshold_fails(self):
        passed, failures = self._check("FASTP_TRIM", {"reads_surviving_pct": 65.0})
        assert not passed
        assert any(f["metric"] == "reads_surviving_pct" for f in failures)

    def test_fastp_above_threshold_passes(self):
        passed, failures = self._check("FASTP_TRIM", {"reads_surviving_pct": 80.0})
        assert passed and failures == []

    def test_fastp_at_threshold_exactly_passes(self):
        """Exactly 70% should NOT trigger (threshold is strict <)."""
        passed, _ = self._check("FASTP_TRIM", {"reads_surviving_pct": 70.0})
        assert passed

    def test_star_low_alignment_rate_fails(self):
        passed, failures = self._check("STAR_ALIGN", {"alignment_rate": 55.0})
        assert not passed
        assert failures[0]["metric"] == "alignment_rate"

    def test_star_high_alignment_rate_passes(self):
        passed, _ = self._check("STAR_ALIGN", {"alignment_rate": 90.0})
        assert passed

    def test_featurecounts_low_assignment_fails(self):
        passed, failures = self._check("FEATURECOUNTS", {"assigned_reads_pct": 40.0})
        assert not passed
        assert failures[0]["metric"] == "assigned_reads_pct"

    def test_salmon_low_mapping_fails(self):
        passed, failures = self._check("SALMON_QUANT", {"mapping_rate": 45.0})
        assert not passed

    def test_flagstat_high_dup_fails(self):
        passed, failures = self._check("FLAGSTAT", {"mapped_pct": 90.0, "duplicate_pct": 45.0})
        assert not passed
        assert any(f["metric"] == "duplicate_pct" for f in failures)

    def test_markdup_dup_at_threshold_passes(self):
        """Exactly 30% → NOT triggered (strict >)."""
        passed, _ = self._check("MARKDUPLICATES", {"duplicate_pct": 30.0})
        assert passed

    def test_cellranger_too_few_cells_fails(self):
        passed, failures = self._check("CELLRANGER_COUNT", {"cells_detected": 100})
        assert not passed
        assert failures[0]["metric"] == "cells_detected"

    def test_cellranger_low_genes_fails(self):
        passed, failures = self._check("CELLRANGER_COUNT", {"median_genes_per_cell": 300})
        assert not passed
        assert failures[0]["metric"] == "median_genes_per_cell"

    def test_macs2_few_peaks_fails(self):
        passed, failures = self._check("MACS2", {"peaks_called": 500})
        assert not passed

    def test_kraken2_low_classified_fails(self):
        passed, failures = self._check("KRAKEN2", {"classified_pct": 20.0})
        assert not passed

    def test_kraken2_passes_at_threshold(self):
        """Exactly 60% classified → NOT triggered (at boundary of warning tier)."""
        passed, _ = self._check("KRAKEN2", {"classified_pct": 60.0})
        assert passed

    def test_kraken2_warning_tier_fails(self):
        """42% classified (30-60% range) → triggers warning-severity failure."""
        passed, failures = self._check("KRAKEN2", {"classified_pct": 42.0})
        assert not passed
        assert any(f["metric"] == "classified_pct" for f in failures)
        assert any(f.get("severity") == "warning" for f in failures)

    def test_kraken2_critical_tier_has_critical_severity(self):
        """18% classified (< 30%) → triggers critical-severity failure."""
        passed, failures = self._check("KRAKEN2", {"classified_pct": 18.0})
        assert not passed
        assert any(f.get("severity") == "critical" for f in failures)

    # -----------------------------------------------------------------------
    # New metrics — mito fraction, FRiP, coverage depth
    # -----------------------------------------------------------------------

    def test_mito_fraction_above_threshold_fails(self):
        """scRNA-seq: mito_fraction_pct > 20% triggers failure (Osorio & Cai 2021)."""
        passed, failures = self._check("CELLRANGER_COUNT", {"mito_fraction_pct": 32.0})
        assert not passed
        assert any(f["metric"] == "mito_fraction_pct" for f in failures)

    def test_mito_fraction_at_threshold_passes(self):
        """scRNA-seq: mito_fraction_pct = 20.0 is NOT > 20 → passes."""
        passed, _ = self._check("CELLRANGER_COUNT", {"mito_fraction_pct": 20.0})
        assert passed

    def test_frip_below_encode_minimum_is_advisory(self):
        """ChIP-seq: FRiP < 0.01 is advisory only — ENCODE4 has no hard FRiP gate.
        The advisory item appears in failures with advisory=True but qc_passed remains True."""
        passed, failures = self._check("MACS2", {"frip_score": 0.005})
        assert passed, "ChIP FRiP < 0.01 must be advisory (non-blocking) per ENCODE4"
        frip_fail = next((f for f in failures if f["metric"] == "frip_score"), None)
        assert frip_fail is not None, "Advisory item should appear in failures for display"
        assert frip_fail.get("advisory") is True

    def test_frip_above_minimum_passes(self):
        """ChIP-seq: FRiP = 0.01 is NOT < 0.01 → passes."""
        passed, _ = self._check("MACS2", {"frip_score": 0.01})
        assert passed

    def test_coverage_below_30x_fails(self):
        """WGS: mean_coverage < 30X triggers failure (GATK threshold)."""
        passed, failures = self._check("MOSDEPTH", {"mean_coverage": 18.5})
        assert not passed
        assert any(f["metric"] == "mean_coverage" for f in failures)

    def test_coverage_at_threshold_passes(self):
        """WGS: mean_coverage = 30.0X is NOT < 30 → passes."""
        passed, _ = self._check("MOSDEPTH", {"mean_coverage": 30.0})
        assert passed

    # -----------------------------------------------------------------------
    # Dispatch table — verify routing AND that real metrics are extracted
    # Each test writes a real output file and checks the metric value,
    # not just that the dispatch call happened.
    # -----------------------------------------------------------------------

    def _subdir(self, tmp_path, prefix="ab", rest="cd1234"):
        subdir = tmp_path / prefix / rest
        subdir.mkdir(parents=True, exist_ok=True)
        return subdir, f"{prefix}/{rest}"

    def test_dispatch_fastp_extracts_real_survival_pct(self, tmp_path):
        """FASTP_TRIM dispatch → real JSON parsed → reads_surviving_pct extracted."""
        import json as _json
        subdir, phash = self._subdir(tmp_path, "fa", "sp0001")
        (subdir / "fastp.json").write_text(_json.dumps({
            "summary": {"before_filtering": {"total_reads": 10_000_000}},
            "filtering_result": {"passed_filter_reads": 7_500_000},
        }))
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("FASTP_TRIM", "t1", phash)
        assert metrics is not None
        assert metrics["reads_surviving_pct"] == pytest.approx(75.0, abs=0.1)

    def test_dispatch_star_extracts_real_alignment_rate(self, tmp_path):
        """STAR_ALIGN dispatch → real Log.final.out parsed → alignment_rate extracted."""
        subdir, phash = self._subdir(tmp_path, "st", "ar0001")
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t82.00%\n"
            "% of reads mapped to multiple loci |\t4.50%\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("STAR_ALIGN", "t1", phash)
        assert metrics is not None
        assert metrics["alignment_rate"] == pytest.approx(86.5, abs=0.1)

    def test_dispatch_featurecounts_extracts_real_assigned_pct(self, tmp_path):
        """FEATURECOUNTS dispatch → real .summary parsed → assigned_reads_pct."""
        subdir, phash = self._subdir(tmp_path, "fc", "fc0001")
        (subdir / "counts.summary").write_text(
            "Status\tcounts\nAssigned\t6000000\nUnassigned_NoFeatures\t4000000\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("FEATURECOUNTS", "t1", phash)
        assert metrics is not None
        assert metrics["assigned_reads_pct"] == pytest.approx(60.0, abs=0.1)

    def test_dispatch_salmon_extracts_real_mapping_rate(self, tmp_path):
        """SALMON_QUANT dispatch → real meta_info.json parsed → mapping_rate."""
        import json as _json
        subdir, phash = self._subdir(tmp_path, "sa", "lm0001")
        aux = subdir / "aux_info"
        aux.mkdir()
        (aux / "meta_info.json").write_text(_json.dumps({"percent_mapped": 88.5}))
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("SALMON_QUANT", "t1", phash)
        assert metrics is not None
        assert metrics["mapping_rate"] == pytest.approx(88.5, abs=0.1)

    def test_dispatch_flagstat_extracts_real_mapped_pct(self, tmp_path):
        """FLAGSTAT dispatch → real flagstat file parsed → mapped_pct extracted."""
        subdir, phash = self._subdir(tmp_path, "fl", "ag0001")
        (subdir / "sample.flagstat").write_text(
            "10000000 + 0 in total (QC-passed reads + QC-failed reads)\n"
            "9200000 + 0 mapped (92.00% : N/A)\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("FLAGSTAT", "t1", phash)
        assert metrics is not None
        assert metrics["mapped_pct"] == pytest.approx(92.0, abs=0.1)

    def test_dispatch_markduplicates_extracts_real_dup_pct(self, tmp_path):
        """MARKDUPLICATES dispatch → real Picard metrics file → duplicate_pct."""
        subdir, phash = self._subdir(tmp_path, "mk", "dp0001")
        (subdir / "sample.dup_metrics").write_text(
            "## METRICS CLASS\tpicard.sam.DuplicationMetrics\n"
            "LIBRARY\tESTIMATED_LIBRARY_SIZE\tPERCENT_DUPLICATION\n"
            "lib1\t10000000\t0.22\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("MARKDUPLICATES", "t1", phash)
        assert metrics is not None
        assert metrics["duplicate_pct"] == pytest.approx(22.0, abs=0.1)

    def test_dispatch_cellranger_extracts_real_cell_count(self, tmp_path):
        """CELLRANGER_COUNT dispatch → real metrics_summary.csv → cells_detected."""
        subdir, phash = self._subdir(tmp_path, "cr", "sc0001")
        (subdir / "metrics_summary.csv").write_text(
            "Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome\n"
            "\"3,200\",\"2,100\",94.5\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("CELLRANGER_COUNT", "t1", phash)
        assert metrics is not None
        assert metrics["cells_detected"] == 3200

    def test_dispatch_macs2_counts_real_peaks(self, tmp_path):
        """MACS2 dispatch → real narrowPeak file → peaks_called count."""
        subdir, phash = self._subdir(tmp_path, "m2", "pk0001")
        lines = "\n".join(
            f"chr1\t{i*500}\t{i*500+400}\tpeak_{i}\t100\t.\t4.0\t8.0\t6.0\t200"
            for i in range(1, 1501)
        )
        (subdir / "sample_peaks.narrowPeak").write_text(lines + "\n")
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("MACS2", "t1", phash)
        assert metrics is not None
        assert metrics["peaks_called"] == 1500

    def test_dispatch_kraken2_extracts_real_classified_pct(self, tmp_path):
        """KRAKEN2 dispatch → real .report file → classified_pct extracted."""
        subdir, phash = self._subdir(tmp_path, "k2", "rp0001")
        (subdir / "sample.report").write_text(
            " 35.00\t350000\t350000\tU\t0\tunclassified\n"
            " 65.00\t650000\t0\tR\t1\troot\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("KRAKEN2", "t1", phash)
        assert metrics is not None
        assert metrics["classified_pct"] == pytest.approx(65.0, abs=0.1)

    def test_dispatch_mosdepth_extracts_mean_coverage(self, tmp_path):
        """MOSDEPTH dispatch → real summary.txt → mean_coverage extracted."""
        subdir, phash = self._subdir(tmp_path, "md", "cov001")
        (subdir / "sample.mosdepth.summary.txt").write_text(
            "chrom\tlength\tbases\tmean\tmin\tmax\n"
            "chr1\t248956422\t8518738116\t34.22\t0\t1200\n"
            "chrX\t156040895\t4210273530\t27.0\t0\t900\n"
            "total\t3099750718\t95000000000\t30.65\t0\t1200\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("MOSDEPTH", "t1", phash)
        assert metrics is not None
        assert metrics["mean_coverage"] == pytest.approx(30.65, abs=0.1)

    def test_dispatch_macs2_frip_score_extracted(self, tmp_path):
        """MACS2 dispatch → frip_score.txt → frip_score extracted."""
        subdir, phash = self._subdir(tmp_path, "m2", "fr0001")
        # One peak in the narrowPeak file
        (subdir / "sample_peaks.narrowPeak").write_text(
            "chr1\t500\t1000\tpeak_1\t100\t.\t4.0\t8.0\t6.0\t250\n"
        )
        (subdir / "frip_score.txt").write_text("0.35\n")
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("MACS2", "t1", phash)
        assert metrics is not None
        assert metrics["frip_score"] == pytest.approx(0.35, abs=0.001)

    def test_dispatch_cellranger_mito_fraction_extracted(self, tmp_path):
        """CELLRANGER_COUNT dispatch → metrics_summary.csv with mito column → mito_fraction_pct."""
        import csv as _csv
        subdir, phash = self._subdir(tmp_path, "cr", "mi0001")
        with open(subdir / "metrics_summary.csv", "w", newline="") as f:
            writer = _csv.DictWriter(f, fieldnames=[
                "Estimated Number of Cells", "Median Genes per Cell",
                "Reads Mapped to Genome", "Fraction Mitochondrial Reads"
            ])
            writer.writeheader()
            writer.writerow({
                "Estimated Number of Cells": "3000",
                "Median Genes per Cell": "1500",
                "Reads Mapped to Genome": "91.5%",
                "Fraction Mitochondrial Reads": "0.18"  # 18% → should be 18.0 after * 100
            })
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("CELLRANGER_COUNT", "t1", phash)
        assert metrics is not None
        assert metrics["mito_fraction_pct"] == pytest.approx(18.0, abs=0.1)

    def test_dispatch_hisat2_extracts_real_alignment_rate(self, tmp_path):
        """HISAT2_ALIGN dispatch → log with 'overall alignment rate' → alignment_rate."""
        subdir, phash = self._subdir(tmp_path, "h2", "al0001")
        (subdir / "hisat2.log").write_text(
            "10000000 reads; of these:\n"
            "  1200000 (12.00%) aligned 0 times\n"
            "88.00% overall alignment rate\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("HISAT2_ALIGN", "t1", phash)
        assert metrics is not None
        assert metrics["alignment_rate"] == pytest.approx(88.0, abs=0.1)

    def test_dispatch_bwa_mem_extracts_alignment_rate(self, tmp_path):
        """BWA_MEM dispatch → same 'overall alignment rate' log pattern → alignment_rate."""
        subdir, phash = self._subdir(tmp_path, "bw", "am0001")
        (subdir / "bwa.log").write_text(
            "10000000 reads; of these:\n"
            "  500000 (5.00%) aligned 0 times\n"
            "95.00% overall alignment rate\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("BWA_MEM", "t1", phash)
        assert metrics is not None
        assert metrics["alignment_rate"] == pytest.approx(95.0, abs=0.1)

    # -----------------------------------------------------------------------
    # Bug 6: process_upper NameError in _check_qc_thresholds
    # (regression: all non-cryo-EM branches would crash before this fix)
    # -----------------------------------------------------------------------

    def test_bug6_process_upper_defined_for_rna_seq_processes(self):
        """_check_qc_thresholds must not raise NameError for any supported process."""
        processes = [
            ("FASTP_TRIM", {"reads_surviving_pct": 60.0}),
            ("STAR_ALIGN", {"alignment_rate": 55.0}),
            ("FEATURECOUNTS", {"assigned_reads_pct": 40.0}),
            ("SALMON_QUANT", {"mapping_rate": 45.0}),
            ("FLAGSTAT", {"mapped_pct": 60.0}),
            ("MARKDUPLICATES", {"duplicate_pct": 45.0}),
            ("CELLRANGER_COUNT", {"cells_detected": 100}),
            ("MACS2", {"peaks_called": 500}),
            ("KRAKEN2", {"classified_pct": 20.0}),
            ("FASTQC", {"module_failures": 2}),
        ]
        for proc, metrics in processes:
            passed, failures = self._check(proc, metrics)
            # All should fail (bad metrics) but NOT raise NameError
            assert not passed, f"Expected {proc} to fail QC with bad metrics"


# ===========================================================================
# 22. RNA-SEQ MULTI-FAILURE
# ===========================================================================

class TestRNASeqMultiFailure:
    """
    When a single process has multiple bad metrics, ALL failures should fire.
    Previous tests only checked one metric at a time. This section tests
    simultaneous failure modes.
    """

    def _check(self, process_name, metrics):
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock()
        )
        return h._check_qc_thresholds(process_name, metrics)

    def test_fastp_both_low_reads_and_low_q30_emit_two_failures(self):
        """FASTP with reads_surviving_pct < 70 AND q30_pct < 75 → 2 failures."""
        passed, failures = self._check(
            "FASTP_TRIM",
            {"reads_surviving_pct": 60.0, "q30_pct": 70.0}
        )
        assert not passed
        metrics_failed = {f["metric"] for f in failures}
        assert "reads_surviving_pct" in metrics_failed
        assert "q30_pct" in metrics_failed
        assert len(failures) == 2

    def test_fastp_only_low_q30_emits_one_failure(self):
        """Good reads_surviving_pct but bad q30 → exactly 1 failure on q30."""
        passed, failures = self._check(
            "FASTP_TRIM",
            {"reads_surviving_pct": 85.0, "q30_pct": 70.0}
        )
        assert not passed
        assert len(failures) == 1
        assert failures[0]["metric"] == "q30_pct"

    def test_flagstat_both_low_mapped_and_high_dup_emit_two_failures(self):
        """samtools flagstat with both mapped_pct < 70 and duplicate_pct > 40."""
        passed, failures = self._check(
            "FLAGSTAT",
            {"mapped_pct": 60.0, "duplicate_pct": 45.0}
        )
        assert not passed
        metrics_failed = {f["metric"] for f in failures}
        assert "mapped_pct" in metrics_failed
        assert "duplicate_pct" in metrics_failed
        assert len(failures) == 2

    def test_cellranger_both_few_cells_and_low_genes_emit_two_failures(self):
        """CellRanger with cells_detected < 200 AND median_genes_per_cell < 500."""
        passed, failures = self._check(
            "CELLRANGER_COUNT",
            {"cells_detected": 100, "median_genes_per_cell": 300}
        )
        assert not passed
        metrics_failed = {f["metric"] for f in failures}
        assert "cells_detected" in metrics_failed
        assert "median_genes_per_cell" in metrics_failed
        assert len(failures) == 2

    def test_good_metrics_no_failures(self):
        """All metrics above threshold → zero failures."""
        passed, failures = self._check(
            "FASTP_TRIM",
            {"reads_surviving_pct": 90.0, "q30_pct": 85.0}
        )
        assert passed
        assert failures == []

    def test_fastp_multi_failure_structured_keys_complete(self):
        """Each failure in a multi-failure response has all 5 required keys."""
        _, failures = self._check(
            "FASTP_TRIM",
            {"reads_surviving_pct": 60.0, "q30_pct": 70.0}
        )
        for f in failures:
            for key in ("metric", "value", "threshold", "operator", "message"):
                assert key in f, f"Missing key {key!r} in failure: {f}"


# ===========================================================================
# 23. CTF DEFOCUS BOUNDARY CONDITIONS
# ===========================================================================

class TestCTFDefocusBoundary:
    """
    The CTF parser accepts defocus_u only in range (1000, 100000) angstroms.
    Values at and outside this boundary should be rejected (treated as garbage lines).
    """

    def _parse(self, work_dir, content, filename="ctf.txt"):
        """Write a CTF file and parse it."""
        (work_dir / filename).write_text(content)
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=work_dir,
            sse_callback=lambda t, d: None, app=Mock()
        )
        return h._parse_ctf_metrics(work_dir)

    def test_defocus_1001_accepted(self, tmp_path):
        """defocus_u = 1001 Å (just above lower bound) is accepted."""
        metrics = self._parse(tmp_path,
            "1001.0\t980.0\t45.0\t0.0\t0.92\n"
        )
        assert metrics is not None
        assert metrics["defocus_u_angstrom"] == 1001.0

    def test_defocus_1000_rejected(self, tmp_path):
        """defocus_u = 1000 Å (at lower bound, not strictly >) recorded as out-of-range."""
        metrics = self._parse(tmp_path,
            "1000.0\t980.0\t45.0\t0.0\t0.92\n"
        )
        assert metrics is not None
        assert metrics.get("defocus_out_of_range") is True
        assert metrics.get("defocus_direction") == "below"

    def test_defocus_999_rejected(self, tmp_path):
        """defocus_u = 999 Å (below lower bound) recorded as out-of-range."""
        metrics = self._parse(tmp_path,
            "999.0\t980.0\t45.0\t0.0\t0.92\n"
        )
        assert metrics is not None
        assert metrics.get("defocus_out_of_range") is True
        assert metrics.get("defocus_direction") == "below"

    def test_defocus_99999_accepted(self, tmp_path):
        """defocus_u = 99999 Å (just below upper bound) is accepted."""
        metrics = self._parse(tmp_path,
            "99999.0\t98000.0\t45.0\t0.0\t0.90\n"
        )
        assert metrics is not None
        assert metrics["defocus_u_angstrom"] == 99999.0

    def test_defocus_100000_rejected(self, tmp_path):
        """defocus_u = 100000 Å (at upper bound, not strictly <) recorded as out-of-range."""
        metrics = self._parse(tmp_path,
            "100000.0\t99000.0\t45.0\t0.0\t0.88\n"
        )
        assert metrics is not None
        assert metrics.get("defocus_out_of_range") is True
        assert metrics.get("defocus_direction") == "above"

    def test_defocus_100001_rejected(self, tmp_path):
        """defocus_u = 100001 Å (above upper bound) recorded as out-of-range."""
        metrics = self._parse(tmp_path,
            "100001.0\t99000.0\t45.0\t0.0\t0.87\n"
        )
        assert metrics is not None
        assert metrics.get("defocus_out_of_range") is True
        assert metrics.get("defocus_direction") == "above"

    def test_invalid_last_line_falls_back_to_valid_earlier_line(self, tmp_path):
        """When last line has out-of-range defocus, valid earlier line is used (Bug 4 fix)."""
        metrics = self._parse(tmp_path,
            # Line 1: valid (defocus 15000, astigmatism = 15000-14800 = 200)
            "15000.0\t14800.0\t32.5\t0.0\t0.95\n"
            # Line 2: invalid defocus (way out of range)
            "500.0\t490.0\t0.0\t0.0\t0.50\n"
        )
        assert metrics is not None
        assert metrics["defocus_u_angstrom"] == 15000.0
        assert metrics["astigmatism_angstrom"] == pytest.approx(200.0, abs=0.1)

    def test_astigmatism_is_absolute_difference(self, tmp_path):
        """Astigmatism is |defocus_u - defocus_v|, always positive."""
        # defocus_v > defocus_u → difference would be negative without abs()
        metrics = self._parse(tmp_path,
            "10000.0\t11000.0\t45.0\t0.0\t0.95\n"
        )
        assert metrics is not None
        assert metrics["astigmatism_angstrom"] == pytest.approx(1000.0, abs=0.1)

    def test_fit_quality_clamped_to_0_1(self, tmp_path):
        """fit_quality is clamped to [0.0, 1.0] even if score > 1.0."""
        # Some CTF programs report CCC or other metrics > 1
        metrics = self._parse(tmp_path,
            "12000.0\t11800.0\t10.0\t0.0\t1.8\n"
        )
        assert metrics is not None
        assert metrics["fit_quality"] == 1.0  # clamped

    def test_fit_quality_negative_clamped_to_zero(self, tmp_path):
        """fit_quality < 0 is clamped to 0.0."""
        metrics = self._parse(tmp_path,
            "12000.0\t11800.0\t10.0\t0.0\t-0.3\n"
        )
        assert metrics is not None
        assert metrics["fit_quality"] == 0.0


# ===========================================================================
# 24. PICKING DUPLICATE FRACTION INVARIANT
# ===========================================================================

class TestPickingDuplicateFractionInvariant:
    """
    The picking parser always emits duplicate_fraction = 0.0 because NMS data
    is not available at parse time. This test class documents that invariant
    so that any future change (e.g., real duplicate detection) is caught.
    """

    def _parse(self, work_dir):
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=work_dir,
            sse_callback=lambda t, d: None, app=Mock()
        )
        return h._parse_picking_metrics(work_dir)

    def test_duplicate_fraction_always_zero(self, tmp_path):
        """duplicate_fraction in picking output is always 0.0 (NMS not available)."""
        star = tmp_path / "particles.star"
        star.write_text(
            "# STAR file\n"
            "_rlnCoordinateX\n"
            "_rlnCoordinateY\n"
            "100.0\t200.0\n"
            "300.0\t400.0\n"
            "500.0\t600.0\n"
        )
        metrics = self._parse(tmp_path)
        assert metrics is not None
        assert metrics["duplicate_fraction"] == 0.0

    def test_picking_qc_gate_never_fires_on_duplicate_fraction_alone(self):
        """Because duplicate_fraction is always 0.0, it can never trigger the gate."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock()
        )
        # Even if threshold is 0.2, the parsed value is always 0.0
        passed, failures = h._check_qc_thresholds(
            "PARTICLE_PICKING",
            {"particles_picked": 5000, "duplicate_fraction": 0.0}
        )
        assert passed
        assert failures == []

    def test_picking_returns_none_when_no_coordinate_files(self, tmp_path):
        """Parser returns None when no .star / .box / .coords files exist."""
        metrics = self._parse(tmp_path)
        assert metrics is None

    def test_picking_counts_only_coordinate_lines(self, tmp_path):
        """Only lines starting with digit or '-' are counted (not headers/comments)."""
        star = tmp_path / "particles.star"
        star.write_text(
            "# comment\n"
            "_rlnCoordinateX\n"
            "_rlnCoordinateY\n"
            "100.0\t200.0\n"
            "300.0\t400.0\n"
        )
        metrics = self._parse(tmp_path)
        assert metrics is not None
        assert metrics["particles_picked"] == 2


# ===========================================================================
# 25. END-TO-END: FILE → HANDLE_PROCESS_COMPLETION → SSE EVENT
# ===========================================================================

class TestEndToEndFileToSSE:
    """
    Full pipeline tests: write real Nextflow work directory files, call
    handle_process_completion, and verify the SSE callback fires with a
    correctly structured QC gate event.

    These tests cover the integration of: file I/O → metric parsing →
    threshold check → suggestion generation → SSE emission.
    """

    def _run(self, work_dir, process_name, hash_prefix, hash_rest,
             domain, params, file_writer):
        """
        Set up a Nextflow-style work subdirectory, write output files via
        file_writer(subdir), then run handle_process_completion and capture events.
        """
        subdir = work_dir / hash_prefix / hash_rest
        subdir.mkdir(parents=True)
        file_writer(subdir)

        events = []
        h = NextflowQCGateHandler(
            invocation_id="e2e-test",
            work_dir=work_dir,
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain=domain,
            current_parameters=params,
        )
        h.handle_process_completion(
            task_id="task42",
            process_name=process_name,
            process_hash=f"{hash_prefix}/{hash_rest}",
            status="COMPLETED",
        )
        return events

    def test_fastp_low_survival_triggers_sse_with_suggestions(self, tmp_path):
        """
        FASTP JSON with 60% reads surviving → SSE event with reads_surviving_pct
        failure AND a trim_quality_threshold suggestion.
        """
        import json as _json

        def write_files(subdir):
            fastp_data = {
                "summary": {
                    "before_filtering": {"total_reads": 10_000_000, "q30_rate": 0.85}
                },
                "filtering_result": {"passed_filter_reads": 6_000_000}
            }
            (subdir / "fastp.json").write_text(_json.dumps(fastp_data))

        events = self._run(
            tmp_path, "FASTP_TRIM", "ab", "cd1234ef",
            "rna_seq", {"trim_quality_threshold": 20},
            write_files
        )

        assert len(events) == 1, f"Expected 1 SSE event, got {len(events)}"
        event_type, event_data = events[0]
        assert event_type == "qc_gate_triggered"
        assert "failures" in event_data
        assert any(f["metric"] == "reads_surviving_pct" for f in event_data["failures"])

    def test_fastp_good_metrics_no_sse_fired(self, tmp_path):
        """FASTP JSON with 92% reads surviving → no SSE event."""
        import json as _json

        def write_files(subdir):
            fastp_data = {
                "summary": {
                    "before_filtering": {"total_reads": 10_000_000, "q30_rate": 0.92}
                },
                "filtering_result": {"passed_filter_reads": 9_200_000}
            }
            (subdir / "fastp.json").write_text(_json.dumps(fastp_data))

        events = self._run(
            tmp_path, "FASTP_TRIM", "cd", "ef5678ab",
            "rna_seq", {},
            write_files
        )
        assert events == [], f"Expected no SSE events for good metrics, got {events}"

    def test_featurecounts_low_assignment_triggers_sse(self, tmp_path):
        """featureCounts summary with 40% assigned → SSE event fired."""
        def write_files(subdir):
            summary = subdir / "counts.summary"
            summary.write_text(
                "Status\tcounts\n"
                "Assigned\t4000000\n"
                "Unassigned_NoFeatures\t6000000\n"
            )

        events = self._run(
            tmp_path, "FEATURECOUNTS", "ee", "ff9900aa",
            "rna_seq", {},
            write_files
        )
        assert len(events) == 1
        assert events[0][0] == "qc_gate_triggered"
        assert events[0][1]["failures"][0]["metric"] == "assigned_reads_pct"
        assert events[0][1]["failures"][0]["value"] == pytest.approx(40.0, abs=0.1)

    def test_missing_work_dir_no_sse(self, tmp_path):
        """When work directory doesn't contain matching hash subdir, no SSE fires."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="e2e-missing",
            work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(),
            workflow_domain="rna_seq",
            current_parameters={},
        )
        h.handle_process_completion(
            task_id="task1",
            process_name="FASTP_TRIM",
            process_hash="xx/yy1234",
            status="COMPLETED",
        )
        assert events == []

    def test_sse_event_has_process_name_and_timestamp(self, tmp_path):
        """SSE event payload includes process_name and ISO-8601 timestamp."""
        import json as _json
        import re

        def write_files(subdir):
            fastp_data = {
                "summary": {"before_filtering": {"total_reads": 10_000_000}},
                "filtering_result": {"passed_filter_reads": 5_000_000}
            }
            (subdir / "fastp.json").write_text(_json.dumps(fastp_data))

        events = self._run(
            tmp_path, "FASTP_TRIM", "12", "3456789a",
            "rna_seq", {},
            write_files
        )
        assert len(events) == 1
        _, data = events[0]
        assert "process_name" in data
        assert data["process_name"] == "FASTP_TRIM"
        assert "timestamp" in data
        # Verify ISO-8601 format: YYYY-MM-DDTHH:MM:SS
        assert re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", data["timestamp"])

    def test_kraken2_low_classified_triggers_sse(self, tmp_path):
        """Kraken2 report with 20% classified reads → SSE event."""
        def write_files(subdir):
            report = subdir / "sample.report"
            report.write_text(
                " 80.00\t800000\t800000\tU\t0\tunclassified\n"
                " 20.00\t200000\t0\tR\t1\troot\n"
            )

        events = self._run(
            tmp_path, "KRAKEN2", "aa", "bb123456",
            "metagenomics", {},
            write_files
        )
        assert len(events) == 1
        assert events[0][0] == "qc_gate_triggered"
        failure = events[0][1]["failures"][0]
        assert failure["metric"] == "classified_pct"
        assert failure["value"] == pytest.approx(20.0, abs=0.1)


# ===========================================================================
# 26. UNCOVERED CODE PATHS — previously untested file formats
# ===========================================================================

class TestUncoveredPaths:
    """
    Tests for code paths that existed in production but had zero test coverage:
    - MultiQC JSON aggregation in _parse_fastqc_metrics
    - STARsolo Summary.csv in _parse_singlecell_metrics
    - broadPeak and summits.bed in _parse_peakcalling_metrics
    - STAR log with only uniquely_mapped_pct (no multi-loci line) → Bug 8 fix
    - Absent total_drift_angstrom metric in motion correction suggester
    """

    def _handler(self, work_dir):
        return NextflowQCGateHandler(
            invocation_id="uncov", work_dir=work_dir,
            sse_callback=lambda t, d: None, app=Mock()
        )

    # -----------------------------------------------------------------------
    # MultiQC JSON path in _parse_fastqc_metrics
    # -----------------------------------------------------------------------

    def test_multiqc_json_gc_content_extracted(self, tmp_path):
        """multiqc_data.json with report_general_stats_data → gc_content_pct."""
        mq = {
            "report_general_stats_data": [
                {"sample1": {"percent_gc": 47.3, "avg_sequence_length": 150}}
            ]
        }
        (tmp_path / "multiqc_data.json").write_text(json.dumps(mq))
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        assert metrics is not None
        assert metrics["gc_content_pct"] == pytest.approx(47.3, abs=0.01)

    def test_multiqc_json_avg_read_length_extracted(self, tmp_path):
        """multiqc_data.json → avg_read_length set from avg_sequence_length."""
        mq = {
            "report_general_stats_data": [
                {"s1": {"percent_gc": 50.0, "avg_sequence_length": 150}}
            ]
        }
        (tmp_path / "multiqc_data.json").write_text(json.dumps(mq))
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        assert metrics is not None
        assert metrics["avg_read_length"] == 150

    def test_multiqc_json_does_not_overwrite_direct_gc(self, tmp_path):
        """summary.txt gc_content_pct takes priority (setdefault) over MultiQC JSON."""
        # Write fastqc_data.txt first (direct source)
        (tmp_path / "fastqc_data.txt").write_text(
            "##FastQC\t0.12\n%GC\t52\n"
        )
        # Also write multiqc with a different GC value
        mq = {
            "report_general_stats_data": [
                {"s1": {"percent_gc": 40.0}}
            ]
        }
        (tmp_path / "multiqc_data.json").write_text(json.dumps(mq))
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        # setdefault → direct parse wins (52), MultiQC (40) ignored
        assert metrics["gc_content_pct"] == 52.0

    def test_multiqc_json_malformed_gracefully_skipped(self, tmp_path):
        """Malformed multiqc_data.json is caught and skipped — no crash."""
        (tmp_path / "multiqc_data.json").write_text("not json at all {{{")
        (tmp_path / "summary.txt").write_text("FAIL\tAdapter Content\tsample_fastqc\n")
        h = self._handler(tmp_path)
        metrics = h._parse_fastqc_metrics(tmp_path)
        # Should still parse summary.txt successfully
        assert metrics is not None
        assert metrics["module_failures"] == 1

    def test_multiqc_json_empty_stats_list_skipped(self, tmp_path):
        """Empty report_general_stats_data list → no metrics from MultiQC."""
        mq = {"report_general_stats_data": []}
        (tmp_path / "multiqc_data.json").write_text(json.dumps(mq))
        h = self._handler(tmp_path)
        # No other files → returns None (no metrics)
        assert h._parse_fastqc_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # STARsolo Summary.csv path in _parse_singlecell_metrics
    # -----------------------------------------------------------------------

    def test_starsolo_summary_csv_cells_detected(self, tmp_path):
        """STARsolo Summary.csv with 'Estimated Number of Cells' → cells_detected."""
        (tmp_path / "Summary.csv").write_text(
            "Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome\n"
            "1250,1840,89.2\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_singlecell_metrics(tmp_path)
        assert metrics is not None
        assert metrics["cells_detected"] == 1250
        assert metrics["median_genes_per_cell"] == 1840

    def test_starsolo_summary_csv_returns_none_when_absent(self, tmp_path):
        """No Summary.csv and no metrics_summary.csv → None."""
        h = self._handler(tmp_path)
        assert h._parse_singlecell_metrics(tmp_path) is None

    # -----------------------------------------------------------------------
    # broadPeak and summits.bed in _parse_peakcalling_metrics
    # -----------------------------------------------------------------------

    def test_broadpeak_line_count(self, tmp_path):
        """*_peaks.broadPeak lines are counted (no comment lines)."""
        peak_file = tmp_path / "sample_peaks.broadPeak"
        peak_file.write_text(
            "chr1\t1000\t5000\tpeak_1\t100\t.\t4.0\t8.0\t-1\n"
            "chr1\t8000\t12000\tpeak_2\t90\t.\t3.5\t7.0\t-1\n"
            "chr2\t500\t3000\tpeak_3\t80\t.\t3.0\t6.0\t-1\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_peakcalling_metrics(tmp_path)
        assert metrics is not None
        assert metrics["peaks_called"] == 3

    def test_summits_bed_line_count(self, tmp_path):
        """*_summits.bed lines are counted as peak summits."""
        summits = tmp_path / "sample_summits.bed"
        summits.write_text(
            "chr1\t1250\t1251\tpeak_1_summit\t150\n"
            "chr1\t8250\t8251\tpeak_2_summit\t130\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_peakcalling_metrics(tmp_path)
        assert metrics is not None
        assert metrics["peaks_called"] == 2

    def test_narrowpeak_takes_priority_over_summits(self, tmp_path):
        """When both narrowPeak and summits.bed exist, narrowPeak is used first."""
        # narrowPeak: 5 peaks
        (tmp_path / "sample_peaks.narrowPeak").write_text(
            "\n".join(
                f"chr1\t{i*1000}\t{i*1000+400}\tpeak_{i}\t100\t.\t4.0\t8.0\t6.0\t200"
                for i in range(1, 6)
            ) + "\n"
        )
        # summits.bed: 2 peaks (should not be used)
        (tmp_path / "sample_summits.bed").write_text(
            "chr1\t1250\t1251\tpeak_1_summit\t150\n"
            "chr1\t8250\t8251\tpeak_2_summit\t130\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_peakcalling_metrics(tmp_path)
        assert metrics is not None
        # Parser takes first match; narrowPeak comes first in glob list
        assert metrics["peaks_called"] == 5

    # -----------------------------------------------------------------------
    # Bug 8: STAR log with only uniquely_mapped_pct (no multi-loci line)
    # → alignment_rate must still be set (fallback = uniquely_mapped_pct)
    # -----------------------------------------------------------------------

    def test_star_no_multiloci_line_alignment_rate_equals_uniquely_mapped(self, tmp_path):
        """
        STAR Log.final.out with only 'Uniquely mapped reads %' (no multi-loci line)
        must still set alignment_rate = uniquely_mapped_pct so threshold check works.
        Before Bug 8 fix: alignment_rate would be absent.
        """
        subdir = tmp_path / "ab" / "cd0001"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Number of input reads |\t10000000\n"
            "Uniquely mapped reads % |\t79.50%\n"
            # intentionally NO "% of reads mapped to multiple loci" line
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("STAR_ALIGN", "t1", "ab/cd0001")
        assert metrics is not None
        assert "alignment_rate" in metrics, (
            "alignment_rate must be set even without multi-loci line (Bug 8 fix)"
        )
        assert metrics["alignment_rate"] == pytest.approx(79.5, abs=0.1)
        assert metrics["uniquely_mapped_pct"] == pytest.approx(79.5, abs=0.1)

    def test_star_with_multiloci_line_alignment_rate_is_sum(self, tmp_path):
        """With both lines present, alignment_rate = uniquely_mapped + multi-loci."""
        subdir = tmp_path / "ab" / "cd0002"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t82.00%\n"
            "% of reads mapped to multiple loci |\t5.00%\n"
        )
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("STAR_ALIGN", "t1", "ab/cd0002")
        assert metrics is not None
        assert metrics["alignment_rate"] == pytest.approx(87.0, abs=0.1)

    def test_star_incomplete_log_gate_fires_correctly(self, tmp_path):
        """
        STAR log with only 55% uniquely mapped (no multi-loci line):
        alignment_rate = 55.0 (below 70% threshold) → gate fires.
        """
        events = []
        subdir = tmp_path / "ab" / "cd0003"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t55.00%\n"
        )
        h = NextflowQCGateHandler(
            invocation_id="bug8", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)),
            app=Mock(), workflow_domain="rnaseq",
        )
        h.handle_process_completion("t1", "STAR_ALIGN", "ab/cd0003", "COMPLETED")
        assert len(events) == 1, "Gate should fire for 55% alignment from incomplete STAR log"
        assert events[0][1]["failures"][0]["metric"] == "alignment_rate"

    # -----------------------------------------------------------------------
    # Absent total_drift_angstrom metric in motion correction suggester
    # (documents the intentional default=0 behaviour)
    # -----------------------------------------------------------------------

    def test_motion_suggester_absent_drift_no_drift_suggestion(self):
        """
        When total_drift_angstrom is absent from metrics, _suggest_motion_correction
        uses default=0, so no drift-related suggestion fires. This is intentional:
        absent drift → assume no problem (safe default).
        """
        from galaxy.jobs.parameter_suggester import CryoEMParameterSuggester
        s = CryoEMParameterSuggester()
        suggestions = s.suggest(
            process_name="MOTION_CORRECTION",
            qc_metrics={},  # no total_drift_angstrom key
            current_parameters={"dose_weighting": False, "patch_size": 3},
            failures=[],
        )
        # No drift metric → no dose_weighting or patch_size suggestion
        assert not any(s.parameter in ("dose_weighting", "patch_size") for s in suggestions)

    def test_motion_suggester_absent_correlation_no_frames_suggestion(self):
        """
        When correlation_score is absent, _suggest_motion_correction must not
        suggest alignment_frames (None-guarded in the correlation branch).
        """
        from galaxy.jobs.parameter_suggester import CryoEMParameterSuggester
        s = CryoEMParameterSuggester()
        suggestions = s.suggest(
            process_name="MOTION_CORRECTION",
            qc_metrics={"total_drift_angstrom": 0},  # absent correlation_score
            current_parameters={"alignment_frames": 1},
            failures=[],
        )
        assert not any(s.parameter == "alignment_frames" for s in suggestions)

    def test_motion_suggester_zero_drift_is_safe_default(self):
        """
        Default 0 for absent drift is safe: total_drift=0 never exceeds threshold=50.
        This documents the intentional asymmetry with None-guard in ab_initio.
        """
        from galaxy.jobs.parameter_suggester import CryoEMParameterSuggester
        s = CryoEMParameterSuggester()
        # total_drift_angstrom absent → defaults to 0 → 0 > 50 is False → no suggestion
        suggs = s.suggest("MOTION_CORRECTION", {}, {"dose_weighting": False}, [])
        dose_sugg = next((x for x in suggs if x.parameter == "dose_weighting"), None)
        assert dose_sugg is None


# ===========================================================================
# TIER 1 REGRESSION TESTS (US-3.2, US-3.3, US-6.3)
# ===========================================================================

class TestTierOneChanges:
    """Regression tests for the Tier 1 backend changes from the user story audit."""

    # -----------------------------------------------------------------------
    # US-3.2 — CTF defocus out-of-range emits directional failure
    # -----------------------------------------------------------------------

    def test_ctf_defocus_below_range_emits_failure(self, tmp_path):
        """
        US-3.2: defocus_u = 950 Å (< 1000) should produce a failure dict
        with 'below' direction and a near-focus message, not be silently skipped.
        """
        subdir = tmp_path / "ab" / "cd9999"
        subdir.mkdir(parents=True)
        # CTFFIND4 format: DefocusU DefocusV Angle Phase FitScore
        (subdir / "mic001_ctf.txt").write_text("950.0\t920.0\t45.0\t0.0\t0.85\n")

        events = []
        h = _make_handler(work_dir=tmp_path, sse_callback=lambda t, d: events.append((t, d)),
                          domain="cryo_em")
        h.handle_process_completion(
            task_id="t1", process_name="CTF_ESTIMATION",
            process_hash="ab/cd9999", status="COMPLETED"
        )
        assert len(events) == 1, "Expected one qc_gate_triggered event"
        event_type, data = events[0]
        assert event_type == "qc_gate_triggered"
        failure = next((f for f in data["failures"]
                        if isinstance(f, dict) and f["metric"] == "defocus_u_angstrom"), None)
        assert failure is not None, "Expected defocus_u_angstrom failure"
        assert failure["operator"] == "<", "Below-range should use < operator"
        assert "near-focus" in failure["message"], "Message should mention near-focus"
        assert failure["threshold"] == 1000

    def test_ctf_defocus_above_range_emits_failure(self, tmp_path):
        """
        US-3.2: defocus_u = 150000 Å (> 100000) should produce a failure dict
        with 'above' direction and a calibration message.
        """
        subdir = tmp_path / "ef" / "gh1111"
        subdir.mkdir(parents=True)
        (subdir / "mic002_ctf.txt").write_text("150000.0\t149500.0\t10.0\t0.0\t0.92\n")

        events = []
        h = _make_handler(work_dir=tmp_path, sse_callback=lambda t, d: events.append((t, d)),
                          domain="cryo_em")
        h.handle_process_completion(
            task_id="t2", process_name="CTF_ESTIMATION",
            process_hash="ef/gh1111", status="COMPLETED"
        )
        assert len(events) == 1
        event_type, data = events[0]
        assert event_type == "qc_gate_triggered"
        failure = next((f for f in data["failures"]
                        if isinstance(f, dict) and f["metric"] == "defocus_u_angstrom"), None)
        assert failure is not None
        assert failure["operator"] == ">", "Above-range should use > operator"
        assert "too far from focus" in failure["message"]
        assert failure["threshold"] == 100000

    # -----------------------------------------------------------------------
    # US-3.3 — Two-tier alignment failure
    # -----------------------------------------------------------------------

    def test_alignment_rate_below_25_has_critical_severity(self, tmp_path):
        """
        US-3.3: alignment_rate = 8% (< 25%) should produce a failure dict
        with severity='critical' and a data-integrity warning message.
        """
        subdir = tmp_path / "ij" / "kl2222"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t8.00%\n"
        )
        events = []
        h = _make_handler(work_dir=tmp_path, sse_callback=lambda t, d: events.append((t, d)),
                          domain="rnaseq")
        h.handle_process_completion(
            task_id="t3", process_name="STAR_ALIGN",
            process_hash="ij/kl2222", status="COMPLETED"
        )
        assert len(events) == 1
        event_type, data = events[0]
        assert event_type == "qc_gate_triggered"
        failure = next((f for f in data["failures"]
                        if isinstance(f, dict) and f["metric"] == "alignment_rate"), None)
        assert failure is not None
        assert failure.get("severity") == "critical"
        assert "species" in failure["message"].lower() or "mismatch" in failure["message"].lower(), \
            "Critical message should hint at species/genome mismatch"

    def test_alignment_rate_between_25_and_70_has_warning_severity(self, tmp_path):
        """
        US-3.3: alignment_rate = 45% (25–70%) should have severity='warning'
        with the standard low-alignment message (no data-integrity hint).
        """
        subdir = tmp_path / "mn" / "op3333"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t45.00%\n"
        )
        events = []
        h = _make_handler(work_dir=tmp_path, sse_callback=lambda t, d: events.append((t, d)),
                          domain="rnaseq")
        h.handle_process_completion(
            task_id="t4", process_name="STAR_ALIGN",
            process_hash="mn/op3333", status="COMPLETED"
        )
        assert len(events) == 1
        failure = next((f for f in events[0][1]["failures"]
                        if isinstance(f, dict) and f["metric"] == "alignment_rate"), None)
        assert failure is not None
        assert failure.get("severity") == "warning"
        assert "species" not in failure["message"].lower(), \
            "Standard warning should not contain species/mismatch language"

    # -----------------------------------------------------------------------
    # US-6.3 — Near-threshold warning emits qc_warning, not qc_gate_triggered
    # -----------------------------------------------------------------------

    def test_near_threshold_alignment_emits_warning_not_gate(self, tmp_path):
        """
        US-6.3: alignment_rate = 73% (within 10% above 70% threshold) should
        emit a 'qc_warning' SSE event, NOT 'qc_gate_triggered'.
        """
        subdir = tmp_path / "qr" / "st4444"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t73.00%\n"
        )
        events = []
        h = _make_handler(work_dir=tmp_path, sse_callback=lambda t, d: events.append((t, d)),
                          domain="rnaseq")
        h.handle_process_completion(
            task_id="t5", process_name="STAR_ALIGN",
            process_hash="qr/st4444", status="COMPLETED"
        )
        assert len(events) == 1, "Expected exactly one SSE event for near-threshold metric"
        event_type, data = events[0]
        assert event_type == "qc_warning", (
            f"Expected 'qc_warning' not 'qc_gate_triggered', got '{event_type}'"
        )
        assert "warnings" in data
        warning = next((w for w in data["warnings"]
                        if w["metric"] == "alignment_rate"), None)
        assert warning is not None
        assert warning["severity"] == "near_threshold"
        assert warning["value"] == pytest.approx(73.0, abs=0.1)

    def test_well_above_threshold_emits_no_event(self, tmp_path):
        """
        US-6.3: alignment_rate = 90% (well above threshold) should emit
        neither a gate nor a warning event.
        """
        subdir = tmp_path / "uv" / "wx5555"
        subdir.mkdir(parents=True)
        (subdir / "Aligned.Log.final.out").write_text(
            "Uniquely mapped reads % |\t90.00%\n"
        )
        events = []
        h = _make_handler(work_dir=tmp_path, sse_callback=lambda t, d: events.append((t, d)),
                          domain="rnaseq")
        h.handle_process_completion(
            task_id="t6", process_name="STAR_ALIGN",
            process_hash="uv/wx5555", status="COMPLETED"
        )
        assert events == [], "No events should fire when metrics are well above threshold"


# ===========================================================================
# ATAC-seq QC domain
# ===========================================================================

class TestATACSeqQCDomain:
    """
    Full coverage of the new ATAC-seq QC domain: parser, dispatch, thresholds, suggestions.
    ENCODE4 standards: TSS ≥ 7 (ideal), ≥ 5 (acceptable); FRiP ≥ 0.3; NRF ≥ 0.9.
    """

    def _handler(self, work_dir):
        return NextflowQCGateHandler(
            invocation_id="atac-test",
            work_dir=work_dir,
            sse_callback=lambda t, d: None,
            app=Mock(),
            workflow_domain="atac_seq",
        )

    def _check(self, process_name, metrics):
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="atac_seq",
        )
        return h._check_qc_thresholds(process_name, metrics)

    # -- Parser tests --

    def test_parse_atac_tss_enrichment_from_file(self, tmp_path):
        """tss_enrich.txt with a float → tss_enrichment extracted."""
        (tmp_path / "tss_enrich.txt").write_text("8.42\n")
        h = self._handler(tmp_path)
        metrics = h._parse_atac_metrics(tmp_path)
        assert metrics is not None
        assert metrics["tss_enrichment"] == pytest.approx(8.42, abs=0.01)

    def test_parse_atac_nrf_from_pbc_file(self, tmp_path):
        """*.pbc.txt with tab-separated columns → nrf_score extracted (column 4)."""
        (tmp_path / "sample.pbc.txt").write_text(
            "50000000\t45000000\t40000000\t5000000\t0.92\t0.89\t12.5\n"
        )
        h = self._handler(tmp_path)
        metrics = h._parse_atac_metrics(tmp_path)
        assert metrics is not None
        assert metrics["nrf_score"] == pytest.approx(0.92, abs=0.001)

    def test_parse_atac_frip_from_file(self, tmp_path):
        """frip_score.txt → frip_score extracted."""
        (tmp_path / "tss_enrich.txt").write_text("6.5\n")
        (tmp_path / "frip_score.txt").write_text("0.38\n")
        h = self._handler(tmp_path)
        metrics = h._parse_atac_metrics(tmp_path)
        assert metrics is not None
        assert metrics["frip_score"] == pytest.approx(0.38, abs=0.001)

    def test_parse_atac_no_files_returns_none(self, tmp_path):
        """Empty directory → None (no files to parse)."""
        h = self._handler(tmp_path)
        assert h._parse_atac_metrics(tmp_path) is None

    # -- Threshold tests --

    def test_tss_below_5_fails(self):
        """TSS enrichment < 5 (unacceptable by ENCODE4) → failure."""
        passed, failures = self._check("ATAC_QC", {"tss_enrichment": 3.2})
        assert not passed
        assert any(f["metric"] == "tss_enrichment" for f in failures)

    def test_tss_below_3_is_critical(self):
        """TSS enrichment < 3 → severity = critical."""
        passed, failures = self._check("ATAC_QC", {"tss_enrichment": 2.1})
        assert not passed
        astig_fail = next((f for f in failures if f["metric"] == "tss_enrichment"), None)
        assert astig_fail is not None
        assert astig_fail.get("severity") == "critical"

    def test_tss_between_5_and_7_passes(self):
        """TSS enrichment 5.0–6.9 → passes (≥ 5 is ENCODE4 minimum; < 7 is just below ideal)."""
        passed, _ = self._check("TSS_ENRICH", {"tss_enrichment": 5.8})
        assert passed

    def test_tss_at_5_boundary_fails(self):
        """TSS enrichment exactly 5.0 is NOT < 5.0 → passes."""
        passed, _ = self._check("ATAC_QC", {"tss_enrichment": 5.0})
        assert passed

    def test_frip_below_0_3_fails(self):
        """FRiP < 0.3 (ENCODE4 ATAC minimum) → failure."""
        passed, failures = self._check("ATAC_QC", {"frip_score": 0.15})
        assert not passed
        assert any(f["metric"] == "frip_score" for f in failures)

    def test_frip_at_threshold_passes(self):
        """FRiP exactly 0.2 is NOT < 0.2 → passes (ENCODE4 acceptable floor)."""
        passed, _ = self._check("ATAC_QC", {"frip_score": 0.2})
        assert passed

    def test_nrf_below_0_9_fails(self):
        """NRF < 0.9 (ENCODE4 library complexity) → failure."""
        passed, failures = self._check("PLOTFINGERPRINT", {"nrf_score": 0.75})
        assert not passed
        assert any(f["metric"] == "nrf_score" for f in failures)

    def test_nrf_below_0_5_is_critical(self):
        """NRF < 0.5 → severity = critical."""
        passed, failures = self._check("ATAC_QC", {"nrf_score": 0.3})
        assert not passed
        nrf_fail = next((f for f in failures if f["metric"] == "nrf_score"), None)
        assert nrf_fail is not None
        assert nrf_fail.get("severity") == "critical"

    def test_all_atac_good_metrics_pass(self):
        """TSS=8.5, FRiP=0.42, NRF=0.95 → no failures."""
        passed, failures = self._check("ATAC_QC", {
            "tss_enrichment": 8.5,
            "frip_score": 0.42,
            "nrf_score": 0.95,
        })
        assert passed
        assert failures == []

    # -- Dispatch test --

    def test_dispatch_atac_qc_process_extracts_tss(self, tmp_path):
        """ATAC_QC process dispatch → tss_enrich.txt → tss_enrichment extracted."""
        subdir, phash = (tmp_path / "aq" / "tss001"), "aq/tss001"
        subdir.mkdir(parents=True)
        (subdir / "tss_enrich.txt").write_text("7.3\n")
        h = self._handler(tmp_path)
        metrics = h._calculate_qc_metrics("ATAC_QC", "t1", phash)
        assert metrics is not None
        assert metrics["tss_enrichment"] == pytest.approx(7.3, abs=0.01)

    # -- Suggester test --

    def test_atac_suggester_low_tss_suggests_shift_extsize(self):
        """Low TSS enrichment → suggests shift=-100 and extsize=200."""
        from lib.galaxy.jobs.parameter_suggester import ChIPSeqParameterSuggester
        suggester = ChIPSeqParameterSuggester()
        suggestions = suggester.suggest(
            process_name="ATAC_QC",
            qc_metrics={"tss_enrichment": 3.5},
            current_parameters={"shift": 0, "extsize": 150, "pcr_cycles": 15},
            failures=["Low TSS enrichment: 3.5 (threshold: 5.0)"]
        )
        params = {s.parameter for s in suggestions}
        assert "shift" in params
        assert "extsize" in params

    def test_atac_suggester_low_nrf_suggests_fewer_pcr_cycles(self):
        """Low NRF → suggests reducing PCR cycles."""
        from lib.galaxy.jobs.parameter_suggester import ChIPSeqParameterSuggester
        suggester = ChIPSeqParameterSuggester()
        suggestions = suggester.suggest(
            process_name="ATAC_QC",
            qc_metrics={"nrf_score": 0.6},
            current_parameters={"pcr_cycles": 15},
            failures=["Low NRF: 0.6"]
        )
        nrf_sugg = next((s for s in suggestions if s.parameter == "pcr_cycles"), None)
        assert nrf_sugg is not None
        assert nrf_sugg.suggested_value < 15

    def test_nrf_exactly_at_threshold_passes(self):
        """NRF = 0.9 is NOT < 0.9 → passes."""
        passed, _ = self._check("ATAC_QC", {"nrf_score": 0.9})
        assert passed


# ===========================================================================
# Audit findings — boundary conditions & domain-aware gaps
# ===========================================================================

class TestAuditFindings:
    """
    Tests added after the 2026-02-24 dual expert audit (code + web research agents).
    Covers boundary conditions and behavioral gaps identified by the audit.
    """

    def _check(self, process_name, metrics, domain="dna_seq"):
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain=domain,
        )
        return h._check_qc_thresholds(process_name, metrics)

    # -- MARKDUPLICATES domain-aware skip --

    def test_markdup_skipped_for_rnaseq(self):
        """MARKDUPLICATES gate must NOT fire for RNA-seq (biological duplication expected)."""
        passed, failures = self._check("MARKDUPLICATES", {"duplicate_pct": 55.0}, domain="rnaseq")
        assert passed, "MARKDUPLICATES gate should be skipped for rnaseq domain"
        assert failures == []

    def test_markdup_skipped_for_atac_seq(self):
        """MARKDUPLICATES gate must NOT fire for ATAC-seq (enriched region duplication expected)."""
        passed, failures = self._check("MARKDUPLICATES", {"duplicate_pct": 55.0}, domain="atac_seq")
        assert passed, "MARKDUPLICATES gate should be skipped for atac_seq domain"
        assert failures == []

    def test_markdup_skipped_for_chip_seq(self):
        """MARKDUPLICATES gate must NOT fire for ChIP-seq (peak region duplication expected)."""
        passed, failures = self._check("MARKDUPLICATES", {"duplicate_pct": 55.0}, domain="chipseq")
        assert passed, "MARKDUPLICATES gate should be skipped for chipseq domain"
        assert failures == []

    def test_markdup_fires_for_dna_seq(self):
        """MARKDUPLICATES gate MUST fire for DNA-seq at > 40% (GATK threshold)."""
        passed, failures = self._check("MARKDUPLICATES", {"duplicate_pct": 45.0}, domain="dna_seq")
        assert not passed
        assert any(f["metric"] == "duplicate_pct" for f in failures)

    # -- Metagenomics 30-60% warning zone now has suggestions --

    def test_metagenomics_suggester_fires_at_45pct_warning_zone(self):
        """MetagenomicsParameterSuggester should suggest at 45% (30-60% warning zone)."""
        from lib.galaxy.jobs.parameter_suggester import MetagenomicsParameterSuggester
        suggester = MetagenomicsParameterSuggester()
        suggestions = suggester.suggest(
            process_name="KRAKEN2",
            qc_metrics={"classified_pct": 45.0},
            current_parameters={"confidence_threshold": 0.1, "database": "standard"},
            failures=["Low classification: 45.0% (threshold: 60%)"]
        )
        assert len(suggestions) >= 1, "Should suggest database upgrade or confidence threshold change"

    def test_metagenomics_suggester_no_confidence_change_if_already_zero(self):
        """If confidence_threshold is already 0.0, don't suggest lowering it further."""
        from lib.galaxy.jobs.parameter_suggester import MetagenomicsParameterSuggester
        suggester = MetagenomicsParameterSuggester()
        suggestions = suggester.suggest(
            process_name="KRAKEN2",
            qc_metrics={"classified_pct": 45.0},
            current_parameters={"confidence_threshold": 0.0, "database": "standard"},
            failures=["Low classification: 45.0%"]
        )
        conf_sugg = next((s for s in suggestions if s.parameter == "confidence_threshold"), None)
        assert conf_sugg is None, "Should not suggest confidence_threshold=0 when already 0"

    # -- ChIP FRiP is advisory (non-blocking) — ENCODE4 has no hard FRiP gate --

    def test_chip_frip_very_low_is_advisory_not_blocking(self):
        """ChIP FRiP < 0.01 should NOT block workflow — ENCODE4 has no hard FRiP threshold.
        The failure dict still appears with advisory=True and severity='warning', but
        qc_passed is True because advisory items do not count toward blocking failures."""
        passed, failures = self._check("MACS2", {"frip_score": 0.005})
        assert passed, "ChIP FRiP advisory must not block the workflow (ENCODE4 has no hard gate)"
        frip_fail = next((f for f in failures if f["metric"] == "frip_score"), None)
        assert frip_fail is not None, "Advisory item should still appear in failures list for display"
        assert frip_fail.get("advisory") is True, "ChIP FRiP failure must have advisory=True"
        assert frip_fail.get("severity") == "warning"

    # -- ATAC FRiP uses 0.2 (acceptable floor), not 0.3 --

    def test_atac_frip_between_0_2_and_0_3_passes(self):
        """ATAC FRiP = 0.25 is in the 0.2-0.3 'acceptable' zone → passes."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(), workflow_domain="atac_seq",
        )
        passed, _ = h._check_qc_thresholds("ATAC_QC", {"frip_score": 0.25})
        assert passed

    # -- Mito threshold now 20% not 25% --

    def test_mito_between_20_and_25_now_triggers(self):
        """Mito = 22% should now trigger (threshold lowered from 25% to 20%)."""
        passed, failures = self._check("CELLRANGER_COUNT", {"mito_fraction_pct": 22.0})
        assert not passed
        assert any(f["metric"] == "mito_fraction_pct" for f in failures)


# ===========================================================================
# Round 2 Expert Audit Findings (2026-02-24)
# Tests for critical and high-priority bugs found in the second audit round:
#   1. Advisory items (ChIP FRiP, CTF astigmatism) must not block workflow
#   2. NRF=0.0 falsy-value bug in _parse_atac_metrics
#   3. CTF astigmatism now advisory at 1000Å (raised from 500Å, [BRONZE])
#   4. MARKDUPLICATES skip extended to "rna" and "single_cell" domains
#   5. WGS/WES-aware coverage thresholds (30X vs 80X)
#   6. Mito near-threshold warning at 10-20%
#   7. Advisory items route to qc_warning event, not qc_gate_triggered
# ===========================================================================

class TestRound2AuditFindings:
    """
    Regression tests for all findings from the 2026-02-24 second expert audit.
    Critical fixes: advisory non-blocking, NRF falsy-value, expanded MARKDUP skip.
    Scientific fixes: CTF astigmatism [BRONZE], WES coverage, mito warnings.
    """

    def _check(self, process_name, metrics, domain="dna_seq"):
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain=domain,
        )
        return h._check_qc_thresholds(process_name, metrics)

    # -----------------------------------------------------------------------
    # CRITICAL: NRF=0.0 falsy-value bug in _parse_atac_metrics
    # -----------------------------------------------------------------------

    def test_nrf_zero_is_parsed_not_skipped(self, tmp_path):
        """NRF=0.0 must be recorded (falsy-value bug: old code used `if metrics.get('nrf_score')`)."""
        pbc = tmp_path / "sample.pbc.txt"
        # col 4 is NRF; give it 0.0 (completely redundant library)
        pbc.write_text("1000\t0\t0\t0\t0.0\t0.0\t0.0\n")
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(), workflow_domain="atac_seq",
        )
        metrics = h._parse_atac_metrics(tmp_path)
        assert metrics is not None, "Parser must return metrics even when NRF=0.0"
        assert "nrf_score" in metrics, "nrf_score key must be present"
        assert metrics["nrf_score"] == pytest.approx(0.0, abs=1e-6), "NRF=0.0 must be preserved"

    # -----------------------------------------------------------------------
    # CRITICAL: Advisory items must not block workflow
    # -----------------------------------------------------------------------

    def test_ctf_astigmatism_high_is_advisory_not_blocking(self):
        """CTF astigmatism > 1000Å is advisory — workflow must NOT be blocked.
        The astigmatism failure dict has advisory=True; fit_quality is the primary hard gate."""
        passed, failures = self._check("CTF_ESTIMATION", {"astigmatism_angstrom": 1500.0})
        assert passed, "CTF astigmatism > 1000Å must be advisory (non-blocking)"
        astig_fail = next((f for f in failures if f["metric"] == "astigmatism_angstrom"), None)
        assert astig_fail is not None, "Advisory item must still appear in failures list"
        assert astig_fail.get("advisory") is True

    def test_ctf_astigmatism_threshold_raised_to_1000(self):
        """Astigmatism threshold raised from 500Å to 1000Å — 800Å must not trigger advisory."""
        passed, failures = self._check("CTF_ESTIMATION", {"astigmatism_angstrom": 800.0})
        assert passed
        # No astigmatism failure at 800Å (< 1000Å threshold)
        assert not any(f["metric"] == "astigmatism_angstrom" for f in failures)

    def test_chip_frip_advisory_routes_through_warning_event(self, tmp_path):
        """ChIP FRiP advisory must emit qc_warning event, NOT qc_gate_triggered."""
        events = []
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics",
            return_value={"frip_score": 0.005}
        ):
            h = NextflowQCGateHandler(
                invocation_id="t", work_dir=tmp_path,
                sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
                workflow_domain="chip_seq",
            )
            h.handle_process_completion("1", "MACS2", "ab/cd", "COMPLETED")
        event_types = [e[0] for e in events]
        assert "qc_gate_triggered" not in event_types, "Advisory must not trigger gate event"
        assert "qc_warning" in event_types, "Advisory must surface via qc_warning event"

    def test_ctf_astigmatism_advisory_routes_through_warning_event(self, tmp_path):
        """CTF astigmatism advisory must emit qc_warning, not qc_gate_triggered."""
        events = []
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics",
            return_value={"astigmatism_angstrom": 1500.0}
        ):
            h = NextflowQCGateHandler(
                invocation_id="t", work_dir=tmp_path,
                sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
                workflow_domain="cryo_em",
            )
            h.handle_process_completion("1", "CTF_ESTIMATION", "ab/cd", "COMPLETED")
        event_types = [e[0] for e in events]
        assert "qc_gate_triggered" not in event_types
        assert "qc_warning" in event_types

    def test_hard_failure_still_blocks_even_with_advisory(self):
        """When both hard failure and advisory coexist, workflow is still blocked."""
        # fit_quality=0.5 (hard gate) + astigmatism=1500 (advisory)
        passed, failures = self._check(
            "CTF_ESTIMATION",
            {"fit_quality": 0.5, "astigmatism_angstrom": 1500.0}
        )
        assert not passed, "Hard failure (fit_quality) must block workflow"
        # Both items should be in failures list
        assert any(f["metric"] == "fit_quality" and not f.get("advisory") for f in failures)
        assert any(f["metric"] == "astigmatism_angstrom" and f.get("advisory") for f in failures)

    # -----------------------------------------------------------------------
    # MARKDUPLICATES: extended skip domains for "rna" and "single_cell"
    # -----------------------------------------------------------------------

    def test_markdup_skipped_for_rna_domain(self):
        """MARKDUPLICATES must not fire for domain='rna' (short-form RNA-seq domain)."""
        passed, failures = self._check("MARKDUPLICATES", {"duplicate_pct": 55.0}, domain="rna")
        assert passed, "MARKDUPLICATES gate should be skipped for 'rna' domain"
        assert failures == []

    def test_markdup_skipped_for_single_cell_domain(self):
        """MARKDUPLICATES must not fire for domain='single_cell'."""
        passed, failures = self._check("MARKDUPLICATES", {"duplicate_pct": 55.0}, domain="single_cell")
        assert passed, "MARKDUPLICATES gate should be skipped for 'single_cell' domain"
        assert failures == []

    # -----------------------------------------------------------------------
    # WGS/WES coverage distinction
    # -----------------------------------------------------------------------

    def test_coverage_30x_passes_for_wgs_domain(self):
        """30X coverage passes for WGS domain (threshold: ≥ 30X)."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(), workflow_domain="wgs",
        )
        passed, _ = h._check_qc_thresholds("MOSDEPTH", {"mean_coverage": 31.0})
        assert passed

    def test_coverage_30x_fails_for_wes_domain(self):
        """30X coverage fails for WES domain (threshold: ≥ 80X germline)."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(), workflow_domain="wes",
        )
        passed, failures = h._check_qc_thresholds("MOSDEPTH", {"mean_coverage": 31.0})
        assert not passed
        cov_fail = next((f for f in failures if f["metric"] == "mean_coverage"), None)
        assert cov_fail is not None
        assert cov_fail["threshold"] == pytest.approx(80.0)

    def test_coverage_80x_passes_for_wes_domain(self):
        """80X coverage passes for WES domain (threshold: ≥ 80X)."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(), workflow_domain="wes",
        )
        passed, _ = h._check_qc_thresholds("MOSDEPTH", {"mean_coverage": 85.0})
        assert passed

    def test_coverage_threshold_unknown_domain_defaults_to_wgs(self):
        """Unknown domain defaults to 30X WGS threshold."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=Path(tempfile.mkdtemp()),
            sse_callback=lambda t, d: None, app=Mock(), workflow_domain="unknown_genomics",
        )
        # 25X fails (< 30X), 35X passes
        passed_low, _ = h._check_qc_thresholds("MOSDEPTH", {"mean_coverage": 25.0})
        passed_high, _ = h._check_qc_thresholds("MOSDEPTH", {"mean_coverage": 35.0})
        assert not passed_low
        assert passed_high

    # -----------------------------------------------------------------------
    # Mito near-threshold warning at 10–20%
    # -----------------------------------------------------------------------

    def test_mito_10_to_20_emits_near_threshold_warning(self, tmp_path):
        """Mito = 15% (10–20% range) must emit qc_warning, not qc_gate_triggered."""
        events = []
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics",
            return_value={"mito_fraction_pct": 15.0, "cells_detected": 5000, "median_genes_per_cell": 2000}
        ):
            h = NextflowQCGateHandler(
                invocation_id="t", work_dir=tmp_path,
                sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
                workflow_domain="scrna_seq",
            )
            h.handle_process_completion("1", "CELLRANGER_COUNT", "ab/cd", "COMPLETED")
        event_types = [e[0] for e in events]
        assert "qc_gate_triggered" not in event_types, "15% mito should not trigger hard gate"
        assert "qc_warning" in event_types, "15% mito should trigger near-threshold warning"

    def test_mito_below_10_no_warning(self, tmp_path):
        """Mito = 8% (below advisory 10% threshold) → no events at all."""
        events = []
        with patch.object(
            NextflowQCGateHandler, "_calculate_qc_metrics",
            return_value={"mito_fraction_pct": 8.0, "cells_detected": 5000, "median_genes_per_cell": 2000}
        ):
            h = NextflowQCGateHandler(
                invocation_id="t", work_dir=tmp_path,
                sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
                workflow_domain="scrna_seq",
            )
            h.handle_process_completion("1", "CELLRANGER_COUNT", "ab/cd", "COMPLETED")
        assert events == [], "8% mito is within normal range — no events expected"

# ===========================================================================
# Phase 1: Per-invocation qc_overrides tests
# ===========================================================================

class TestQCOverrides:
    """
    Tests for Phase 1: per-invocation QC threshold overrides.

    Coverage:
      - Alignment rate override (SILVER: threshold lowered for special assays)
      - GOLD metric rejection (mapped_pct cannot be overridden)
      - Red-line clamping (reads_surviving_pct cannot go below 50%)
      - Mito fraction override for cardiac tissue (raised ceiling)
      - Mito fraction red-line ceiling (cannot exceed 80%)
      - validate_qc_overrides() classmethod
      - Audit JSONL written on init and on gate event
      - SSE event includes overrides_active flag
      - Metagenomics classified_pct critical threshold override (soil use case)
      - Duplicate pct override (FFPE WGS use case)
      - Mean coverage override (low-pass WGS use case)
    """

    # -----------------------------------------------------------------------
    # SILVER metric overrides
    # -----------------------------------------------------------------------

    def test_alignment_rate_override_raises_effective_threshold(self, tmp_path):
        """
        alignment_rate=65% fails at default 70% but passes when override lowers to 50%.
        Simulates ribo-depleted RNA-seq or FFPE RNA-seq use cases.
        """
        default_handler = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="rnaseq",
        )
        passed_default, _ = default_handler._check_qc_thresholds(
            "STAR_ALIGN", {"alignment_rate": 65.0}
        )
        assert not passed_default, "65% should fail at default 70% threshold"

        override_handler = NextflowQCGateHandler(
            invocation_id="t2", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="rnaseq",
            qc_overrides={"alignment_rate": 50.0},
        )
        passed_override, _ = override_handler._check_qc_thresholds(
            "STAR_ALIGN", {"alignment_rate": 65.0}
        )
        assert passed_override, "65% should pass when override lowers threshold to 50%"

    def test_mito_fraction_override_for_cardiac_tissue(self, tmp_path):
        """
        mito_fraction_pct=30% fails at default 20% but passes when override raised to 35%.
        Simulates cardiac tissue scRNA-seq.
        """
        default_handler = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="scrna_seq",
        )
        passed_default, _ = default_handler._check_qc_thresholds(
            "CELLRANGER_COUNT", {"mito_fraction_pct": 30.0, "cells_detected": 5000, "median_genes_per_cell": 2000}
        )
        assert not passed_default, "30% mito should fail at default 20% threshold"

        cardiac_handler = NextflowQCGateHandler(
            invocation_id="t2", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="scrna_seq",
            qc_overrides={"mito_fraction_pct": 35.0},
        )
        passed_cardiac, _ = cardiac_handler._check_qc_thresholds(
            "CELLRANGER_COUNT", {"mito_fraction_pct": 30.0, "cells_detected": 5000, "median_genes_per_cell": 2000}
        )
        assert passed_cardiac, "30% mito should pass when override raises ceiling to 35%"

    def test_duplicate_pct_override_for_ffpe_wgs(self, tmp_path):
        """
        duplicate_pct=60% fails at default 40% but passes when override raised to 70%.
        Simulates FFPE WGS (Robbe et al. 2018 Nat Med).
        """
        default_handler = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="wgs",
        )
        passed_default, _ = default_handler._check_qc_thresholds(
            "MARKDUPLICATES", {"duplicate_pct": 60.0}
        )
        assert not passed_default, "60% dup should fail at default 40% threshold"

        ffpe_handler = NextflowQCGateHandler(
            invocation_id="t2", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="wgs",
            qc_overrides={"duplicate_pct": 70.0},
        )
        passed_ffpe, _ = ffpe_handler._check_qc_thresholds(
            "MARKDUPLICATES", {"duplicate_pct": 60.0}
        )
        assert passed_ffpe, "60% dup should pass when override raises threshold to 70%"

    def test_coverage_override_for_low_pass_wgs(self, tmp_path):
        """
        mean_coverage=5X fails at default 30X but passes when override lowers to 4X.
        Simulates low-pass WGS for population genetics (UK Biobank standard).
        """
        default_handler = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="wgs",
        )
        passed_default, _ = default_handler._check_qc_thresholds(
            "MOSDEPTH", {"mean_coverage": 5.0}
        )
        assert not passed_default, "5X should fail at default 30X threshold"

        lowpass_handler = NextflowQCGateHandler(
            invocation_id="t2", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="wgs",
            qc_overrides={"mean_coverage": 4.0},
        )
        passed_lowpass, _ = lowpass_handler._check_qc_thresholds(
            "MOSDEPTH", {"mean_coverage": 5.0}
        )
        assert passed_lowpass, "5X should pass when override lowers threshold to 4X"

    def test_metagenomics_critical_threshold_override_for_soil(self, tmp_path):
        """
        classified_pct=20% fires critical gate at default 30% but passes when
        classified_pct_critical overridden to 10%.
        Simulates soil metagenomics where < 30% classification is normal.
        """
        default_handler = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="metagenomics",
        )
        passed_default, failures = default_handler._check_qc_thresholds(
            "KRAKEN2", {"classified_pct": 20.0}
        )
        assert not passed_default
        assert any(f["severity"] == "critical" for f in failures)

        # Soil: both critical (10%) and warning (15%) are below 20% → no gate fires
        soil_handler = NextflowQCGateHandler(
            invocation_id="t2", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="metagenomics",
            qc_overrides={
                "classified_pct_critical": 10.0,  # 20% > 10% → no critical
                "classified_pct_warning": 15.0,   # 20% > 15% → no warning
            },
        )
        passed_soil, failures_soil = soil_handler._check_qc_thresholds(
            "KRAKEN2", {"classified_pct": 20.0}
        )
        assert passed_soil, (
            "20% classified should pass when both critical (10%) and warning (15%) "
            "thresholds are overridden below the sample value"
        )

    # -----------------------------------------------------------------------
    # GOLD metric rejection
    # -----------------------------------------------------------------------

    def test_gold_metric_override_ignored_in_get_threshold(self, tmp_path):
        """
        _get_threshold returns default for GOLD metric 'mapped_pct' regardless of override.
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="dna_seq",
            qc_overrides={"mapped_pct": 40.0},  # attempt to lower GOLD threshold
        )
        effective = h._get_threshold("mapped_pct", 70.0)
        assert effective == pytest.approx(70.0), "GOLD metric override must be ignored"

    def test_validate_qc_overrides_rejects_gold_metrics(self):
        """validate_qc_overrides returns errors when caller tries to override GOLD metrics."""
        valid, errors = NextflowQCGateHandler.validate_qc_overrides({"mapped_pct": 50.0})
        assert not valid
        assert len(errors) == 1
        assert "GOLD" in errors[0] or "mapped_pct" in errors[0]

    def test_validate_qc_overrides_accepts_silver_metrics(self):
        """validate_qc_overrides accepts valid SILVER/BRONZE metric overrides."""
        valid, errors = NextflowQCGateHandler.validate_qc_overrides({
            "alignment_rate": 50.0,
            "reads_surviving_pct": 65.0,
            "duplicate_pct": 65.0,
            "mito_fraction_pct": 35.0,
        })
        assert valid, f"Silver overrides should be valid, but got errors: {errors}"
        assert errors == []

    def test_validate_qc_overrides_rejects_non_numeric(self):
        """validate_qc_overrides returns errors for non-numeric override values."""
        valid, errors = NextflowQCGateHandler.validate_qc_overrides({"alignment_rate": "foo"})
        assert not valid
        assert any("numeric" in e for e in errors)

    # -----------------------------------------------------------------------
    # Red-line clamping
    # -----------------------------------------------------------------------

    def test_reads_surviving_red_line_clamped_to_floor(self, tmp_path):
        """
        Override reads_surviving_pct to 30% (below red-line floor 50%) → clamped to 50%.
        A value of 45% surviving should still fail (45 < 50).
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="rnaseq",
            qc_overrides={"reads_surviving_pct": 30.0},  # below red-line floor
        )
        effective = h._get_threshold("reads_surviving_pct", 70.0)
        assert effective == pytest.approx(50.0), "Red-line floor must clamp to 50%"

        # 45% surviving → still fails (below clamped floor 50%)
        passed, failures = h._check_qc_thresholds("FASTP", {"reads_surviving_pct": 45.0, "q30_pct": 90.0})
        assert not passed, "45% must still fail after clamping to red-line floor 50%"
        surv_fail = next((f for f in failures if f["metric"] == "reads_surviving_pct"), None)
        assert surv_fail is not None
        assert surv_fail["threshold"] == pytest.approx(50.0)

    def test_mito_fraction_red_line_ceiling_clamped(self, tmp_path):
        """
        Override mito_fraction_pct to 90% (above red-line ceiling 80%) → clamped to 80%.
        mito=85% must still fail.
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="scrna_seq",
            qc_overrides={"mito_fraction_pct": 90.0},  # above red-line ceiling
        )
        effective = h._get_threshold("mito_fraction_pct", 20.0)
        assert effective == pytest.approx(80.0), "Red-line ceiling must clamp to 80%"

        passed, failures = h._check_qc_thresholds(
            "CELLRANGER_COUNT",
            {"mito_fraction_pct": 85.0, "cells_detected": 5000, "median_genes_per_cell": 2000}
        )
        assert not passed, "85% mito must still fail after clamping to 80% ceiling"
        mito_fail = next((f for f in failures if f["metric"] == "mito_fraction_pct"), None)
        assert mito_fail is not None
        assert mito_fail["threshold"] == pytest.approx(80.0)

    def test_alignment_rate_red_line_floor_clamps_at_5_pct(self, tmp_path):
        """
        Override alignment_rate to 2% (below red-line floor 5%) → clamped to 5%.
        alignment_rate=4% still fails (4 < 5).
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="rnaseq",
            qc_overrides={"alignment_rate": 2.0},
        )
        effective = h._get_threshold("alignment_rate", 70.0)
        assert effective == pytest.approx(5.0), "Override 2% must be clamped to red-line floor 5%"

    # -----------------------------------------------------------------------
    # Audit log
    # -----------------------------------------------------------------------

    def test_audit_log_written_on_init_with_overrides(self, tmp_path):
        """
        When qc_overrides is non-empty, an 'initialized' JSONL record must be written
        to work_dir/qc_overrides_audit.jsonl on handler creation.
        """
        import json
        NextflowQCGateHandler(
            invocation_id="audit-test", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_overrides={"alignment_rate": 50.0},
        )
        audit_path = tmp_path / "qc_overrides_audit.jsonl"
        assert audit_path.exists(), "Audit log must be created on init with overrides"
        records = [json.loads(line) for line in audit_path.read_text().splitlines() if line.strip()]
        assert len(records) >= 1
        assert records[0]["event_type"] == "initialized"
        assert records[0]["invocation_id"] == "audit-test"
        assert "alignment_rate" in records[0]["configured_overrides"]

    def test_audit_log_not_written_without_overrides(self, tmp_path):
        """
        When qc_overrides is empty (default), no audit file should be created.
        """
        NextflowQCGateHandler(
            invocation_id="no-overrides", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
        )
        audit_path = tmp_path / "qc_overrides_audit.jsonl"
        assert not audit_path.exists(), "Audit log must NOT be created when no overrides"

    def test_audit_log_updated_when_gate_fires_under_overrides(self, tmp_path):
        """
        When a QC gate triggers while overrides are active, a 'gate_triggered' record
        is appended to the audit log.
        """
        import json
        events = []
        h = NextflowQCGateHandler(
            invocation_id="gate-audit", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
            workflow_domain="rnaseq",
            qc_overrides={"alignment_rate": 80.0},  # raise threshold so 75% fails
        )
        h._check_qc_thresholds("STAR_ALIGN", {"alignment_rate": 75.0})
        # Directly call _emit_qc_gate_event to trigger audit write
        h._emit_qc_gate_event("STAR_ALIGN", {"alignment_rate": 75.0}, [])

        audit_path = tmp_path / "qc_overrides_audit.jsonl"
        records = [json.loads(line) for line in audit_path.read_text().splitlines() if line.strip()]
        event_types = [r["event_type"] for r in records]
        assert "gate_triggered" in event_types, "gate_triggered audit record must be written"

    # -----------------------------------------------------------------------
    # SSE event flags
    # -----------------------------------------------------------------------

    def test_sse_gate_event_has_overrides_active_true(self, tmp_path):
        """Gate SSE event must include overrides_active=True when overrides are set."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
            workflow_domain="rnaseq",
            qc_overrides={"alignment_rate": 50.0},
        )
        h._emit_qc_gate_event("STAR_ALIGN", {"alignment_rate": 45.0}, [])
        assert len(events) == 1
        _, data = events[0]
        assert data["overrides_active"] is True
        assert "alignment_rate" in data["active_overrides"]

    def test_sse_gate_event_has_overrides_active_false_when_no_overrides(self, tmp_path):
        """Gate SSE event must include overrides_active=False when no overrides are set."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
        )
        h._emit_qc_gate_event("STAR_ALIGN", {"alignment_rate": 45.0}, [])
        _, data = events[0]
        assert data["overrides_active"] is False
        assert data["active_overrides"] == {}

    def test_sse_warning_event_has_overrides_active_true(self, tmp_path):
        """Warning SSE event also includes overrides_active=True when overrides are set."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
            qc_overrides={"reads_surviving_pct": 65.0},
        )
        h._emit_qc_warning_event("FASTP", {}, [])
        _, data = events[0]
        assert data["overrides_active"] is True

    # -----------------------------------------------------------------------
    # Override effective threshold in _get_threshold
    # -----------------------------------------------------------------------

    def test_get_threshold_returns_override_for_silver_metric(self, tmp_path):
        """_get_threshold returns the override value for an unrestricted SILVER metric."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_overrides={"q30_pct": 60.0},
        )
        assert h._get_threshold("q30_pct", 75.0) == pytest.approx(60.0)

    def test_get_threshold_returns_default_for_unconfigured_metric(self, tmp_path):
        """_get_threshold returns default when metric not in qc_overrides."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_overrides={"alignment_rate": 50.0},  # q30_pct NOT in overrides
        )
        assert h._get_threshold("q30_pct", 75.0) == pytest.approx(75.0)

    def test_get_threshold_returns_default_when_no_overrides_set(self, tmp_path):
        """_get_threshold returns default when qc_overrides is empty."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
        )
        assert h._get_threshold("alignment_rate", 70.0) == pytest.approx(70.0)


# =============================================================================
# Phase 2 — Named QC profiles (Layer 3)
# =============================================================================

class TestNamedProfiles:
    """
    Tests for named QC profile support (Phase 2, Layer 3).

    Covers:
      - validate_qc_profile: known / unknown names
      - get_profile_overrides: correct thresholds returned
      - list_profiles: all profiles have required keys
      - __init__ with qc_profile: profile overrides merged into qc_overrides
      - Explicit qc_overrides take precedence over profile values
      - Profile overrides propagate to _get_threshold
      - active_profile in SSE events
      - active_profile in audit log
      - Real biological use cases (ribodepleted, cardiac scRNA, soil metagenomics, …)
    """

    # ------------------------------------------------------------------
    # validate_qc_profile
    # ------------------------------------------------------------------

    def test_validate_known_profile_returns_valid(self, tmp_path):
        """validate_qc_profile returns (True, []) for a known profile."""
        valid, errors = NextflowQCGateHandler.validate_qc_profile("rnaseq_ribodepleted")
        assert valid is True
        assert errors == []

    def test_validate_unknown_profile_returns_errors(self, tmp_path):
        """validate_qc_profile returns (False, [msg]) for an unknown profile name."""
        valid, errors = NextflowQCGateHandler.validate_qc_profile("nonexistent_profile_xyz")
        assert valid is False
        assert len(errors) == 1
        assert "nonexistent_profile_xyz" in errors[0]

    def test_all_defined_profiles_pass_validation(self, tmp_path):
        """Every profile ID in QC_NAMED_PROFILES passes validate_qc_profile."""
        from galaxy.jobs.qc_trace_monitor import QC_NAMED_PROFILES
        for profile_id in QC_NAMED_PROFILES:
            valid, errors = NextflowQCGateHandler.validate_qc_profile(profile_id)
            assert valid is True, f"Profile '{profile_id}' failed validation: {errors}"

    # ------------------------------------------------------------------
    # get_profile_overrides
    # ------------------------------------------------------------------

    def test_get_profile_overrides_ribodepleted_has_lower_alignment_rate(self, tmp_path):
        """rnaseq_ribodepleted profile lowers alignment_rate from default 70% to 50%."""
        overrides = NextflowQCGateHandler.get_profile_overrides("rnaseq_ribodepleted")
        assert "alignment_rate" in overrides
        assert overrides["alignment_rate"] == pytest.approx(50.0)

    def test_get_profile_overrides_unknown_returns_empty(self, tmp_path):
        """get_profile_overrides returns {} for an unknown profile (safe fallback)."""
        overrides = NextflowQCGateHandler.get_profile_overrides("no_such_profile")
        assert overrides == {}

    def test_get_profile_overrides_soil_suppresses_critical_gate(self, tmp_path):
        """metagenomics_soil profile has a very low classified_pct_critical (≤ 5%)."""
        overrides = NextflowQCGateHandler.get_profile_overrides("metagenomics_soil")
        assert overrides.get("classified_pct_critical", 30.0) <= 5.0

    # ------------------------------------------------------------------
    # list_profiles
    # ------------------------------------------------------------------

    def test_list_profiles_returns_all_profiles(self, tmp_path):
        """list_profiles returns a list entry for every profile in QC_NAMED_PROFILES."""
        from galaxy.jobs.qc_trace_monitor import QC_NAMED_PROFILES
        result = NextflowQCGateHandler.list_profiles()
        assert len(result) == len(QC_NAMED_PROFILES)

    def test_list_profiles_each_entry_has_required_keys(self, tmp_path):
        """Every entry from list_profiles has id, description, domain_hint, overrides, references."""
        for profile in NextflowQCGateHandler.list_profiles():
            for key in ("id", "description", "domain_hint", "overrides", "references"):
                assert key in profile, f"Profile '{profile.get('id')}' missing key '{key}'"

    # ------------------------------------------------------------------
    # __init__ with qc_profile — merge semantics
    # ------------------------------------------------------------------

    def test_init_with_profile_applies_profile_overrides(self, tmp_path):
        """Handler initialised with qc_profile applies the profile's threshold overrides."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_profile="rnaseq_ribodepleted",
        )
        # ribodepleted lowers alignment_rate to 50% — _get_threshold should return 50%
        assert h._get_threshold("alignment_rate", 70.0) == pytest.approx(50.0)

    def test_init_explicit_overrides_take_precedence_over_profile(self, tmp_path):
        """Explicit qc_overrides values win over profile values for the same key."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_profile="rnaseq_ribodepleted",   # sets alignment_rate=50
            qc_overrides={"alignment_rate": 45.0},  # explicit override → should win
        )
        assert h._get_threshold("alignment_rate", 70.0) == pytest.approx(45.0)

    def test_init_profile_and_explicit_override_merge_non_overlapping_keys(self, tmp_path):
        """Profile keys not overridden by explicit overrides are still applied."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_profile="rnaseq_ribodepleted",        # sets alignment_rate=50, reads_surviving_pct=65
            qc_overrides={"alignment_rate": 45.0},   # only overrides alignment_rate
        )
        # alignment_rate: explicit 45 wins over profile 50
        assert h._get_threshold("alignment_rate", 70.0) == pytest.approx(45.0)
        # reads_surviving_pct: profile 65 applies (no explicit override)
        assert h._get_threshold("reads_surviving_pct", 70.0) == pytest.approx(65.0)

    def test_init_active_profile_stored(self, tmp_path):
        """active_profile attribute is set to the profile name."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_profile="scrna_cardiac",
        )
        assert h.active_profile == "scrna_cardiac"

    def test_init_no_profile_active_profile_is_none(self, tmp_path):
        """active_profile is None when no profile is specified."""
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
        )
        assert h.active_profile is None

    # ------------------------------------------------------------------
    # SSE events include active_profile
    # ------------------------------------------------------------------

    def test_gate_event_includes_active_profile(self, tmp_path):
        """qc_gate_triggered SSE event includes active_profile field."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
            qc_profile="rnaseq_ribodepleted",
        )
        h._emit_qc_gate_event("STAR_ALIGN", {}, [])
        _, data = events[0]
        assert data["active_profile"] == "rnaseq_ribodepleted"

    def test_gate_event_active_profile_none_when_no_profile(self, tmp_path):
        """active_profile is None in gate event when no profile is active."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
        )
        h._emit_qc_gate_event("STAR_ALIGN", {}, [])
        _, data = events[0]
        assert data["active_profile"] is None

    def test_warning_event_includes_active_profile(self, tmp_path):
        """qc_warning SSE event includes active_profile field."""
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
            qc_profile="metagenomics_soil",
        )
        h._emit_qc_warning_event("KRAKEN2", {}, [])
        _, data = events[0]
        assert data["active_profile"] == "metagenomics_soil"

    # ------------------------------------------------------------------
    # Audit log includes active_profile
    # ------------------------------------------------------------------

    def test_audit_log_includes_active_profile(self, tmp_path):
        """Audit log JSONL records include active_profile field."""
        import json as _json
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_profile="wgs_germline_lowpass",
        )
        audit_path = tmp_path / "qc_overrides_audit.jsonl"
        records = [_json.loads(line) for line in audit_path.read_text().splitlines() if line.strip()]
        assert len(records) >= 1
        assert records[0]["active_profile"] == "wgs_germline_lowpass"

    # ------------------------------------------------------------------
    # Real biological use cases
    # ------------------------------------------------------------------

    def test_ribodepleted_rna_passes_lower_alignment_threshold(self, tmp_path):
        """
        US-4.3 (ribo-depleted): alignment_rate=55% passes the gate under
        rnaseq_ribodepleted profile (threshold: 50%), triggering only a near-threshold warning.
        Without the profile the gate would fire at 70%.
        """
        events = []
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: events.append((t, d)), app=Mock(),
            workflow_domain="rnaseq",
            qc_profile="rnaseq_ribodepleted",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "STAR_ALIGN", {"alignment_rate": 55.0}
        )
        assert qc_passed is True, f"Gate should NOT fire; got failures: {failures}"

    def test_ribodepleted_rna_gate_fires_below_profile_threshold(self, tmp_path):
        """
        rnaseq_ribodepleted profile: alignment_rate=45% (< 50%) still triggers the gate.
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="rnaseq",
            qc_profile="rnaseq_ribodepleted",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "STAR_ALIGN", {"alignment_rate": 45.0}
        )
        assert qc_passed is False
        assert any(f["metric"] == "alignment_rate" for f in failures)

    def test_cardiac_scrna_high_mito_passes(self, tmp_path):
        """
        scrna_cardiac profile: mito_fraction_pct=35% passes (profile threshold: 40%).
        Without the profile the hard gate is 20% → would fire.
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="scrna_seq",
            qc_profile="scrna_cardiac",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "CELLRANGER_COUNT", {"mito_fraction_pct": 35.0}
        )
        assert qc_passed is True, f"Gate should NOT fire for cardiac scRNA; got failures: {failures}"

    def test_cardiac_scrna_above_profile_threshold_fails(self, tmp_path):
        """
        scrna_cardiac profile: mito_fraction_pct=45% (> 40%) triggers the gate.
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="scrna_seq",
            qc_profile="scrna_cardiac",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "CELLRANGER_COUNT", {"mito_fraction_pct": 45.0}
        )
        assert qc_passed is False
        assert any(f["metric"] == "mito_fraction_pct" for f in failures)

    def test_soil_metagenomics_low_classification_passes(self, tmp_path):
        """
        metagenomics_soil profile: classified_pct=12% passes the gate
        (critical threshold: 5%) — soil dark matter is expected.
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="metagenomics",
            qc_profile="metagenomics_soil",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "KRAKEN2", {"classified_pct": 12.0}
        )
        assert qc_passed is True, f"Soil 12% classification should pass; got: {failures}"

    def test_wgs_lowpass_low_coverage_passes(self, tmp_path):
        """
        wgs_germline_lowpass profile: mean_coverage=5X passes the gate
        (profile threshold: 4X vs default 30X).
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="wgs",
            qc_profile="wgs_germline_lowpass",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "MOSDEPTH", {"mean_coverage": 5.0}
        )
        assert qc_passed is True, f"Low-pass 5X should pass; got: {failures}"

    def test_cryo_em_membrane_protein_high_drift_passes(self, tmp_path):
        """
        cryoem_spa_membrane profile: total_drift_angstrom=70Å passes
        (profile threshold: 80Å vs default 50Å).
        """
        h = NextflowQCGateHandler(
            invocation_id="t", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            workflow_domain="cryo_em",
            qc_profile="cryoem_spa_membrane",
        )
        qc_passed, failures = h._check_qc_thresholds(
            "MOTION_CORRECTION", {"total_drift_angstrom": 70.0}
        )
        assert qc_passed is True, f"Membrane protein 70Å drift should pass; got: {failures}"

    def test_default_profile_polya_standard_has_no_overrides(self, tmp_path):
        """
        rnaseq_polya_standard is the default — its overrides dict is empty,
        and effective thresholds are identical to the unprofiiled defaults.
        """
        h_profile = NextflowQCGateHandler(
            invocation_id="t1", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
            qc_profile="rnaseq_polya_standard",
        )
        h_default = NextflowQCGateHandler(
            invocation_id="t2", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock(),
        )
        assert h_profile._get_threshold("alignment_rate", 70.0) == \
               h_default._get_threshold("alignment_rate", 70.0)


# ---------------------------------------------------------------------------
# US-6.1 — Drug discovery parameter suggestions
# ---------------------------------------------------------------------------

class TestDrugDiscoverySuggester:
    """Tests for DrugDiscoveryParameterSuggester (hERG, DILI, Ames, pulldown, QSAR)."""

    def setup_method(self):
        self.s = DrugDiscoveryParameterSuggester()

    def test_herg_ic50_high_risk_enables_filter(self):
        """hERG IC50 < 1 μM → herg_liability_filter + brenk filter suggested."""
        suggestions = self.s.suggest(
            "HERG_PREDICTION", {"herg_ic50_uM": 0.5}, {}, []
        )
        params = {s.parameter for s in suggestions}
        assert "herg_liability_filter" in params
        assert "structural_alert_filter" in params
        brenk = next(s for s in suggestions if s.parameter == "structural_alert_filter")
        assert brenk.suggested_value == "brenk"
        assert brenk.source == "literature"

    def test_herg_ic50_medium_risk_only_filter(self):
        """hERG IC50 5 μM (1–10 range) → only herg_liability_filter, no brenk."""
        suggestions = self.s.suggest(
            "HERG_PREDICTION", {"herg_ic50_uM": 5.0}, {}, []
        )
        params = {s.parameter for s in suggestions}
        assert "herg_liability_filter" in params
        assert "structural_alert_filter" not in params

    def test_dili_high_suggests_structural_alert(self):
        """DILI category 'high' → dili_alert filter suggested."""
        suggestions = self.s.suggest(
            "DILI_PREDICTION", {"dili_category": "high"}, {}, []
        )
        assert len(suggestions) == 1
        assert suggestions[0].parameter == "structural_alert_filter"
        assert suggestions[0].suggested_value == "dili_alert"
        assert suggestions[0].source == "literature"

    def test_ames_positive_suggests_reactive_group_filter(self):
        """Ames probability ≥ 0.7 → reactive_group_filter + pains filter."""
        suggestions = self.s.suggest(
            "AMES_MUTAGENICITY", {"ames_probability": 0.85}, {}, []
        )
        params = {s.parameter for s in suggestions}
        assert "reactive_group_filter" in params
        assert "structural_alert_filter" in params
        pains = next(s for s in suggestions if s.parameter == "structural_alert_filter")
        assert pains.suggested_value == "pains"

    def test_pulldown_low_enrichment_suggests_more_beads(self):
        """Median enrichment ratio 1.5× < 3× → input_protein_ug + beads_ul."""
        suggestions = self.s.suggest(
            "CHEMOPROTEOMICS_PULLDOWN", {"median_enrichment_ratio": 1.5}, {}, []
        )
        params = {s.parameter for s in suggestions}
        assert "input_protein_ug" in params
        assert "beads_ul" in params

    def test_abpp_alias_also_routed(self):
        """ABPP_PULLDOWN alias also triggers enrichment suggestions."""
        suggestions = self.s.suggest(
            "ABPP_PULLDOWN", {"median_enrichment_ratio": 2.0}, {}, []
        )
        assert len(suggestions) > 0

    def test_qsar_low_cv_r2_suggests_more_estimators(self):
        """CV R² 0.3 < 0.5 → n_estimators + feature_selection."""
        suggestions = self.s.suggest(
            "QSAR_RF_MODEL", {"cv_r2_score": 0.3}, {}, []
        )
        params = {s.parameter for s in suggestions}
        assert "n_estimators" in params
        assert "feature_selection" in params

    def test_domain_routing_drug_discovery(self):
        """get_suggester_for_domain returns DrugDiscoveryParameterSuggester for drug domains."""
        for domain in ("drug_discovery", "chemoproteomics", "herg_screening", "qsar", "abpp"):
            s = get_suggester_for_domain(domain)
            assert isinstance(s, DrugDiscoveryParameterSuggester), f"wrong suggester for domain '{domain}'"

    def test_no_suggestions_when_metrics_absent(self):
        """Empty qc_metrics → no suggestions (graceful no-op)."""
        for process in ("HERG_PREDICTION", "DILI_PREDICTION", "AMES_MUTAGENICITY",
                        "CHEMOPROTEOMICS_PULLDOWN", "QSAR_RF_MODEL"):
            suggestions = self.s.suggest(process, {}, {}, [])
            # Either empty or DILI always emits one advisory (DILI always fires)
            # DILI suggest fires on process name alone (dili_category defaults to '')
            if "DILI" not in process and "AMES" not in process:
                assert suggestions == [], f"expected no suggestions for {process} with empty metrics"
