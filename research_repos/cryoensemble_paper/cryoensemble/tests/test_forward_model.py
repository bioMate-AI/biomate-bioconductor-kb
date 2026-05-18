"""Smoke + correctness tests for the forward model and likelihood.

Run with:
    cd /home/yzhang/biomate/research_repos/cryoensemble_paper
    python -m cryoensemble.tests.test_forward_model

These tests exercise the differentiable rendering pipeline against simple synthetic data,
verifying that:
  1. Projecting atoms produces a non-empty image
  2. CTF application produces image with expected frequency-domain structure
  3. log-likelihood ranks the correct conformer highest when given its own rendered image
  4. Gradients flow back to atomic coordinates (required for DPS)
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import torch

# Make import work whether run as module or script
ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.forward_model import (
    project_atoms_to_image,
    render_particle,
    quaternion_to_rotation_matrix,
)
from cryoensemble.likelihood import per_particle_log_likelihood, aggregate_posterior
from cryoensemble.ctf import ctf2d


def make_helix_coords(n_res: int = 50, rise: float = 1.5, radius: float = 2.3) -> torch.Tensor:
    """Build a synthetic α-helix Cα trace, centered at origin."""
    i = torch.arange(n_res, dtype=torch.float32)
    twist = i * (100.0 * math.pi / 180.0)
    x = radius * torch.cos(twist)
    y = radius * torch.sin(twist)
    z = i * rise
    z = z - z.mean()
    return torch.stack([x, y, z], dim=-1)


def test_projection_nonempty():
    coords = make_helix_coords(50).unsqueeze(0)             # (1, 50, 3)
    R = torch.eye(3).unsqueeze(0)
    t = torch.zeros(1, 2)
    img = project_atoms_to_image(coords, R, t, D=64, apix=1.5, sigma_a=1.5)
    assert img.shape == (1, 64, 64)
    assert img.sum().item() > 0, "projection should have non-zero density"
    print(f"  test_projection_nonempty: ✓  mean={img.mean():.4f}, max={img.max():.4f}")


def test_ctf_shape_and_symmetry():
    D, apix = 64, 1.5
    ctf = ctf2d(
        D=D, apix=apix,
        defocus_u=torch.tensor([15000.0]),
        defocus_v=torch.tensor([14500.0]),
        astig_angle_deg=torch.tensor([0.0]),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )
    assert ctf.shape == (1, D, D)
    # CTF should be centro-symmetric on the symmetric interior (even-D FFT grids
    # include an extra Nyquist column that has no mirror; exclude it).
    inner = ctf[:, 1:, 1:]
    flipped = torch.flip(inner, dims=(-2, -1))
    err = (inner - flipped).abs().mean().item()
    assert err < 1e-4, f"CTF not centro-symmetric (interior): {err}"
    print(f"  test_ctf_shape_and_symmetry: ✓  interior symmetry error={err:.2e}")


def test_render_with_ctf():
    coords = make_helix_coords(50).unsqueeze(0)
    R = torch.eye(3).unsqueeze(0)
    t = torch.zeros(1, 2)
    img = render_particle(
        coords, R, t, D=64, apix=1.5,
        defocus_u=torch.tensor([15000.0]),
        defocus_v=torch.tensor([14500.0]),
        astig_angle_deg=torch.tensor([0.0]),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )
    assert img.shape == (1, 64, 64)
    print(f"  test_render_with_ctf: ✓  range=[{img.min():.4f}, {img.max():.4f}]")


def test_likelihood_ranks_correct_conformer():
    """The decisive test: synthesize an image from conformer A, then ensure
    that A's log-likelihood beats a perturbed conformer B's log-likelihood."""
    torch.manual_seed(0)
    A = make_helix_coords(40)
    B = A + 0.05 * torch.randn_like(A)                      # tiny perturbation
    C = A + 2.0 * torch.randn_like(A)                       # larger perturbation

    D, apix = 64, 1.5
    R = torch.eye(3).unsqueeze(0)
    t = torch.zeros(1, 2)
    ctf_params = dict(
        defocus_u=torch.tensor([15000.0]),
        defocus_v=torch.tensor([14500.0]),
        astig_angle_deg=torch.tensor([0.0]),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )

    obs = render_particle(A.unsqueeze(0), R, t, D=D, apix=apix, **ctf_params)
    obs = obs + 0.02 * torch.randn_like(obs)                # additive noise

    lA = per_particle_log_likelihood(A, obs, R, t, ctf_params, D=D, apix=apix).item()
    lB = per_particle_log_likelihood(B, obs, R, t, ctf_params, D=D, apix=apix).item()
    lC = per_particle_log_likelihood(C, obs, R, t, ctf_params, D=D, apix=apix).item()

    print(f"  log L:  A={lA:.2f}  B={lB:.2f}  C={lC:.2f}")
    assert lA > lB, "correct conformer should beat small perturbation"
    assert lB > lC, "small perturbation should beat large perturbation"
    print(f"  test_likelihood_ranks_correct_conformer: ✓")


def test_gradient_flows_to_coords():
    """DPS requires ∇_coords log p — verify the gradient exists and is finite."""
    coords = make_helix_coords(30).clone().requires_grad_(True)
    R = torch.eye(3).unsqueeze(0)
    t = torch.zeros(1, 2)
    obs = torch.randn(1, 64, 64)
    ctf_params = dict(
        defocus_u=torch.tensor([15000.0]),
        defocus_v=torch.tensor([14500.0]),
        astig_angle_deg=torch.tensor([0.0]),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )
    logL = per_particle_log_likelihood(coords, obs, R, t, ctf_params, D=64, apix=1.5)
    logL.sum().backward()
    assert coords.grad is not None
    assert torch.isfinite(coords.grad).all(), "gradients must be finite"
    g_norm = coords.grad.norm().item()
    print(f"  test_gradient_flows_to_coords: ✓  ‖∇‖={g_norm:.4f}")


def test_posterior_recovers_truth_from_two_conformer_prior():
    """Synthesize 200 particles from conformer A. With prior {A, B} the posterior must concentrate on A."""
    torch.manual_seed(0)
    A = make_helix_coords(40)
    B = A + 3.0 * torch.randn_like(A)

    D, apix = 64, 1.5
    n_particles = 200
    R = torch.eye(3).unsqueeze(0).expand(n_particles, -1, -1)
    t = torch.zeros(n_particles, 2)
    ctf_params = dict(
        defocus_u=torch.linspace(10000, 25000, n_particles),
        defocus_v=torch.linspace(9500, 24500, n_particles),
        astig_angle_deg=torch.zeros(n_particles),
        voltage_kV=300.0, cs_mm=2.0, amp_contrast=0.1,
    )
    obs = render_particle(
        A.unsqueeze(0).expand(n_particles, -1, -1), R, t,
        D=D, apix=apix, **ctf_params,
    )
    obs = obs + 0.02 * torch.randn_like(obs)

    log_likelihoods = []
    for conf in [A, B]:
        ll = per_particle_log_likelihood(conf, obs, R, t, ctf_params, D=D, apix=apix)
        log_likelihoods.append(ll)
    log_likelihoods = torch.stack(log_likelihoods, dim=0)    # (2, n_particles)
    posterior = aggregate_posterior(log_likelihoods)
    print(f"  posterior: A={posterior[0]:.4f}  B={posterior[1]:.4f}")
    assert posterior[0] > 0.95, "truth conformer should dominate the posterior"
    print(f"  test_posterior_recovers_truth_from_two_conformer_prior: ✓")


def main():
    print("[CryoEnsemble forward-model tests]\n")
    test_projection_nonempty()
    test_ctf_shape_and_symmetry()
    test_render_with_ctf()
    test_likelihood_ranks_correct_conformer()
    test_gradient_flows_to_coords()
    test_posterior_recovers_truth_from_two_conformer_prior()
    print("\nAll tests passed.")


if __name__ == "__main__":
    main()
