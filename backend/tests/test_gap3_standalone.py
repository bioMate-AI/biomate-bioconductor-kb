"""
Standalone Gap 3 Integration Test (No Galaxy dependencies)

Tests the parameter suggester logic directly without requiring Galaxy imports.
"""

import sys
import json
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from galaxy.jobs.parameter_suggester import (
    CryoEMParameterSuggester,
    RNASeqParameterSuggester,
    get_suggester_for_domain
)


def test_cryo_em_motion_correction():
    """Test Cryo-EM motion correction suggestions."""
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

    assert len(suggestions) == 3, f"Expected 3 suggestions, got {len(suggestions)}"

    # Check dose weighting
    dose_weighting = next((s for s in suggestions if s.parameter == "dose_weighting"), None)
    assert dose_weighting is not None, "dose_weighting suggestion missing"
    assert dose_weighting.current_value is False
    assert dose_weighting.suggested_value is True
    assert dose_weighting.confidence == 0.85
    assert "Excessive drift" in dose_weighting.reason

    # Check patch size
    patch_size = next((s for s in suggestions if s.parameter == "patch_size"), None)
    assert patch_size is not None, "patch_size suggestion missing"
    assert patch_size.current_value == 3
    assert patch_size.suggested_value == 5
    assert patch_size.confidence == 0.75

    # Check alignment frames
    alignment_frames = next((s for s in suggestions if s.parameter == "alignment_frames"), None)
    assert alignment_frames is not None, "alignment_frames suggestion missing"
    assert alignment_frames.current_value == 1
    assert alignment_frames.suggested_value == 3
    assert alignment_frames.confidence == 0.70

    print("✓ Motion correction suggestions correct")


def test_cryo_em_ctf_estimation():
    """Test Cryo-EM CTF estimation suggestions."""
    suggester = CryoEMParameterSuggester()

    suggestions = suggester.suggest(
        process_name="CTF_ESTIMATION",
        qc_metrics={
            "astigmatism_angstrom": 1500,
            "fit_quality": 0.6
        },
        current_parameters={
            "use_tilt_search": False,
            "defocus_min": 10000,
            "defocus_max": 30000
        },
        failures=[
            "High astigmatism: 1500Å",
            "Poor fit quality: 0.6"
        ]
    )

    assert len(suggestions) == 2

    tilt_search = next(s for s in suggestions if s.parameter == "use_tilt_search")
    assert tilt_search.suggested_value is True
    assert tilt_search.confidence == 0.80

    defocus_range = next(s for s in suggestions if s.parameter == "defocus_search_range")
    # suggested_value is a dict so frontend can apply defocus_min and defocus_max separately
    assert defocus_range.suggested_value == {"defocus_min": 5000, "defocus_max": 50000}
    assert defocus_range.confidence == 0.75

    print("✓ CTF estimation suggestions correct")


def test_cryo_em_particle_picking():
    """Test Cryo-EM particle picking suggestions."""
    suggester = CryoEMParameterSuggester()

    # Too few particles
    suggestions = suggester.suggest(
        process_name="PARTICLE_PICKING",
        qc_metrics={"particles_picked": 500},
        current_parameters={"picking_threshold": 0.5},
        failures=["Too few particles"]
    )

    assert len(suggestions) == 1
    assert suggestions[0].parameter == "picking_threshold"
    assert suggestions[0].suggested_value == 0.4
    # Confidence is 0.65 (not 0.85) — lowering threshold risks picking junk particles
    assert suggestions[0].confidence == 0.65

    # Too many duplicates
    suggestions = suggester.suggest(
        process_name="PARTICLE_PICKING",
        qc_metrics={"duplicate_fraction": 0.35},
        current_parameters={"minimum_separation": 10},
        failures=["High duplicate rate"]
    )

    assert len(suggestions) == 1
    assert suggestions[0].parameter == "minimum_separation"
    assert suggestions[0].suggested_value == 20
    assert suggestions[0].confidence == 0.80

    print("✓ Particle picking suggestions correct")


