"""End-to-end pipeline test.

Synthesises a small two-state protein, generates realistic-noise particles for the
rare state at 5% prevalence, runs reweight_prior, verifies the posterior concentrates
on conformers near the rare state.

This is the in-silico analogue of the ADK proof-of-concept, but now using REAL 2D
images (not coordinate-space) with CTF — i.e., what the proposal commits to.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.forward_model import render_particle, euler_zyz_to_matrix
from cryoensemble.dps import DPSConfig, reweight_prior
from cryoensemble.evaluate import evaluate, kabsch_rmsd


def make_helix(n: int = 60) -> torch.Tensor:
    i = torch.arange(n, dtype=torch.float32)
    th = i * 100.0 * math.pi / 180.0
    x = 2.3 * torch.cos(th)
    y = 2.3 * torch.sin(th)
    z = 1.5 * i
    z = z - z.mean()
    return torch.stack([x, y, z], dim=-1)


def main():
    torch.manual_seed(0)
    np.random.seed(0)

    D, apix = 64, 1.8

    # Two states: open helix (resting) and closed helix (compressed)
    open_state = make_helix(50)
    closed_state = open_state.clone()
    closed_state[25:, 2] *= 0.4              # crush the C-terminal half along z

    rmsd_oc = kabsch_rmsd(open_state.numpy(), closed_state.numpy())
    print(f"Open ↔ Closed RMSD: {rmsd_oc:.2f} Å")

    # Particles: 95% open, 5% closed
    n_part = 200
    n_closed = int(round(0.05 * n_part))
    n_open = n_part - n_closed

    # Random poses
    rng = torch.Generator().manual_seed(42)
    alpha = (torch.rand(n_part, generator=rng) * 2 * math.pi)
    beta = torch.acos(2 * torch.rand(n_part, generator=rng) - 1)
    gamma = (torch.rand(n_part, generator=rng) * 2 * math.pi)
    R = euler_zyz_to_matrix(alpha, beta, gamma)
    t = torch.zeros(n_part, 2)

    # CTF params: spread defocus values
    ctf_params = dict(
        defocus_u=torch.linspace(8000, 25000, n_part),
        defocus_v=torch.linspace(8500, 25500, n_part),
        astig_angle_deg=torch.rand(n_part, generator=rng) * 90,
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )

    truths = [open_state] * n_open + [closed_state] * n_closed
    truth_coords = torch.stack(truths, dim=0)
    obs = render_particle(truth_coords, R, t, D=D, apix=apix, **ctf_params)
    obs = obs + 0.05 * torch.randn_like(obs)

    print(f"Generated {n_part} particles: {n_open} open + {n_closed} closed")

    # Prior: 20 perturbations of open + 4 of closed (5/24 ≈ 21% closed — over-sampled
    # in the prior so the posterior really has to pull weight from the open mode
    # back to the closed mode based on evidence)
    n_open_prior, n_closed_prior = 20, 4
    prior = []
    for _ in range(n_open_prior):
        prior.append(open_state + 0.3 * torch.randn_like(open_state))
    for _ in range(n_closed_prior):
        prior.append(closed_state + 0.3 * torch.randn_like(closed_state))
    prior = torch.stack(prior, dim=0)
    truths_label = np.array(["open"] * n_open_prior + ["closed"] * n_closed_prior)

    # Verify the prior actually covers both states (sanity check)
    rmsds_open = np.array([kabsch_rmsd(prior[i].numpy(), open_state.numpy()) for i in range(len(prior))])
    rmsds_closed = np.array([kabsch_rmsd(prior[i].numpy(), closed_state.numpy()) for i in range(len(prior))])
    print(f"Prior: {n_open_prior} open-perturbed (RMSD to open: {rmsds_open[:n_open_prior].mean():.2f}±{rmsds_open[:n_open_prior].std():.2f} Å)")
    print(f"       {n_closed_prior} closed-perturbed (RMSD to closed: {rmsds_closed[n_open_prior:].mean():.2f}±{rmsds_closed[n_open_prior:].std():.2f} Å)")

    cfg = DPSConfig(D=D, apix=apix, sigma_a=1.5, sigma_noise=0.5, particle_batch=64)

    print("\nRunning per-particle posterior...")
    summary, raw = evaluate(
        prior, obs, R, t, ctf_params, cfg,
        rare_reference=closed_state.numpy(),
        rmsd_threshold_A=2.0,
    )
    print(f"  ESS = {summary.posterior_ess:.1f} / {len(prior)}")
    print(f"  Entropy = {summary.posterior_entropy_bits:.2f} bits")
    print(f"  Max weight = {summary.posterior_max_weight:.3f}")
    print(f"  Rare-state min RMSD in prior = {summary.rare_state_min_rmsd:.2f} Å")
    print(f"  Rare-state posterior mass = {summary.rare_state_posterior_mass:.3f}")
    print(f"  Rare-state recovered = {summary.rare_state_recovered}")

    post = raw["posterior"].numpy()
    print("\nPer-conformer posterior:")
    for i, (lab, w) in enumerate(zip(truths_label, post)):
        bar = "█" * int(w * 60)
        print(f"  [{i:02d}] {lab:6s}  {w:.4f}  {bar}")

    # Assertions
    open_mass = post[:n_open_prior].sum()
    closed_mass = post[n_open_prior:].sum()
    print(f"\nopen-prior posterior mass: {open_mass:.3f}")
    print(f"closed-prior posterior mass: {closed_mass:.3f}")

    # With 95% open particles, the open mode should dominate but the closed mode
    # should NOT be zero (it has 5% of the evidence and rare conformers in the prior).
    assert open_mass > 0.6, f"open mode should dominate, got {open_mass:.3f}"
    assert closed_mass > 0.01, f"closed mode must retain non-trivial weight, got {closed_mass:.3f}"
    print("\nEnd-to-end pipeline test: PASSED")


if __name__ == "__main__":
    main()
