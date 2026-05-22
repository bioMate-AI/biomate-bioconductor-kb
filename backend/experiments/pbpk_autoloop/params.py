"""PBPK simulation parameter dataclass — the knobs the auto-loop can tune."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PBPKParams:
    """
    Parameters of a PBPK simulation that the auto-loop tuner can remediate.

    Defaults reflect a typical small-molecule oral simulation in adult human.

    simulation_duration_h : total simulation time
    dose_mg               : administered dose
    fu_p                  : fraction unbound in plasma (0–1)
    clint_mL_per_min      : intrinsic hepatic clearance (mL/min)
    kp_scale              : multiplicative scale on tissue:plasma partition
                            coefficients (1.0 = unchanged)
    integration_rtol      : ODE solver relative tolerance
    integration_atol      : ODE solver absolute tolerance
    """
    simulation_duration_h: float = 24.0
    dose_mg:               float = 100.0
    fu_p:                  float = 0.1
    clint_mL_per_min:      float = 50.0
    kp_scale:              float = 1.0
    integration_rtol:      float = 1e-6
    integration_atol:      float = 1e-9

    def copy(self) -> "PBPKParams":
        return PBPKParams(
            simulation_duration_h=self.simulation_duration_h,
            dose_mg=self.dose_mg,
            fu_p=self.fu_p,
            clint_mL_per_min=self.clint_mL_per_min,
            kp_scale=self.kp_scale,
            integration_rtol=self.integration_rtol,
            integration_atol=self.integration_atol,
        )
