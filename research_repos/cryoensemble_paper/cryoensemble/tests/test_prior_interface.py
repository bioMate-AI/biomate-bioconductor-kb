"""Smoke tests for the PriorAdapter interface."""

from __future__ import annotations

import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cryoensemble.priors import DeltaEnsemblePrior


def test_delta_prior_metadata_and_sample():
    confs = torch.randn(8, 50, 3)
    p = DeltaEnsemblePrior(confs, name="test")
    meta = p.metadata()
    assert meta.name == "test"
    assert meta.kind == "fixed"
    assert meta.n_atoms == 50
    s = p.sample(20)
    assert s.shape == (20, 50, 3)
    print(f"  test_delta_prior_metadata_and_sample: ✓  metadata={meta}")


def test_delta_prior_score_shape_and_attractor():
    """Score at a conformer should attract to nearby conformers; score at a
    far-away point should be huge in magnitude pulling toward the prior support.
    """
    torch.manual_seed(0)
    confs = torch.randn(4, 30, 3) * 5.0
    p = DeltaEnsemblePrior(confs)
    # At one of the conformers: score should point ~zero (small perturbation only)
    x = confs[0:1].clone()
    g = p.score(x)
    assert g.shape == x.shape
    # At a random point far from any conformer: gradient should have significant magnitude
    x_far = torch.randn_like(x) * 100.0
    g_far = p.score(x_far)
    assert g_far.norm() > g.norm()
    print(f"  test_delta_prior_score_shape_and_attractor: ✓  ‖∇_near‖={g.norm():.3e}, ‖∇_far‖={g_far.norm():.3e}")


def test_delta_score_pulls_toward_nearest_conformer():
    """Sanity: if a single conformer dominates the posterior, the score should
    pull x toward it. NB: DeltaEnsemblePrior centres its stored conformers, so
    `x` must also be centred (or use p.conformers[i] as the reference).
    """
    torch.manual_seed(1)
    confs = torch.zeros(2, 20, 3)
    confs[0] = torch.randn(20, 3)
    confs[1] = confs[0] + torch.randn(20, 3) * 50   # very far apart
    p = DeltaEnsemblePrior(confs, kernel_sigma=0.5)
    # Start near centred conformer 0 → score should pull toward C0
    x = p.conformers[0:1].clone() + 0.01 * torch.randn(1, 20, 3)
    g = p.score(x)
    pull_dir = p.conformers[0] - x[0]
    cos = torch.nn.functional.cosine_similarity(g.flatten(), pull_dir.flatten(), dim=0)
    assert cos > 0.99, f"score should point toward nearest conformer; cos={cos:.3f}"
    print(f"  test_delta_score_pulls_toward_nearest_conformer: ✓  cos(score, C0-x)={cos:.4f}")


def main():
    print("[PriorAdapter smoke tests]\n")
    test_delta_prior_metadata_and_sample()
    test_delta_prior_score_shape_and_attractor()
    test_delta_score_pulls_toward_nearest_conformer()
    print("\nAll tests passed.")


if __name__ == "__main__":
    main()
