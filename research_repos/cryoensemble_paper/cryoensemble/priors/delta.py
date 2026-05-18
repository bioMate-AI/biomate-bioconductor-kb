"""DeltaEnsemblePrior — wraps a fixed conformer set as a "delta" prior.

This is the prior used by reweighting baselines (Tang/Cossio 2023). The prior
distribution is a uniform mixture of delta functions at the given conformers,
so `sample` returns elements drawn from the fixed pool. `score` is undefined
(deltas are non-differentiable); we approximate via a smooth kernel for DPS
compatibility, but the recommended use is reweighting (no DPS step).

Use cases:
  1. Re-implementing per-particle reweighting (Tang/Cossio).
  2. Wrapping any externally-generated ensemble (MD trajectory, BioEmu samples
     saved to disk, AlphaFlow output) so the experiment harness can swap priors.
"""

from __future__ import annotations

import torch

from .base import PriorAdapter, PriorMetadata


class DeltaEnsemblePrior(PriorAdapter):
    """Fixed conformer set treated as a delta prior."""

    def __init__(
        self,
        conformers: torch.Tensor,        # (N, n_atoms, 3)
        *,
        name: str = "delta",
        trained_on: str = "external",
        weights: torch.Tensor | None = None,
        kernel_sigma: float = 0.3,       # for smooth-score fallback if DPS used
    ):
        if conformers.ndim != 3 or conformers.shape[-1] != 3:
            raise ValueError(f"conformers must be (N, n_atoms, 3); got {tuple(conformers.shape)}")
        self.conformers = conformers - conformers.mean(dim=1, keepdim=True)
        self._weights = (
            weights / weights.sum()
            if weights is not None
            else torch.full((conformers.shape[0],), 1.0 / conformers.shape[0])
        )
        self.kernel_sigma = float(kernel_sigma)
        self._meta = PriorMetadata(
            name=name,
            kind="fixed",
            n_atoms=int(conformers.shape[1]),
            trained_on=trained_on,
            notes="delta prior over fixed conformer pool",
        )

    # ── Interface ──────────────────────────────────────────────────────────────

    def metadata(self) -> PriorMetadata:
        return self._meta

    def sample(self, n: int, **kwargs) -> torch.Tensor:
        idx = torch.multinomial(self._weights, n, replacement=True)
        return self.conformers[idx].clone()

    def score(self, x: torch.Tensor, t=None, **kwargs) -> torch.Tensor:
        """Smooth-kernel approximation to the score of a discrete prior.

        Density: p(x) = Σ_i w_i (2πσ²)^{-3A/2} exp(-‖x-C_i‖²/(2σ²))
        where σ is the per-coordinate kernel bandwidth in Å and ‖·‖² is the
        full L2 norm over all 3A coordinates.

        Score:
            ∇_x log p(x) = (1/σ²) · Σ_i r_i(x) (C_i - x)
        with r_i(x) ∝ w_i exp(-‖x-C_i‖²/(2σ²)) (softmax over conformers).
        """
        B, A, _ = x.shape
        C = self.conformers.to(x.device, dtype=x.dtype)             # (N, A, 3)
        sigma = self.kernel_sigma
        diff = x.unsqueeze(1) - C.unsqueeze(0)                       # (B, N, A, 3)
        d2 = (diff ** 2).sum(dim=(-2, -1))                           # (B, N)
        w = self._weights.to(x.device, dtype=x.dtype)
        # NB: d2 spans a 3A-dim space; use sigma as the per-coordinate scale
        # directly (no extra normalization). This is the standard isotropic-
        # Gaussian KDE score formula.
        log_unnorm = torch.log(w + 1e-30) - d2 / (2 * sigma * sigma)
        log_norm = torch.logsumexp(log_unnorm, dim=-1, keepdim=True) # (B, 1)
        resp = torch.exp(log_unnorm - log_norm)                      # (B, N)
        grad = (resp.unsqueeze(-1).unsqueeze(-1) * (C.unsqueeze(0) - x.unsqueeze(1))).sum(dim=1)
        return grad / (sigma * sigma)


__all__ = ["DeltaEnsemblePrior"]
