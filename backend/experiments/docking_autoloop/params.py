"""
Docking parameter schema.

Covers both AutoDock Vina (docking_autodock_vina_results.json) and
Schrodinger Glide (docking_summary.json).

Hit thresholds from qc_trace_monitor.py:
  binding_affinity < -7 kcal/mol (Vina) → hit
  GlideScore < -6 (Glide SP) → moderate binder; < -8 → strong binder
"""
from dataclasses import dataclass, field, asdict


@dataclass
class DockingParams:
    """Tunable parameters for a virtual screening / docking run."""

    # ── Hit threshold gates ───────────────────────────────────────────────────
    # Vina: binding_affinity (kcal/mol); lower = stronger (more negative)
    min_binding_affinity_kcal_mol: float = -7.0   # HALT if best score > this
    # Glide GlideScore (same convention; lower = stronger)
    min_glide_score: float = -6.0

    # ── Enrichment quality gates ──────────────────────────────────────────────
    min_valid_poses: int = 1           # HALT if no valid poses produced
    min_hit_fraction: float = 0.05    # fraction of screened ligands that are hits

    # ── Search parameters (tunable for retry) ─────────────────────────────────
    exhaustiveness: int = 8           # Vina exhaustiveness (higher = better sampling)
    n_poses: int = 9                  # number of output poses per ligand
    energy_range_kcal: float = 3.0   # energy window above best pose
    center_box_expand_A: float = 0.0 # expand binding box by this amount on retry

    # ── Grid / scoring ────────────────────────────────────────────────────────
    docking_precision: str = "SP"     # Glide precision: SP | XP | HTVS
    use_epik: bool = True             # Glide: Epik state penalties

    # ── Screening scope ───────────────────────────────────────────────────────
    n_ligands: int = 100              # ligands submitted per run

    def to_dict(self) -> dict:
        return asdict(self)

    def copy(self) -> "DockingParams":
        return DockingParams(**asdict(self))


PHASE_PARAM_OWNERS: dict[str, list[str]] = {
    "phase_1_docking": [
        "exhaustiveness", "n_poses", "energy_range_kcal",
        "center_box_expand_A", "docking_precision", "use_epik",
    ],
    "phase_2_hit_selection": [
        "min_binding_affinity_kcal_mol", "min_glide_score",
        "min_valid_poses", "min_hit_fraction", "n_ligands",
    ],
}
