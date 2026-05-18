"""End-to-end evaluation pipeline.

Given:
  - A set of prior conformers (e.g., a BioEmu ensemble)
  - A real cryo-EM particle stack (with poses + CTF)

Compute:
  - The posterior over prior conformers (per-particle likelihood reweighting)
  - The effective sample size (ESS) — how concentrated the posterior is
  - Rare-state recovery: if a known "rare" reference is provided, the posterior
    weight that lands on conformers within `rmsd_threshold` of that reference

This is the proposal's central deliverable: per-particle conditioning on real
images, on a real protein, in a single pipeline.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
import torch

from .dps import DPSConfig, reweight_prior


def kabsch_rmsd(P: np.ndarray, Q: np.ndarray) -> float:
    """Kabsch-aligned Cα RMSD between two equal-length atom sets."""
    P = P - P.mean(0)
    Q = Q - Q.mean(0)
    H = P.T @ Q
    U, _, Vt = np.linalg.svd(H)
    d = np.linalg.det(Vt.T @ U.T)
    R = Vt.T @ np.diag([1, 1, d]) @ U.T
    return float(np.sqrt(((P @ R.T - Q) ** 2).sum(-1).mean()))


@dataclass
class EvaluationResult:
    n_conformers: int
    n_particles: int
    posterior_max_weight: float
    posterior_ess: float
    posterior_entropy_bits: float
    rare_state_recovered: bool | None
    rare_state_posterior_mass: float | None
    rare_state_min_rmsd: float | None

    def to_dict(self):
        return asdict(self)


def evaluate(
    prior_coords: torch.Tensor,             # (n_conf, n_atoms, 3) Cα Å
    particles: torch.Tensor,                # (n_part, D, D)
    R: torch.Tensor,
    t: torch.Tensor,
    ctf_params: dict,
    config: DPSConfig,
    *,
    rare_reference: np.ndarray | None = None,
    rmsd_threshold_A: float = 2.0,
) -> tuple[EvaluationResult, dict]:
    """Run the per-particle posterior on a real particle stack.

    Returns (summary, raw_outputs).
    """
    out = reweight_prior(prior_coords, particles, R, t, ctf_params, config)
    post = out["posterior"].numpy()

    # Posterior summary
    entropy = float(-(post * np.log2(post + 1e-30)).sum())
    max_w = float(post.max())

    # Rare-state recovery
    rare_recovered = None
    rare_mass = None
    rare_min_rmsd = None
    if rare_reference is not None:
        coords_np = prior_coords.detach().cpu().numpy()
        # Trim to common length
        n = min(rare_reference.shape[0], coords_np.shape[1])
        ref = rare_reference[:n]
        rmsds = np.array([kabsch_rmsd(coords_np[i, :n], ref) for i in range(coords_np.shape[0])])
        within = rmsds < rmsd_threshold_A
        rare_min_rmsd = float(rmsds.min())
        rare_mass = float(post[within].sum())
        rare_recovered = bool(rare_min_rmsd < rmsd_threshold_A and rare_mass > 1e-3)

    summary = EvaluationResult(
        n_conformers=int(prior_coords.shape[0]),
        n_particles=int(particles.shape[0]),
        posterior_max_weight=max_w,
        posterior_ess=float(out["ess"]),
        posterior_entropy_bits=entropy,
        rare_state_recovered=rare_recovered,
        rare_state_posterior_mass=rare_mass,
        rare_state_min_rmsd=rare_min_rmsd,
    )
    return summary, out


def save_results(summary: EvaluationResult, raw: dict, outdir: str | Path):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    with open(outdir / "summary.json", "w") as f:
        json.dump(summary.to_dict(), f, indent=2)
    if "log_likelihoods" in raw:
        np.save(outdir / "log_likelihoods.npy", raw["log_likelihoods"].numpy())
    if "log_evidence" in raw:
        np.save(outdir / "log_evidence.npy", raw["log_evidence"].numpy())
    np.save(outdir / "posterior.npy", raw["posterior"].numpy())
    if "per_particle_assignments" in raw:
        np.save(outdir / "per_particle_assignments.npy", raw["per_particle_assignments"].numpy())


__all__ = ["kabsch_rmsd", "EvaluationResult", "evaluate", "save_results"]
