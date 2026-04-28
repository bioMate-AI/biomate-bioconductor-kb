"""
Docking QC evaluator.

Metrics from docking_autodock_vina_results.json:
  {
    "success": bool,
    "best_score_kcal_mol": float,     # most negative = strongest binder
    "n_ligands_docked": int,
    "results": [{"ligand": str, "best_affinity_kcal_mol": float}, ...]
  }

Or from docking_summary.json (Glide):
  {
    "n_ligands_input": int,
    "n_poses_generated": int,
    "top_glidescore": float,
    "mean_glidescore": float,
    "interpretation": str
  }
"""
from __future__ import annotations
import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class QCAction(str, Enum):
    PASS = "pass"
    ADVISORY = "advisory"
    HALT = "halt"


class QCLevel(str, Enum):
    GOLD = "GOLD"
    SILVER = "SILVER"
    BRONZE = "BRONZE"
    FAIL = "FAIL"


@dataclass
class GateResult:
    gate: str
    action: QCAction
    level: QCLevel
    value: float
    threshold: float
    message: str
    suggestion: str = ""

    @property
    def passed(self) -> bool:
        return self.action != QCAction.HALT


@dataclass
class PhaseQCResult:
    phase: str
    gate_results: list[GateResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(g.passed for g in self.gate_results)

    @property
    def halts(self) -> list[GateResult]:
        return [g for g in self.gate_results if g.action == QCAction.HALT]

    @property
    def overall_level(self) -> QCLevel:
        if any(g.level == QCLevel.FAIL for g in self.gate_results):
            return QCLevel.FAIL
        if any(g.level == QCLevel.BRONZE for g in self.gate_results):
            return QCLevel.BRONZE
        if any(g.level == QCLevel.SILVER for g in self.gate_results):
            return QCLevel.SILVER
        return QCLevel.GOLD


QC_PROFILES: dict[str, dict[str, Any]] = {
    "docking_hit_finding": {
        "min_binding_affinity_kcal_mol": -7.0,   # weak hit threshold (Vina)
        "min_glide_score": -6.0,                  # moderate binder (Glide SP)
        "min_valid_poses": 1,
    },
    "docking_lead_opt": {
        "min_binding_affinity_kcal_mol": -8.0,   # strong hit required
        "min_glide_score": -8.0,                  # strong binder (Glide)
        "min_valid_poses": 3,
    },
    "docking_fragment": {
        "min_binding_affinity_kcal_mol": -5.0,   # fragments bind weakly
        "min_glide_score": -4.0,
        "min_valid_poses": 1,
    },
}


class DockingQCEvaluator:
    def __init__(self, profile: str = "docking_hit_finding"):
        if profile not in QC_PROFILES:
            raise ValueError(f"Unknown QC profile: {profile!r}. Options: {list(QC_PROFILES)}")
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    def evaluate_phase_1(self, metrics: dict) -> PhaseQCResult:
        results: list[GateResult] = []

        # Gate 1: success / valid poses
        success = bool(metrics.get("success", True))
        n_poses = int(metrics.get("n_poses_generated",
                      metrics.get("n_ligands_docked", 1)))
        min_poses = self.thresholds["min_valid_poses"]
        results.append(GateResult(
            gate="valid_poses",
            action=QCAction.HALT if (not success or n_poses < min_poses) else QCAction.PASS,
            level=QCLevel.FAIL if not success else (
                QCLevel.GOLD if n_poses >= min_poses * 5 else QCLevel.SILVER
            ),
            value=float(n_poses),
            threshold=float(min_poses),
            message=f"{n_poses} valid pose(s) generated (min {min_poses}); success={success}",
            suggestion=(
                "Expand binding box (center_box_expand_A) or increase exhaustiveness to recover poses."
            ) if not success or n_poses < min_poses else "",
        ))

        # Gate 2: best binding score
        # Support both Vina (best_score_kcal_mol) and Glide (top_glidescore)
        best = metrics.get("best_score_kcal_mol",
               metrics.get("top_glidescore", 0.0))
        best = float(best) if best is not None else 0.0
        is_glide = "top_glidescore" in metrics
        thresh = self.thresholds["min_glide_score"] if is_glide else self.thresholds["min_binding_affinity_kcal_mol"]
        # Lower (more negative) = better for both Vina and Glide.
        # Advisory fires for borderline-passing scores: thresh*1.15 < best ≤ thresh
        # (e.g., thresh=-7.0 → advisory for -8.05 < best ≤ -7.0).
        # Using 0.85 would give thresh*0.85 = -5.95 > thresh = -7.0 for negative thresh,
        # making the advisory unreachable — so we use 1.15 instead.
        action = QCAction.HALT if best > thresh else (
            QCAction.ADVISORY if best > thresh * 1.15 else QCAction.PASS
        )
        results.append(GateResult(
            gate="best_binding_score",
            action=action,
            level=QCLevel.GOLD if best < thresh * 1.2 else (
                QCLevel.SILVER if best <= thresh else (
                    QCLevel.BRONZE if best <= thresh * 0.8 else QCLevel.FAIL
                )
            ),
            value=best,
            threshold=thresh,
            message=(
                f"Best {'GlideScore' if is_glide else 'Vina'} score {best:.2f} kcal/mol "
                f"(hit threshold {thresh:.1f} kcal/mol)"
            ),
            suggestion=(
                "Increase exhaustiveness or expand search box to improve pose sampling. "
                "For Glide, switch precision SP→XP for better scoring accuracy."
            ) if action == QCAction.HALT else "",
        ))

        return PhaseQCResult(phase="phase_1_docking", gate_results=results)

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        dispatch = {"phase_1_docking": self.evaluate_phase_1}
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase!r}")
        return fn(metrics)
