"""Diffusion Posterior Sampler — gradient-driven update of a conformational prior
toward a posterior conditioned on per-particle cryo-EM image likelihoods.

This is a simplified, score-free DPS variant suitable for the rare-state recovery
demonstration in the proposal: rather than backpropagating through a learned
diffusion score network, we treat the prior ensemble as fixed samples and reweight
+ Langevin-refine them.

For each prior conformer X_i:
  - compute Σ_k log p(particle_k | X_i, pose_k, CTF_k)   (likelihood)
  - optionally refine X_i by Langevin steps:
        X ← X + η ∇_X Σ_k log p(particle_k | X, pose_k, CTF_k) + √(2η) ξ
    (gradient descent on the negative log-posterior + noise for exploration)

Two operating modes:
  (a) "reweight" — fastest, just compute per-conformer evidence and aggregate.
  (b) "langevin" — refine each conformer with N gradient steps before reweighting.

The reweight path is exactly what the ADK proof-of-concept does. The Langevin path
is what's needed to move probability mass to rare states absent from the prior.
"""

from __future__ import annotations

from dataclasses import dataclass

import torch

from .likelihood import per_particle_log_likelihood, aggregate_posterior


@dataclass
class DPSConfig:
    D: int                                  # image size
    apix: float                             # pixel size (Å)
    sigma_a: float = 1.5                    # atomic Gaussian σ (Å)
    sigma_noise: float = 0.1                # per-pixel noise σ (after normalisation)
    # Langevin refinement
    n_langevin_steps: int = 0               # 0 = pure reweight, >0 = Langevin
    langevin_lr: float = 1.0                # step size η
    langevin_temperature: float = 1.0       # Langevin noise scale multiplier
    # Particle batching (memory)
    particle_batch: int = 128


def reweight_prior(
    prior_coords: torch.Tensor,             # (n_conf, n_atoms, 3)
    particles: torch.Tensor,                # (n_part, D, D)
    R: torch.Tensor,                        # (n_part, 3, 3)
    t: torch.Tensor,                        # (n_part, 2)
    ctf_params: dict,                       # each value (n_part,)
    config: DPSConfig,
    prior_weights: torch.Tensor | None = None,
    posterior_mode: str = "mixture",        # "mixture" (EM) or "single"
) -> dict:
    """Compute posterior mixture weights over prior conformers.

    Returns dict with keys:
        log_likelihoods : (n_conf, n_part)  per-conformer per-particle log p
        posterior       : (n_conf,) mixture weights
        ess             : effective sample size 1 / Σ w²
        per_particle_assignments : (n_part,) most-likely conformer index
    """
    n_conf, _, _ = prior_coords.shape
    n_part = particles.shape[0]
    device = particles.device

    log_p = torch.zeros(n_conf, n_part, device=device, dtype=particles.dtype)

    pbatch = config.particle_batch
    for i in range(n_conf):
        conf = prior_coords[i]
        for j0 in range(0, n_part, pbatch):
            j1 = min(j0 + pbatch, n_part)
            ctf_slice = {k: v[j0:j1].to(device) if isinstance(v, torch.Tensor) else v
                         for k, v in ctf_params.items()}
            ll = per_particle_log_likelihood(
                conf, particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                D=config.D, apix=config.apix,
                sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
            )
            log_p[i, j0:j1] = ll

    posterior = aggregate_posterior(log_p, prior_weights, mode=posterior_mode)
    ess = (1.0 / (posterior**2).sum()).item()
    assignments = log_p.argmax(dim=0).detach().cpu()

    return {
        "log_likelihoods": log_p.detach().cpu(),
        "posterior": posterior.detach().cpu(),
        "ess": ess,
        "per_particle_assignments": assignments,
    }


def langevin_refine(
    coords_init: torch.Tensor,              # (n_atoms, 3) starting conformer
    particles: torch.Tensor,                # (n_part, D, D)
    R: torch.Tensor,
    t: torch.Tensor,
    ctf_params: dict,
    config: DPSConfig,
) -> dict:
    """Langevin-refine a single conformer toward the posterior mode.

    Update rule:
        X ← X + (η / σ_noise²) ∇_X log p(particles | X) + sqrt(2 η T) ξ

    Returns
    -------
    trajectory : (n_steps+1, n_atoms, 3)  coordinate snapshots
    log_post   : (n_steps+1,)             log Σ_k log p(particle_k | X) at each step
    """
    device = particles.device
    coords = coords_init.detach().clone().to(device).requires_grad_(True)

    traj = [coords.detach().clone().cpu()]
    log_post = []

    pbatch = config.particle_batch
    n_part = particles.shape[0]

    for step in range(config.n_langevin_steps):
        if coords.grad is not None:
            coords.grad.zero_()
        total = torch.zeros((), device=device, dtype=coords.dtype)
        for j0 in range(0, n_part, pbatch):
            j1 = min(j0 + pbatch, n_part)
            ctf_slice = {k: v[j0:j1].to(device) if isinstance(v, torch.Tensor) else v
                         for k, v in ctf_params.items()}
            ll = per_particle_log_likelihood(
                coords, particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                D=config.D, apix=config.apix,
                sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
            )
            total = total + ll.sum()
        total.backward()
        log_post.append(total.detach().cpu())

        with torch.no_grad():
            noise = torch.randn_like(coords) * (2 * config.langevin_lr * config.langevin_temperature) ** 0.5
            coords = coords + config.langevin_lr * coords.grad + noise
            coords.requires_grad_(True)
        traj.append(coords.detach().clone().cpu())

    # final eval
    with torch.no_grad():
        total = torch.zeros((), device=device, dtype=coords.dtype)
        for j0 in range(0, n_part, pbatch):
            j1 = min(j0 + pbatch, n_part)
            ctf_slice = {k: v[j0:j1].to(device) if isinstance(v, torch.Tensor) else v
                         for k, v in ctf_params.items()}
            ll = per_particle_log_likelihood(
                coords, particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                D=config.D, apix=config.apix,
                sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
            )
            total = total + ll.sum()
        log_post.append(total.detach().cpu())

    return {
        "trajectory": torch.stack(traj),
        "log_posterior": torch.tensor(log_post),
        "final_coords": coords.detach().cpu(),
    }


__all__ = ["DPSConfig", "reweight_prior", "langevin_refine"]
