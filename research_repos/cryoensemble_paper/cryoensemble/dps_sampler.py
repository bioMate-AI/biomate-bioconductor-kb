"""Diffusion Posterior Sampling for cryo-EM conformational priors.

Standard DPS (Chung et al. NeurIPS 2022) for inverse problems:

    x_{t-1} = denoise_θ(x_t) + η_t · ∇_{x_t} log p(y | x̂_0(x_t))

where x̂_0 is the model's denoised estimate (Tweedie's mean), `y` is the
observed data (here: cryo-EM particle stack), and η_t is a step size.

For protein conformational priors:
  - `denoise_θ` is implemented by `PriorAdapter.score()` (equivalent to denoise
    via Tweedie: x̂_0 = x_t + σ_t² · score)
  - `∇ log p(y | x̂_0)` is the per-particle image likelihood gradient
    (we already have this — `per_particle_log_likelihood` is differentiable)

Two important departures from naïve DPS for our use case:

1. **Population vs single-state.** Standard DPS recovers a single posterior
   sample. We want a *posterior distribution* over conformational states.
   Solution: run DPS in parallel from N starting points (N samples from the
   unconditional prior) and aggregate via EM mixture posterior.

2. **Cross-particle data consistency.** The data y is a stack of K particles.
   Each particle has its own pose+CTF. The likelihood naturally factors:
       log p(y_1..K | x) = Σ_k log p(y_k | x, pose_k, CTF_k)
   We can either:
     (a) sum the log-likelihood gradient over all particles (single conformer
         is jointly optimised against all particles) — appropriate when one
         conformer is meant to explain the whole stack;
     (b) for each DPS trajectory, route particles via their soft-assignment
         responsibility r_{ki} and only flow gradient from particles with
         high r_{ki} into trajectory i.

   We implement (a) here (it's the standard formulation) and provide (b) as
   a flag for the multi-modal-prior setting.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import torch

from .forward_model import render_particle
from .likelihood import per_particle_log_likelihood, aggregate_posterior
from .priors.base import PriorAdapter


@dataclass
class DPSEMConfig:
    # Forward model
    D: int
    apix: float
    sigma_a: float = 1.5
    sigma_noise: float = 0.5

    # DPS scheduling
    n_steps: int = 50
    sigma_max: float = 1.0       # initial noise level on coordinates (Å)
    sigma_min: float = 0.05      # final noise level
    schedule: str = "linear"     # "linear" or "geometric"

    # Step sizes
    likelihood_lr: float = 0.5   # η_t for likelihood gradient
    prior_lr: float = 1.0        # η_t for prior score (denoising)

    # Particle batching
    particle_batch: int = 64

    # Numerics
    grad_clip: float = 50.0      # clamp ‖∇‖ per step

    def schedule_sigmas(self) -> torch.Tensor:
        if self.schedule == "linear":
            return torch.linspace(self.sigma_max, self.sigma_min, self.n_steps)
        elif self.schedule == "geometric":
            return torch.tensor(
                [self.sigma_max * (self.sigma_min / self.sigma_max) ** (i / max(self.n_steps - 1, 1))
                 for i in range(self.n_steps)],
                dtype=torch.float32,
            )
        else:
            raise ValueError(f"unknown schedule {self.schedule}")


# ──────────────────────────────────────────────────────────────────────────────
# Single-trajectory DPS
# ──────────────────────────────────────────────────────────────────────────────

def dps_single_trajectory(
    prior: PriorAdapter,
    *,
    particles: torch.Tensor,           # (K, D, D)
    R: torch.Tensor,                   # (K, 3, 3)
    t: torch.Tensor,                   # (K, 2)
    ctf_params: dict,                  # K-element tensor values
    config: DPSEMConfig,
    init_x: torch.Tensor | None = None,
    on_step: Callable[[int, torch.Tensor, dict], None] | None = None,
) -> dict:
    """Run a single DPS trajectory: prior score + likelihood gradient.

    Returns dict with:
        trajectory   : (n_steps+1, A, 3)  coordinate snapshots
        sigma_t      : (n_steps,) noise level at each step
        log_lik      : (n_steps+1,) Σ_k log p(particle_k | x) at each snapshot
    """
    device = particles.device
    sigmas = config.schedule_sigmas().to(device)

    # Init: sample from prior (or use init_x if given)
    if init_x is None:
        x = prior.sample(1).squeeze(0).to(device).clone()
        x = x + config.sigma_max * torch.randn_like(x)
    else:
        x = init_x.to(device).clone()
    x = x - x.mean(dim=0, keepdim=True)  # always centred

    n_atoms = x.shape[0]
    K = particles.shape[0]

    traj = [x.detach().clone().cpu()]
    log_liks = [_eval_loglik(prior, x, particles, R, t, ctf_params, config).item()]

    for step in range(config.n_steps):
        sigma_t = sigmas[step]

        # ── Prior score: pulls x toward the prior's mode mass ────────────────
        # PriorAdapter.score returns ∇ log p_prior(x); for cached priors this
        # is the KDE-smoothed attractor toward the conformer pool.
        with torch.no_grad():
            prior_grad = prior.score(x.unsqueeze(0), t=sigma_t).squeeze(0)

        # ── Likelihood gradient: pulls x toward conformations that explain y ──
        x_l = x.detach().clone().requires_grad_(True)
        total = _eval_loglik(prior, x_l, particles, R, t, ctf_params, config)
        total.backward()
        lik_grad = x_l.grad.detach()

        # Optional gradient clipping
        if config.grad_clip is not None:
            for g in (prior_grad, lik_grad):
                norm = g.norm()
                if norm > config.grad_clip:
                    g.mul_(config.grad_clip / norm)

        # ── Combined step ─────────────────────────────────────────────────────
        # x ← x + η_prior · σ_t² · score_prior + η_lik · σ_t² · ∇ log p(y|x)
        # σ_t² scaling makes the step size adapt to current noise level.
        with torch.no_grad():
            x = x + config.prior_lr * sigma_t**2 * prior_grad + config.likelihood_lr * sigma_t**2 * lik_grad
            x = x - x.mean(dim=0, keepdim=True)

        traj.append(x.detach().clone().cpu())
        log_liks.append(_eval_loglik(prior, x, particles, R, t, ctf_params, config).item())
        if on_step is not None:
            on_step(step, x.detach().cpu(), {
                "sigma": float(sigma_t),
                "log_lik": log_liks[-1],
                "prior_grad_norm": float(prior_grad.norm()),
                "lik_grad_norm": float(lik_grad.norm()),
            })

    return {
        "trajectory": torch.stack(traj),
        "sigma_t": sigmas.cpu(),
        "log_lik": torch.tensor(log_liks),
        "final": x.detach().cpu(),
    }


def _eval_loglik(
    prior: PriorAdapter,
    x: torch.Tensor,
    particles: torch.Tensor,
    R: torch.Tensor,
    t: torch.Tensor,
    ctf_params: dict,
    config: DPSEMConfig,
) -> torch.Tensor:
    """Total log p(particles | x) across all K particles, batched for memory."""
    K = particles.shape[0]
    total = torch.zeros((), device=x.device, dtype=x.dtype)
    pb = config.particle_batch
    for j0 in range(0, K, pb):
        j1 = min(j0 + pb, K)
        ctf_slice = {k: (v[j0:j1] if isinstance(v, torch.Tensor) else v)
                     for k, v in ctf_params.items()}
        ll = per_particle_log_likelihood(
            x, particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
            D=config.D, apix=config.apix,
            sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
        )
        total = total + ll.sum()
    return total


# ──────────────────────────────────────────────────────────────────────────────
# Population-DPS: N trajectories + EM aggregation
# ──────────────────────────────────────────────────────────────────────────────

def dps_em_posterior(
    prior: PriorAdapter,
    *,
    particles: torch.Tensor,
    R: torch.Tensor,
    t: torch.Tensor,
    ctf_params: dict,
    config: DPSEMConfig,
    n_trajectories: int = 20,
    prior_weights: torch.Tensor | None = None,
) -> dict:
    """Run `n_trajectories` independent DPS samples; aggregate via EM mixture.

    This is the population-level posterior — analogous to `reweight_prior` in
    `dps.py` but with each prior-pool sample first *refined by DPS* against the
    image data before mixture aggregation. The refined trajectories may land at
    coordinates **not present in the original prior pool** — that's the off-
    manifold rare-state recovery the framework is designed for.
    """
    final_coords = []
    trajectories = []
    for i in range(n_trajectories):
        out = dps_single_trajectory(
            prior, particles=particles, R=R, t=t, ctf_params=ctf_params, config=config,
        )
        final_coords.append(out["final"])
        trajectories.append(out["trajectory"])

    final = torch.stack(final_coords).to(particles.device)   # (N, A, 3)

    # Compute per-particle log-lik for each refined conformer
    K = particles.shape[0]
    log_p = torch.zeros(n_trajectories, K, device=particles.device, dtype=particles.dtype)
    for i in range(n_trajectories):
        for j0 in range(0, K, config.particle_batch):
            j1 = min(j0 + config.particle_batch, K)
            ctf_slice = {k: (v[j0:j1] if isinstance(v, torch.Tensor) else v)
                         for k, v in ctf_params.items()}
            ll = per_particle_log_likelihood(
                final[i], particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                D=config.D, apix=config.apix,
                sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
            )
            log_p[i, j0:j1] = ll

    posterior = aggregate_posterior(log_p, prior_weights, mode="mixture")
    ess = (1.0 / (posterior ** 2).sum()).item()
    assignments = log_p.argmax(dim=0).detach().cpu()

    return {
        "refined_conformers": final.detach().cpu(),
        "log_likelihoods": log_p.detach().cpu(),
        "posterior": posterior.detach().cpu(),
        "ess": ess,
        "per_particle_assignments": assignments,
        "trajectories": torch.stack(trajectories),
    }


# ──────────────────────────────────────────────────────────────────────────────
# EM-DPS: responsibility-weighted DPS for mixture recovery
# ──────────────────────────────────────────────────────────────────────────────
#
# H1 motivation: when the dataset is a mixture of K conformations and only one
# rare conformation has support in the prior, a *single* DPS trajectory gets
# gradient from the entire particle stack — so the dominant-state pull drowns
# out the rare-state signal, and no trajectory ever moves toward the rare state.
#
# Solution: run N trajectories in parallel and use *soft assignment* of particles
# to trajectories. Each trajectory's gradient is weighted by per-particle
# responsibility:  ∇log p_i ← Σ_k r_{ki} · ∇ log p(particle_k | x_i)
# where r_{ki} = soft(log p(particle_k | x_i) − logsumexp_j log p(particle_k | x_j))
#
# This is an EM-style outer loop wrapped around DPS: each outer iteration runs a
# few DPS steps for each trajectory (M-step), then recomputes responsibilities
# (E-step). Initial responsibilities are uniform.
#
# This is the algorithm that recovers off-prior rare states.


def em_dps_posterior(
    prior: PriorAdapter,
    *,
    particles: torch.Tensor,           # (K, D, D)
    R: torch.Tensor,
    t: torch.Tensor,
    ctf_params: dict,
    config: DPSEMConfig,
    n_trajectories: int = 20,
    n_outer_iters: int = 5,
    inner_dps_steps: int | None = None,
    init_responsibility: str = "uniform",   # "uniform" or "single_assignment"
) -> dict:
    """Responsibility-weighted DPS — the EM-DPS algorithm.

    Outer iterations: 1...n_outer_iters
      E-step: compute responsibility r_{ki} from current trajectories
      M-step: for each trajectory i, run `inner_dps_steps` of DPS with the
              likelihood gradient weighted by r_{:i} across particles

    Returns the same dict shape as `dps_em_posterior` plus
        responsibilities  : (K, N) final per-particle assignment probabilities
        outer_log_evidence : (n_outer_iters,) total log-evidence per outer iter
    """
    device = particles.device
    K = particles.shape[0]
    N = n_trajectories
    if inner_dps_steps is None:
        inner_dps_steps = max(1, config.n_steps // n_outer_iters)

    # Initialise N trajectories at independent prior samples
    coords = prior.sample(N).to(device).clone()                # (N, A, 3)
    coords = coords - coords.mean(dim=1, keepdim=True)
    n_atoms = coords.shape[1]

    sigmas = config.schedule_sigmas().to(device)
    # We reuse one schedule across all outer iters to keep behaviour interpretable
    step_idx = 0
    outer_logL = []

    for outer in range(n_outer_iters):
        # ── E-step: per-particle log-lik for each current conformer ──────────
        with torch.no_grad():
            log_p = torch.zeros(N, K, device=device, dtype=coords.dtype)
            for i in range(N):
                for j0 in range(0, K, config.particle_batch):
                    j1 = min(j0 + config.particle_batch, K)
                    ctf_slice = {k: (v[j0:j1] if isinstance(v, torch.Tensor) else v)
                                 for k, v in ctf_params.items()}
                    ll = per_particle_log_likelihood(
                        coords[i], particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                        D=config.D, apix=config.apix,
                        sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
                    )
                    log_p[i, j0:j1] = ll
            log_norm = torch.logsumexp(log_p, dim=0)             # (K,)
            log_r = log_p - log_norm.unsqueeze(0)                # (N, K) responsibilities
            r = torch.exp(log_r)                                 # (N, K)
            evidence = log_norm.sum().item()
            outer_logL.append(evidence)

        # ── M-step: DPS update on each trajectory, gradient weighted by r ───
        for inner_step in range(inner_dps_steps):
            sigma_t = sigmas[min(step_idx, len(sigmas) - 1)]
            step_idx += 1

            # Prior score (per-trajectory)
            with torch.no_grad():
                prior_grad = prior.score(coords, t=sigma_t)        # (N, A, 3)

            # Likelihood gradient — weighted by r per-particle, per-trajectory
            lik_grad = torch.zeros_like(coords)
            for i in range(N):
                w_i = r[i]                                          # (K,)
                if w_i.sum() < 1e-6:
                    continue                                        # trajectory has no support
                x_l = coords[i].detach().clone().requires_grad_(True)
                # Weighted total log-lik over particles
                total = torch.zeros((), device=device, dtype=coords.dtype)
                for j0 in range(0, K, config.particle_batch):
                    j1 = min(j0 + config.particle_batch, K)
                    ctf_slice = {k: (v[j0:j1] if isinstance(v, torch.Tensor) else v)
                                 for k, v in ctf_params.items()}
                    ll_batch = per_particle_log_likelihood(
                        x_l, particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                        D=config.D, apix=config.apix,
                        sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
                    )
                    total = total + (ll_batch * w_i[j0:j1]).sum()
                total.backward()
                lik_grad[i] = x_l.grad.detach()

            # Gradient clipping
            if config.grad_clip is not None:
                for g in (prior_grad, lik_grad):
                    norms = g.reshape(N, -1).norm(dim=-1)
                    factor = (config.grad_clip / norms.clamp_min(1e-6)).clamp_max(1.0)
                    g.mul_(factor.unsqueeze(-1).unsqueeze(-1))

            with torch.no_grad():
                coords = coords + config.prior_lr * sigma_t**2 * prior_grad \
                                 + config.likelihood_lr * sigma_t**2 * lik_grad
                coords = coords - coords.mean(dim=1, keepdim=True)

    # ── Final E-step for the returned posterior ──────────────────────────────
    with torch.no_grad():
        log_p = torch.zeros(N, K, device=device, dtype=coords.dtype)
        for i in range(N):
            for j0 in range(0, K, config.particle_batch):
                j1 = min(j0 + config.particle_batch, K)
                ctf_slice = {k: (v[j0:j1] if isinstance(v, torch.Tensor) else v)
                             for k, v in ctf_params.items()}
                ll = per_particle_log_likelihood(
                    coords[i], particles[j0:j1], R[j0:j1], t[j0:j1], ctf_slice,
                    D=config.D, apix=config.apix,
                    sigma_a=config.sigma_a, sigma_noise=config.sigma_noise,
                )
                log_p[i, j0:j1] = ll

    posterior = aggregate_posterior(log_p, prior_weights=None, mode="mixture")
    ess = (1.0 / (posterior ** 2).sum()).item()
    assignments = log_p.argmax(dim=0).detach().cpu()
    return {
        "refined_conformers": coords.detach().cpu(),
        "log_likelihoods": log_p.detach().cpu(),
        "posterior": posterior.detach().cpu(),
        "responsibilities": torch.exp(log_p - torch.logsumexp(log_p, dim=0, keepdim=True)).detach().cpu(),
        "ess": ess,
        "per_particle_assignments": assignments,
        "outer_log_evidence": torch.tensor(outer_logL),
    }


__all__ = [
    "DPSEMConfig", "dps_single_trajectory",
    "dps_em_posterior", "em_dps_posterior",
]
