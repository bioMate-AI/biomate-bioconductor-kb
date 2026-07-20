"""
Calibration logger tests.

Verifies that the CalibrationLogger:
  1. Writes a record on each hERG gate remediation
  2. Does NOT write a record for non-hERG gates (DILI, Ames)
  3. Writes the correct fields (observed_ic50, logp_max_before, logp_max_suggested, etc.)
  4. Does nothing (no crash) when no logger is passed to the tuner
  5. Accumulates records across multiple remediation calls
  6. `read_all()` returns records in insertion order
"""
import json
import tempfile
from pathlib import Path

import pytest

from experiments.admet_autoloop.calibration_logger import CalibrationLogger
from experiments.admet_autoloop.param_tuner import ADMETParamTuner
from experiments.admet_autoloop.params import ADMETParams
from experiments.admet_autoloop.qc_evaluator import ADMETQCEvaluator


def _evaluator():
    return ADMETQCEvaluator("admet_standard")


def _params(**kwargs) -> ADMETParams:
    defaults = dict(
        logp_max=5.0,
        mw_max_da=500.0,
        ames_strict=False,
        num_candidates=50,
        tpsa_max_A2=140.0,
    )
    defaults.update(kwargs)
    return ADMETParams(**defaults)


# ── Logger unit tests ─────────────────────────────────────────────────────────

def test_logger_writes_record(tmp_path):
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    logger.log(
        observed_ic50_uM=3.5,
        logp_max_before=5.0,
        logp_max_suggested=4.0,
        target_ic50_uM=15.0,
        gap_ratio=4.3,
        confidence="heuristic",
        profile="admet_standard",
        run_id="test-001",
        ts="2026-07-17T10:00:00Z",
    )
    assert log_file.exists()
    records = logger.read_all()
    assert len(records) == 1
    r = records[0]
    assert r["observed_ic50_uM"] == 3.5
    assert r["logp_max_before"] == 5.0
    assert r["logp_max_suggested"] == 4.0
    assert r["confidence"] == "heuristic"
    assert r["profile"] == "admet_standard"
    assert r["run_id"] == "test-001"


def test_logger_appends_multiple(tmp_path):
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    for i in range(3):
        logger.log(
            observed_ic50_uM=float(i + 1),
            logp_max_before=5.0,
            logp_max_suggested=5.0 - i * 0.5,
            target_ic50_uM=15.0,
            gap_ratio=2.0,
            confidence="heuristic",
        )
    records = logger.read_all()
    assert len(records) == 3
    assert [r["observed_ic50_uM"] for r in records] == [1.0, 2.0, 3.0]


def test_logger_read_all_empty(tmp_path):
    log_file = tmp_path / "nonexistent.jsonl"
    logger = CalibrationLogger(log_file)
    assert logger.read_all() == []


def test_logger_record_count(tmp_path):
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    assert logger.record_count() == 0
    logger.log(
        observed_ic50_uM=3.5,
        logp_max_before=5.0,
        logp_max_suggested=4.2,
        target_ic50_uM=15.0,
        gap_ratio=4.3,
        confidence="heuristic",
    )
    assert logger.record_count() == 1


def test_logger_creates_parent_dirs(tmp_path):
    log_file = tmp_path / "nested" / "deep" / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    logger.log(
        observed_ic50_uM=5.0,
        logp_max_before=5.0,
        logp_max_suggested=4.5,
        target_ic50_uM=15.0,
        gap_ratio=3.0,
        confidence="heuristic",
    )
    assert log_file.exists()