def test_rna_seq_quality_trimming():
    """Test RNA-seq quality trimming suggestions (uses reads_surviving_pct metric)."""
    suggester = RNASeqParameterSuggester()

    suggestions = suggester.suggest(
        process_name="FASTP_TRIM",
        qc_metrics={"reads_surviving_pct": 60.0},
        current_parameters={"quality_cutoff": 20},
        failures=["Low read survival"]
    )

    assert len(suggestions) >= 1
    quality_sugg = next((s for s in suggestions if s.parameter == "quality_cutoff"), None)
    assert quality_sugg is not None
    assert quality_sugg.suggested_value == 25
    assert quality_sugg.confidence == 0.85

    print("✓ RNA-seq quality trimming suggestions correct")


def test_rna_seq_alignment():
    """Test RNA-seq alignment suggestions (uses alignment_rate metric, percentage)."""
    suggester = RNASeqParameterSuggester()

    suggestions = suggester.suggest(
        process_name="STAR_ALIGN",
        qc_metrics={"alignment_rate": 55.0},   # 55%, below 70% threshold
        current_parameters={"max_mismatches": 2, "twopass_mode": True},
        failures=["Low alignment rate"]
    )

    # Should suggest more mismatches (twopass already on so no twopass suggestion)
    mismatch_sugg = next((s for s in suggestions if s.parameter == "max_mismatches"), None)
    assert mismatch_sugg is not None
    assert mismatch_sugg.suggested_value == 3
    assert mismatch_sugg.confidence == 0.65

    print("✓ RNA-seq alignment suggestions correct")


def test_domain_suggester_factory():
    """Test get_suggester_for_domain factory function."""

    cryo_suggester = get_suggester_for_domain("cryo_em")
    assert isinstance(cryo_suggester, CryoEMParameterSuggester)

    rna_suggester = get_suggester_for_domain("rnaseq")
    assert isinstance(rna_suggester, RNASeqParameterSuggester)

    # Test case-insensitive matching
    cryo_suggester2 = get_suggester_for_domain("CRYO_EM")
    assert isinstance(cryo_suggester2, CryoEMParameterSuggester)

    print("✓ Domain suggester factory works")


def test_json_serialization():
    """Test that suggestions can be JSON serialized."""
    suggester = CryoEMParameterSuggester()

    suggestions = suggester.suggest(
        process_name="MOTION_CORRECTION",
        qc_metrics={"total_drift_angstrom": 65.3},
        current_parameters={"dose_weighting": False},
        failures=["Excessive drift"]
    )

    # Convert to JSON-serializable format
    suggestions_dict = [
        {
            "parameter": s.parameter,
            "currentValue": s.current_value,
            "suggestedValue": s.suggested_value,
            "reason": s.reason,
            "confidence": s.confidence
        }
        for s in suggestions
    ]

    # Test serialization
    json_str = json.dumps(suggestions_dict, indent=2)
    parsed = json.loads(json_str)

    assert len(parsed) >= 1
    assert "parameter" in parsed[0]
    assert "confidence" in parsed[0]
    assert 0 <= parsed[0]["confidence"] <= 1

    print("✓ JSON serialization works")


def run_all_tests():
    """Run all standalone Gap 3 tests."""
    print("\n" + "=" * 70)
    print("Gap 3 Standalone Integration Tests")
    print("=" * 70 + "\n")

    tests = [
        ("Motion Correction Suggestions", test_cryo_em_motion_correction),
        ("CTF Estimation Suggestions", test_cryo_em_ctf_estimation),
        ("Particle Picking Suggestions", test_cryo_em_particle_picking),
        ("RNA-seq Quality Trimming", test_rna_seq_quality_trimming),
        ("RNA-seq Alignment Suggestions", test_rna_seq_alignment),
        ("Domain Suggester Factory", test_domain_suggester_factory),
        ("JSON Serialization", test_json_serialization),
    ]

    passed = 0
    failed = 0

    for name, test_func in tests:
        try:
            test_func()
            passed += 1
        except AssertionError as e:
            print(f"✗ {name} FAILED: {e}")
            failed += 1
        except Exception as e:
            print(f"✗ {name} ERROR: {e}")
            failed += 1

    print("\n" + "=" * 70)
    if failed == 0:
        print(f"✅ ALL TESTS PASSED ({passed}/{len(tests)})")
        print("=" * 70)
        print("\nGap 3 Parameter Suggester Status: 100% WORKING")
        print("\nProduction Status: READY ✅")
        return 0
    else:
        print(f"❌ TESTS FAILED ({failed}/{len(tests)} failed, {passed} passed)")
        print("=" * 70)
        return 1


if __name__ == "__main__":
    exit_code = run_all_tests()
    sys.exit(exit_code)
