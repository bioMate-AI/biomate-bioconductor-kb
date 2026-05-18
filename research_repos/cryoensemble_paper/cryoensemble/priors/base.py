"""Base class for generative-prior adapters.

Design principle: keep the surface area minimal so any pretrained protein structure
model — diffusion (RFdiffusion, AlphaFlow), flow-based (BioEmu, AlphaFlow),
autoregressive (AF3 multi-seed), or fixed-set MD trajectory — can be wrapped
behind the same API.

Two operating regimes for DPS (Diffusion Posterior Sampling):

(1) True diffusion priors → expose `denoise(x_t, t)` directly; DPS calls it.
(2) Sampler-only priors (BioEmu, AF3 multi-seed) → expose `sample(n)`; the DPS
    layer uses Tweedie's formula to approximate the score:
        ∇ log p(x_t) ≈ (E[x_0 | x_t] − x_t) / σ_t²
    where E[x_0 | x_t] is approximated by re-sampling and averaging.

Both regimes plug into the same DPS update loop.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

import torch


@dataclass
class PriorMetadata:
    name: str
    kind: str           # "fixed", "flow", "diffusion", "sampler"
    n_atoms: int
    trained_on: str     # e.g. "MD@300K", "PDB", "ColabFold-MSAs"
    notes: str = ""


class PriorAdapter(ABC):
    """Generative-prior interface for CryoEnsemble.

    All methods return PyTorch tensors. Coordinate convention:
    `(B, n_atoms, 3)` Cα coordinates in Å, *centered* at origin.
    """

    @abstractmethod
    def metadata(self) -> PriorMetadata:
        """Return descriptive metadata for logging & paper reporting."""

    @abstractmethod
    def sample(self, n: int, *, sequence: str | None = None, **kwargs) -> torch.Tensor:
        """Draw `n` unconditional samples from the prior.

        Returns
        -------
        (n, n_atoms, 3) Cα coordinates in Å.
        """

    # ── Score-based interface (DPS) ─────────────────────────────────────────────
    def score(
        self,
        x: torch.Tensor,
        t: torch.Tensor | float | None = None,
        n_mc: int = 8,
        **kwargs,
    ) -> torch.Tensor:
        """Return ∇_x log p_t(x). Default implementation: Tweedie estimate.

        For true diffusion priors that expose a denoiser, subclasses should override
        with the exact score. For sampler-only priors, the Tweedie default uses
        repeated sampling around `x` to estimate the conditional mean.

        Parameters
        ----------
        x : (B, n_atoms, 3) noisy coordinates
        t : noise level (sigma_t); broadcastable to B
        n_mc : Monte Carlo samples for Tweedie estimate when denoiser unavailable.

        Returns
        -------
        (B, n_atoms, 3) gradient.
        """
        if hasattr(self, "denoise") and callable(self.denoise):
            x0_hat = self.denoise(x, t)
        else:
            x0_hat = self._mc_denoise(x, t, n_mc=n_mc, **kwargs)
        sigma2 = self._sigma_t_sq(t)
        return (x0_hat - x) / sigma2

    def _mc_denoise(
        self,
        x: torch.Tensor,
        t: torch.Tensor | float | None,
        *,
        n_mc: int = 8,
        **kwargs,
    ) -> torch.Tensor:
        """Estimate E[x_0 | x_t] by sampling near x_t — for sampler-only priors."""
        with torch.no_grad():
            # draw n_mc unconditional samples (cheap reference), then take the one
            # closest to x as the conditional mean estimate. For better accuracy,
            # subclass-override with an explicit conditional sampler if available.
            B, A, _ = x.shape
            base = self.sample(max(n_mc, B), **kwargs).to(x.device)
            # naive: pick the closest base sample to each x[b] (no alignment)
            x_flat = x.reshape(B, -1)
            base_flat = base.reshape(base.shape[0], -1)
            d2 = torch.cdist(x_flat, base_flat)
            idx = d2.argmin(dim=-1)
            return base[idx]

    @staticmethod
    def _sigma_t_sq(t: torch.Tensor | float | None) -> torch.Tensor | float:
        if t is None:
            return 1.0
        if isinstance(t, float):
            return max(t * t, 1e-8)
        return (t * t).clamp_min(1e-8)

    # ── Convenience ────────────────────────────────────────────────────────────
    def __repr__(self):
        meta = self.metadata()
        return f"{meta.name}(kind={meta.kind}, n_atoms={meta.n_atoms}, on={meta.trained_on})"


__all__ = ["PriorAdapter", "PriorMetadata"]
