"""
Calibration logger for the hERG QSAR auto-loop tuner.

Writes one JSONL record per hERG remediation:

  {
    "observed_ic50_uM":    float,   # hERG IC50 that triggered the gate
    "logp_max_before":     float,   # logP_max at time of gate failure
    "logp_max_suggested":  float,   # tuner's suggested new logP_max
    "target_ic50_uM":      float,   # threshold × HERG_SAFETY_MARGIN
    "gap_ratio":           float,   # target / observed
    "confidence":          str,     # "confident" | "heuristic"
    "profile":             str,     # QC profile name
    "run_id":              str,     # optional run identifier
    "ts":                  str,     # ISO-8601 UTC timestamp (injected by caller)
  }

These records accumulate across runs and feed future recalibration of:
  1. HERG_QSAR_LOGP_COEFF / HERG_QSAR_INTERCEPT — analytical path
  2. HERG_BASE_STEP scaling — heuristic path

Usage (in orchestrators or test harnesses that pass a real timestamp):

  from experiments.admet_autoloop.calibration_logger import CalibrationLogger

  logger = CalibrationLogger("/data/admet_calibration.jsonl")
  tuner  = ADMETParamTuner(calibration_logger=logger)

  # run_id and ts must be supplied at call time (not inside the logger) so
  # the logger stays deterministic and testable.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Optional


class CalibrationLogger:
    """
    Append-only JSONL writer for hERG tuner calibration records.

    Thread-safety: each `log()` call opens, appends one line, and closes the
    file.  This is safe for single-process use (gunicorn single-worker or CLI).
    For multi-worker use, swap `open(…, "a")` for `fcntl.flock` if needed.

    Parameters
    ----------
    path : str | Path
        Path to the JSONL file.  Parent directories are created on first write.
    """

    def __init__(self, path: "str | Path"):
        self._path = Path(path)

    def log(
        self,
        *,
        observed_ic50_uM: float,
        logp_max_before:  float,
        logp_max_suggested: float,
        target_ic50_uM:   float,
        gap_ratio:        float,
        confidence:       str,
        profile:          str = "admet_standard",
        run_id:           str = "",
        ts:               str = "",
    ) -> None:
        """Append one calibration record to the log file."""
        record = {
            "observed_ic50_uM":   round(observed_ic50_uM,   4),
            "logp_max_before":    round(logp_max_before,    2),
            "logp_max_suggested": round(logp_max_suggested, 2),
            "target_ic50_uM":     round(target_ic50_uM,     4),
            "gap_ratio":          round(gap_ratio,           4),
            "confidence":         confidence,
            "profile":            profile,
            "run_id":             run_id,
            "ts":                 ts,
        }
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with open(self._path, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")

    def read_all(self) -> list[dict]:
        """Return all records as a list of dicts (for tests and analysis)."""
        if not self._path.exists():
            return []
        records = []
        with open(self._path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    records.append(json.loads(line))
        return records

    def record_count(self) -> int:
        return len(self.read_all())
