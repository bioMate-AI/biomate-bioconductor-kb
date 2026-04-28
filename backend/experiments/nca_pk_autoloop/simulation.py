"""Simulated NCA PK outputs for testing."""
from __future__ import annotations
from dataclasses import dataclass
from .params import NCAPKParams


@dataclass
class NCAReport:
    auc_extrap_pct: float
    subjects_with_no_terminal_slope: int
    t_half_mean: float
    auc_last_mean: float
    auc_inf_mean: float
    cmax_mean: float

    def to_dict(self) -> dict:
        return {"population_summary": {
            "auc_extrap_pct":                    self.auc_extrap_pct,
            "subjects_with_no_terminal_slope":   self.subjects_with_no_terminal_slope,
            "t_half_mean":                       self.t_half_mean,
            "auc_last_mean":                     self.auc_last_mean,
            "auc_inf_mean":                      self.auc_inf_mean,
            "cmax_mean":                         self.cmax_mean,
        }}


class SimulatedNCAJob:
    def __init__(self, scenario: list[dict]):
        self._scenario = scenario
        self._attempt = 0

    def run(self, params: NCAPKParams) -> NCAReport:
        idx = min(self._attempt, len(self._scenario) - 1)
        self._attempt += 1
        return NCAReport(**self._scenario[idx])


SCENARIO_HIGH_EXTRAP_THEN_PASS: list[dict] = [
    {"auc_extrap_pct": 35.0, "subjects_with_no_terminal_slope": 1, "t_half_mean": 8.0,
     "auc_last_mean": 650.0, "auc_inf_mean": 1000.0, "cmax_mean": 120.0},
    {"auc_extrap_pct": 12.0, "subjects_with_no_terminal_slope": 0, "t_half_mean": 8.5,
     "auc_last_mean": 875.0, "auc_inf_mean": 994.0, "cmax_mean": 118.0},
]

SCENARIO_NO_SLOPE_THEN_PASS: list[dict] = [
    {"auc_extrap_pct": 18.0, "subjects_with_no_terminal_slope": 4, "t_half_mean": 6.0,
     "auc_last_mean": 820.0, "auc_inf_mean": 1000.0, "cmax_mean": 200.0},
    {"auc_extrap_pct": 14.0, "subjects_with_no_terminal_slope": 1, "t_half_mean": 6.2,
     "auc_last_mean": 855.0, "auc_inf_mean": 994.0, "cmax_mean": 198.0},
]

SCENARIO_CLEAN_PASS: list[dict] = [
    {"auc_extrap_pct": 8.5, "subjects_with_no_terminal_slope": 0, "t_half_mean": 5.0,
     "auc_last_mean": 910.0, "auc_inf_mean": 994.0, "cmax_mean": 150.0},
]

SCENARIO_PERSISTENT_FAIL: list[dict] = [
    {"auc_extrap_pct": 55.0, "subjects_with_no_terminal_slope": 5, "t_half_mean": 2.0,
     "auc_last_mean": 450.0, "auc_inf_mean": 1000.0, "cmax_mean": 200.0},
]


class ScenarioRunner:
    def __init__(self, scenario: list[dict]):
        self._job = SimulatedNCAJob(scenario)

    def phase_runner(self, phase: str, params: NCAPKParams) -> dict:
        return self._job.run(params).to_dict()
