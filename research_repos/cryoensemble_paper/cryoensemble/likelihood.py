"""Per-particle Gaussian log-likelihood.

Given:
  - a conformer (atomic coords)
  - a particle image with known pose and CTF parameters

Compute log p(image | conformer, pose, CTF) under a Gaussian noise model.

This is the core quantity that distinguishes CryoEnsemble from map-level BME methods.
Map-level methods compute log p(reconstruction_map | conformer) — averaging away
the rare-state signal. Per-particle methods compute log p(particle_k | conformer)
for every particle k, then aggregate — preserving the rare-state evidence.
"""

from __future__ import annotations

import torch
import torch.nn.functional as F

from .forward_model import render_particle


def per_particle_log_likelihood(
    coords: torch.Tensor,             # (N_atoms, 3) — one conformer's Cα coords (Å, centered)
    particle_images: torch.Tensor,    # (B, D, D) — observed particles
    R: torch.Tensor,                  # (B, 3, 3) — per-particle rotation
    t: torch.Tensor,                  # (B, 2) — per-particle image-plane shift (Å)
    ctf_params: dict,                 # dict of (B,)-shape CTF tensors
    *,
    D: int,
    apix: float,
    sigma_a: float = 1.5,
    sigma_noise: float = 0.1,         # per-pixel Gaussian noise σ (after normalisation)
    weights: torch.Tensor | None = None,
    normalise: str = "zscore",        # "none" | "zscore" | "minmax"
    mask: torch.Tensor | None = None, # (D, D) circular mask; auto-built if None
) -> torch.Tensor:
    """Return shape-(B,) tensor of log p(image_k | conformer, pose_k, ctf_k).

    Implementation
    --------------
    1. Render the single conformer at each particle's pose+CTF (broadcasting coords).
    2. Normalise both rendered and observed images (mean 0, std 1 by default).
    3. Apply circular mask (default: radius D/2).
    4. Gaussian likelihood: -½ Σ_pix ((I_obs - I_pred) / σ_noise)²  - const
    """
    device = particle_images.device
    dtype = particle_images.dtype
    B = particle_images.shape[0]

    # Broadcast coords to (B, N, 3)
    coords_b = coords.unsqueeze(0).expand(B, -1, -1).to(device=device, dtype=dtype)

    pred = render_particle(
        coords_b, R, t,
        D=D, apix=apix, sigma_a=sigma_a, weights=weights,
        **ctf_params,
    )                                                       # (B, D, D)

    if mask is None:
        cy, cx = (D - 1) / 2.0, (D - 1) / 2.0
        yy, xx = torch.meshgrid(
            torch.arange(D, device=device, dtype=dtype),
            torch.arange(D, device=device, dtype=dtype),
            indexing="ij",
        )
        mask = ((yy - cy) ** 2 + (xx - cx) ** 2) <= (D / 2.0) ** 2
        mask = mask.to(dtype)

    obs = particle_images
    # Normalise per-image using mask
    def _norm(im):
        if normalise == "none":
            return im
        m = mask
        if normalise == "zscore":
            n = m.sum()
            mu = (im * m).sum(dim=(-2, -1), keepdim=True) / n
            v = ((im - mu) ** 2 * m).sum(dim=(-2, -1), keepdim=True) / n
            return (im - mu) / torch.sqrt(v + 1e-8)
        if normalise == "minmax":
            mn = im.amin(dim=(-2, -1), keepdim=True)
            mx = im.amax(dim=(-2, -1), keepdim=True)
            return (im - mn) / (mx - mn + 1e-8)
        raise ValueError(f"unknown normalise={normalise}")

    obs_n = _norm(obs)
    pred_n = _norm(pred)

    diff2 = ((obs_n - pred_n) ** 2) * mask                  # (B, D, D)
    npix = mask.sum()
    sse = diff2.sum(dim=(-2, -1))                           # (B,)

    # Log-likelihood (drop constant terms; treat σ as fixed hyperparameter)
    logL = -0.5 * sse / (sigma_noise ** 2)
    return logL


def aggregate_posterior(
    conformer_log_likelihoods: torch.Tensor,    # (n_conformers, n_particles)
    prior_weights: torch.Tensor | None = None,  # (n_conformers,)
    mode: str = "mixture",
    em_iters: int = 200,
    em_tol: float = 1e-6,
) -> torch.Tensor:
    """Combine per-particle log-likelihoods into a posterior over conformers.

    Two modes
    ---------
    mode="single" (Bayes for a single explanatory conformer):
        log w_i ∝ log π(i) + Σ_k log p(image_k | conformer_i)
        Use when the dataset is genuinely homogeneous (one true conformer).

    mode="mixture" (EM over conformer mixture weights) — DEFAULT, what cryo-EM needs:
        The dataset is a mixture of conformations. We learn the mixing weights w_i
        such that  log p(particles | w) = Σ_k log Σ_i w_i p(image_k | conformer_i)
        is maximized. Each particle "votes" for the conformer that best explains it;
        rare states are recovered because their few particles are best explained by
        the matching rare-state conformers, not the majority.

        E-step:  r_{ki} = w_i p_{ki} / Σ_j w_j p_{kj}
        M-step:  w_i   = (1/N) Σ_k r_{ki}

    Returns (n_conformers,) summing to 1.
    """
    if mode == "single":
        log_evidence = conformer_log_likelihoods.sum(dim=-1)
        if prior_weights is not None:
            log_evidence = log_evidence + torch.log(prior_weights + 1e-30)
        log_evidence = log_evidence - log_evidence.max()
        w = torch.exp(log_evidence)
        return w / w.sum()

    if mode == "mixture":
        # Stable EM in log-space.
        # log_p has shape (n_conf, n_particles)
        log_p = conformer_log_likelihoods
        n_conf, n_part = log_p.shape

        # Initial weights: prior if given, else uniform
        if prior_weights is None:
            w = torch.full((n_conf,), 1.0 / n_conf, dtype=log_p.dtype, device=log_p.device)
        else:
            w = prior_weights / prior_weights.sum()

        prev_logL = float("-inf")
        for it in range(em_iters):
            # log r_{ki} = log w_i + log p_{ki} − logsumexp_j (log w_j + log p_{kj})
            log_w = torch.log(w + 1e-30).unsqueeze(-1)             # (n_conf, 1)
            log_joint = log_w + log_p                              # (n_conf, n_part)
            log_norm = torch.logsumexp(log_joint, dim=0)           # (n_part,)
            log_resp = log_joint - log_norm                        # responsibilities
            r = torch.exp(log_resp)                                # (n_conf, n_part)

            # M-step
            w_new = r.mean(dim=-1)
            w_new = w_new / w_new.sum()

            # Convergence check via marginal log-likelihood
            logL = log_norm.sum().item()
            if abs(logL - prev_logL) < em_tol * max(1.0, abs(logL)):
                w = w_new
                break
            prev_logL = logL
            w = w_new
        return w

    raise ValueError(f"unknown mode={mode}")


__all__ = ["per_particle_log_likelihood", "aggregate_posterior"]
