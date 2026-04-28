"""
NCA PK parameter schema.

Gates on nca_summary.json from drug_discovery/nca_pknca/main.nf.

FDA guidance: AUCinf extrapolation > 20% of total AUC indicates insufficient
terminal phase sampling; the estimated AUCinf is unreliable.

nca_summary.json schema (from nca_pknca/main.nf):
  {
    "study_info": {"n_subjects": int, ...},
    "population_summary": {
      "auc_last_mean": float,
      "auc_inf_mean":  float,
      "cmax_mean":     float,
      "tmax_mean":     float,
      "t_half_mean":   float,
      "auc_extrap_pct": float,      -- % AUC from t_last → ∞
      "subjects_with_no_terminal_slope": int
    }
  }
"""
from dataclasses import dataclass, field, asdict


@dataclass
class NCAPKParams:
    """Tunable parameters for an NCA PK analysis run."""

    # ── FDA AUC extrapolation gate ────────────────────────────────────────────
    max_auc_extrap_pct: float = 20.0   # FDA: > 20% → unreliable AUCinf
    max_no_slope_subjects: int = 2     # subjects missing terminal slope

    # ── Half-life quality ─────────────────────────────────────────────────────
    min_t_half_h: float = 0.5          # half-life < 0.5h → likely measurement noise
    max_t_half_h: float = 72.0         # half-life > 72h → insufficient late sampling

    # ── Sampling schedule parameters (tunable for retry) ─────────────────────
    last_sampling_time_h: float = 24.0     # extend on retry for drugs with long t½
    terminal_phase_points: int = 3         # min points for reliable slope estimate
    sampling_interval_fraction: float = 0.5  # late sampling as fraction of expected t½

    # ── Population parameters ─────────────────────────────────────────────────
    n_subjects: int = 6               # subjects in study
    dose_mg: float = 100.0

    def to_dict(self) -> dict:
        return asdict(self)

    def copy(self) -> "NCAPKParams":
        return NCAPKParams(**asdict(self))


PHASE_PARAM_OWNERS: dict[str, list[str]] = {
    "phase_1_nca_analysis": [
        "max_auc_extrap_pct", "max_no_slope_subjects",
        "min_t_half_h", "max_t_half_h",
    ],
    "phase_2_sampling_adequacy": [
        "last_sampling_time_h", "terminal_phase_points", "sampling_interval_fraction",
    ],
}
