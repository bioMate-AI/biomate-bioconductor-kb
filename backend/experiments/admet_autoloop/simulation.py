"""
Simulated ADMET pipeline for testing the auto-loop without a live Nextflow run.

Produces synthetic toxicity_report.json outputs that mirror the schema from
pharmacology/ADMET_pred/main.nf.  ScenarioRunner controls whether each attempt
passes or fails specific gates, allowing the orchestrator's retry logic to be
exercised in unit tests.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from typing import Callable

from .params import ADMETParams


# ── Simulated toxicity_report.json ────────────────────────────────────────────

@dataclass
class ToxicityReport:
    """
    Mirrors toxicity_report.json output from ADMET_pred/main.nf.

    Fields:
      herg_ic50_uM:       worst-case hERG IC50 across all compounds (µM)
      dili_risk:          "high" | "medium" | "low"
      dili_probability:   0-1 (worst compound, Lammert 2010)
      ames_positive:      True if any compound triggers Kazius structural alerts
      ames_probability:   0-1 (worst compound)
      logP:               worst-case logP
      mw:                 worst-case molecular weight (Da)
    """
    herg_ic50_uM: float
    dili_risk: str
    dili_probability: float
    ames_positive: bool
    ames_probability: float
    logP: float
    mw: float

    def to_dict(self) -> dict:
        return {
            "herg_ic50_uM":     self.herg_ic50_uM,
            "dili_risk":        self.dili_risk,
            "dili_probability": self.dili_probability,
            "ames_positive":    self.ames_positive,
            "ames_probability": self.ames_probability,
            "logP":             self.logP,
            "mw":               self.mw,
        }


# ── Pre-canned scenario sequences ────────────────────────────────────────────

class SimulatedADMETJob:
    """
    Simulates one ADMET screening attempt given the current params.

    Each call to `run()` produces a ToxicityReport whose values are determined
    by the scenario sequence.  The scenario is a list of ToxicityReport kwargs
    dicts; after exhaustion it repeats the last entry (stable pass scenario).
    """

    def __init__(self, scenario: list[dict]):
        if not scenario:
            raise ValueError("scenario must have at least one entry")
        self._scenario = scenario
        self._attempt = 0

    def run(self, params: ADMETParams) -> ToxicityReport:
        """Return the next synthetic ToxicityReport for the current attempt."""
        idx = min(self._attempt, len(self._scenario) - 1)
        entry = self._scenario[idx]
        self._attempt += 1
        return ToxicityReport(**entry)


# ── Named scenarios matching test cases ───────────────────────────────────────

# Scenario 1: hERG HALT on attempt 0, passes after param tighten on attempt 1
SCENARIO_HERG_THEN_PASS: list[dict] = [
    {
        "herg_ic50_uM": 3.5,    # < 10 µM → HALT
        "dili_risk": "low",
        "dili_probability": 0.15,
        "ames_positive": False,
        "ames_probability": 0.10,
        "logP": 3.2,
        "mw": 380.0,
    },
    {
        "herg_ic50_uM": 18.0,   # > 10 µM → PASS
        "dili_risk": "low",
        "dili_probability": 0.12,
        "ames_positive": False,
        "ames_probability": 0.08,
        "logP": 2.9,
        "mw": 360.0,
    },
]

# Scenario 2: DILI HALT on attempt 0, passes on attempt 1
SCENARIO_DILI_THEN_PASS: list[dict] = [
    {
        "herg_ic50_uM": 25.0,
        "dili_risk": "high",    # HALT (> medium)
        "dili_probability": 0.78,
        "ames_positive": False,
        "ames_probability": 0.20,
        "logP": 4.8,
        "mw": 450.0,
    },
    {
        "herg_ic50_uM": 22.0,
        "dili_risk": "medium",  # PASS (≤ medium)
        "dili_probability": 0.42,
        "ames_positive": False,
        "ames_probability": 0.15,
        "logP": 3.5,
        "mw": 380.0,
    },
]

# Scenario 3: Ames HALT on attempt 0, passes on attempt 1
SCENARIO_AMES_THEN_PASS: list[dict] = [
    {
        "herg_ic50_uM": 30.0,
        "dili_risk": "low",
        "dili_probability": 0.22,
        "ames_positive": True,  # HALT
        "ames_probability": 0.72,
        "logP": 2.8,
        "mw": 310.0,
    },
    {
        "herg_ic50_uM": 28.0,
        "dili_risk": "low",
        "dili_probability": 0.18,
        "ames_positive": False, # PASS
        "ames_probability": 0.28,
        "logP": 2.5,
        "mw": 300.0,
    },
]

# Scenario 4: Multi-gate failure — hERG + DILI, resolves across 3 attempts
SCENARIO_MULTI_GATE: list[dict] = [
    {
        "herg_ic50_uM": 2.1,    # HALT
        "dili_risk": "high",    # HALT
        "dili_probability": 0.82,
        "ames_positive": False,
        "ames_probability": 0.31,
        "logP": 5.5,
        "mw": 510.0,
    },
    {
        "herg_ic50_uM": 7.5,    # still HALT (< 10)
        "dili_risk": "medium",  # PASS now
        "dili_probability": 0.44,
        "ames_positive": False,
        "ames_probability": 0.22,
        "logP": 4.2,
        "mw": 430.0,
    },
    {
        "herg_ic50_uM": 14.0,   # PASS
        "dili_risk": "low",
        "dili_probability": 0.28,
        "ames_positive": False,
        "ames_probability": 0.15,
        "logP": 3.1,
        "mw": 380.0,
    },
]

# Scenario 5: Persistent failure — never passes (escalation path)
SCENARIO_PERSISTENT_FAIL: list[dict] = [
    {
        "herg_ic50_uM": 0.8,    # HALT — very potent hERG inhibitor
        "dili_risk": "high",
        "dili_probability": 0.91,
        "ames_positive": True,
        "ames_probability": 0.88,
        "logP": 6.2,
        "mw": 620.0,
    },
]

# Scenario 6: Clean pass on first attempt (baseline / regression test)
SCENARIO_CLEAN_PASS: list[dict] = [
    {
        "herg_ic50_uM": 45.0,
        "dili_risk": "low",
        "dili_probability": 0.12,
        "ames_positive": False,
        "ames_probability": 0.08,
        "logP": 2.4,
        "mw": 320.0,
    },
]


# ── ScenarioRunner (mirrors cryo_em_autoloop.simulation.ScenarioRunner) ──────

class ScenarioRunner:
    """
    Drives the orchestrator by providing a phase-runner function that
    returns a ToxicityReport for each retry attempt.

    Usage in tests::

        runner = ScenarioRunner(SCENARIO_HERG_THEN_PASS)
        result = await loop.run(runner.phase_runner)
    """

    def __init__(self, scenario: list[dict]):
        self._job = SimulatedADMETJob(scenario)
        self.run_log: list[dict] = []

    def phase_runner(self, phase: str, params: ADMETParams) -> dict:
        """
        Simulate running `phase` with the given params and return metrics dict.

        In production this would invoke the Nextflow ADMET_pred process and
        parse the resulting toxicity_report.json.  Here it returns synthetic
        data from the pre-canned scenario sequence.
        """
        report = self._job.run(params)
        metrics = report.to_dict()
        self.run_log.append({"phase": phase, "params_snapshot": params.to_dict(), "metrics": metrics})
        return metrics
