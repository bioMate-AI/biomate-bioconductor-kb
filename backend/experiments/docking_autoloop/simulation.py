"""Simulated docking outputs for testing."""
from __future__ import annotations
from dataclasses import dataclass
from .params import DockingParams


@dataclass
class DockingReport:
    success: bool
    best_score_kcal_mol: float
    n_ligands_docked: int
    mean_score: float

    def to_dict(self) -> dict:
        return {
            "success": self.success,
            "best_score_kcal_mol": self.best_score_kcal_mol,
            "n_ligands_docked": self.n_ligands_docked,
            "mean_score": self.mean_score,
        }


class SimulatedDockingJob:
    def __init__(self, scenario: list[dict]):
        self._scenario = scenario
        self._attempt = 0

    def run(self, params: DockingParams) -> DockingReport:
        idx = min(self._attempt, len(self._scenario) - 1)
        entry = self._scenario[idx]
        self._attempt += 1
        return DockingReport(**entry)


SCENARIO_WEAK_THEN_HIT: list[dict] = [
    {"success": True,  "best_score_kcal_mol": -5.2, "n_ligands_docked": 10, "mean_score": -4.1},
    {"success": True,  "best_score_kcal_mol": -7.8, "n_ligands_docked": 10, "mean_score": -6.5},
]

SCENARIO_NO_POSES_THEN_HIT: list[dict] = [
    {"success": False, "best_score_kcal_mol":  0.0, "n_ligands_docked":  0, "mean_score":  0.0},
    {"success": True,  "best_score_kcal_mol": -8.1, "n_ligands_docked":  8, "mean_score": -6.8},
]

SCENARIO_STRONG_HIT: list[dict] = [
    {"success": True,  "best_score_kcal_mol": -9.4, "n_ligands_docked": 12, "mean_score": -7.2},
]

SCENARIO_PERSISTENT_FAIL: list[dict] = [
    {"success": False, "best_score_kcal_mol":  0.0, "n_ligands_docked":  0, "mean_score":  0.0},
]

SCENARIO_CLEAN_PASS: list[dict] = [
    {"success": True,  "best_score_kcal_mol": -8.5, "n_ligands_docked": 15, "mean_score": -6.9},
]


class ScenarioRunner:
    def __init__(self, scenario: list[dict]):
        self._job = SimulatedDockingJob(scenario)

    def phase_runner(self, phase: str, params: DockingParams) -> dict:
        return self._job.run(params).to_dict()
