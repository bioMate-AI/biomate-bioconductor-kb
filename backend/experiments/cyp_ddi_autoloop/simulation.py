"""
Simulated CYP DDI panel outputs for testing.

Mirrors cyp_panel_summary.json schema from cyp_ddi_panel/main.nf.
"""
from __future__ import annotations
from dataclasses import dataclass
from .params import CYPDDIParams


@dataclass
class CYPPanelReport:
    n_clinical: int
    n_investigate: int
    n_tdi: int
    overall_recommendation: str
    highest_risk_isoform: str = "CYP3A4"
    highest_risk_ic50_uM: float = 5.0

    def to_dict(self) -> dict:
        return {
            "summary": {
                "n_clinical":             self.n_clinical,
                "n_investigate":          self.n_investigate,
                "n_tdi":                  self.n_tdi,
                "overall_recommendation": self.overall_recommendation,
                "highest_risk_isoform":   self.highest_risk_isoform,
            },
        }


class SimulatedCYPJob:
    def __init__(self, scenario: list[dict]):
        self._scenario = scenario
        self._attempt = 0

    def run(self, params: CYPDDIParams) -> CYPPanelReport:
        idx = min(self._attempt, len(self._scenario) - 1)
        entry = self._scenario[idx]
        self._attempt += 1
        return CYPPanelReport(**entry)


# ── Pre-canned scenarios ──────────────────────────────────────────────────────

SCENARIO_CLINICAL_THEN_PASS: list[dict] = [
    {"n_clinical": 1, "n_investigate": 2, "n_tdi": 1,
     "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"},
    {"n_clinical": 0, "n_investigate": 1, "n_tdi": 0,
     "overall_recommendation": "INVESTIGATE"},
    {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
     "overall_recommendation": "NOT_EXPECTED"},
]

SCENARIO_INVESTIGATE_THEN_PASS: list[dict] = [
    {"n_clinical": 0, "n_investigate": 4, "n_tdi": 0,
     "overall_recommendation": "INVESTIGATE"},
    {"n_clinical": 0, "n_investigate": 2, "n_tdi": 0,
     "overall_recommendation": "INVESTIGATE"},
    {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
     "overall_recommendation": "NOT_EXPECTED"},
]

SCENARIO_CLEAN_PASS: list[dict] = [
    {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
     "overall_recommendation": "NOT_EXPECTED"},
]

SCENARIO_PERSISTENT_FAIL: list[dict] = [
    {"n_clinical": 3, "n_investigate": 4, "n_tdi": 2,
     "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"},
]


class ScenarioRunner:
    def __init__(self, scenario: list[dict]):
        self._job = SimulatedCYPJob(scenario)
        self.run_log: list[dict] = []

    def phase_runner(self, phase: str, params: CYPDDIParams) -> dict:
        report = self._job.run(params)
        metrics = report.to_dict()
        self.run_log.append({"phase": phase, "metrics": metrics})
        return metrics