def test_logger_each_line_valid_json(tmp_path):
    """Each line in the JSONL file must be independently parseable JSON."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    for i in range(5):
        logger.log(
            observed_ic50_uM=float(i),
            logp_max_before=5.0,
            logp_max_suggested=4.0,
            target_ic50_uM=15.0,
            gap_ratio=3.0,
            confidence="heuristic",
        )
    with open(log_file) as f:
        lines = [l.strip() for l in f if l.strip()]
    assert len(lines) == 5
    for line in lines:
        obj = json.loads(line)
        assert "observed_ic50_uM" in obj


# ── Tuner integration tests ───────────────────────────────────────────────────

def test_tuner_writes_on_herg_remediation(tmp_path):
    """hERG HALT → calibration logger receives one record."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    tuner  = ADMETParamTuner(calibration_logger=logger)
    ev = _evaluator()
    # hERG IC50 = 3.5 µM → below 10 µM threshold → HALT
    qc = ev.evaluate_phase_3({"herg_ic50_uM": 3.5})
    tuner.remediate(qc, _params())
    records = logger.read_all()
    assert len(records) == 1
    r = records[0]
    assert r["observed_ic50_uM"] == pytest.approx(3.5, abs=0.01)
    assert r["logp_max_before"] == pytest.approx(5.0)
    assert r["logp_max_suggested"] < 5.0, "Suggested logP should be lower than before"
    assert r["confidence"] == "heuristic"


def test_tuner_no_record_on_pass(tmp_path):
    """No calibration record when hERG gate passes."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    tuner = ADMETParamTuner(calibration_logger=logger)
    ev = _evaluator()
    qc = ev.evaluate_phase_3({"herg_ic50_uM": 45.0})
    tuner.remediate(qc, _params())
    assert logger.record_count() == 0


def test_tuner_no_record_for_dili(tmp_path):
    """DILI HALT does not write to calibration log (only hERG is calibration-relevant)."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    tuner = ADMETParamTuner(calibration_logger=logger)
    ev = _evaluator()
    qc = ev.evaluate_phase_4({"dili_probability": 0.8, "dili_risk": "high",
                               "ames_positive": False, "ames_probability": 0.1})
    tuner.remediate(qc, _params())
    assert logger.record_count() == 0


def test_tuner_no_logger_no_crash():
    """Tuner without calibration_logger completes normally — no AttributeError."""
    tuner = ADMETParamTuner()
    ev = _evaluator()
    qc = ev.evaluate_phase_3({"herg_ic50_uM": 3.5})
    new_params, remediations = tuner.remediate(qc, _params())
    assert new_params.logp_max < 5.0


def test_tuner_accumulates_across_multiple_runs(tmp_path):
    """Multiple hERG remediations produce multiple calibration records."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    tuner = ADMETParamTuner(calibration_logger=logger)
    ev = _evaluator()
    for ic50 in [2.0, 4.0, 7.5]:
        qc = ev.evaluate_phase_3({"herg_ic50_uM": ic50})
        tuner.remediate(qc, _params())
    records = logger.read_all()
    assert len(records) == 3
    observed = [r["observed_ic50_uM"] for r in records]
    assert observed == pytest.approx([2.0, 4.0, 7.5], abs=0.01)


def test_calibration_record_fields_complete(tmp_path):
    """All required calibration fields are present in every record."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    tuner = ADMETParamTuner(calibration_logger=logger, profile="admet_cns")
    ev = ADMETQCEvaluator("admet_cns")
    qc = ev.evaluate_phase_3({"herg_ic50_uM": 3.5})
    tuner.remediate(qc, _params())
    r = logger.read_all()[0]
    required = {"observed_ic50_uM", "logp_max_before", "logp_max_suggested",
                "target_ic50_uM", "gap_ratio", "confidence", "profile"}
    assert required.issubset(r.keys())
    assert r["profile"] == "admet_cns"


def test_calibration_gap_ratio_correct(tmp_path):
    """gap_ratio = target_ic50 / observed_ic50 = (10 * 1.5) / 3.5 ≈ 4.29."""
    log_file = tmp_path / "calibration.jsonl"
    logger = CalibrationLogger(log_file)
    tuner = ADMETParamTuner(calibration_logger=logger)
    ev = _evaluator()
    qc = ev.evaluate_phase_3({"herg_ic50_uM": 3.5})
    tuner.remediate(qc, _params())
    r = logger.read_all()[0]
    expected_gap = (10.0 * 1.5) / 3.5  # threshold=10, margin=1.5, observed=3.5
    assert r["gap_ratio"] == pytest.approx(expected_gap, rel=0.01)
    assert r["target_ic50_uM"] == pytest.approx(15.0, abs=0.01)
