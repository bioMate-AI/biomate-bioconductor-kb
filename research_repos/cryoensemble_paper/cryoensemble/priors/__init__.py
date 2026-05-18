"""Generative-prior plug-in interface for CryoEnsemble.

Every supported prior implements `PriorAdapter`:

    sample(n, sequence, **kwargs)          # unconditional samples
    score(x, t=None)                       # ∇_x log p(x); may be Tweedie-approximated
    denoise(x_t, t)                        # one denoising step (optional, for true diffusion priors)
    metadata() -> dict                     # what the prior was trained on / type / limits

Subclasses:
    DeltaEnsemblePrior — wraps a fixed conformer set (Tang/Cossio reweighting baseline)
    BioemuPrior        — wraps Microsoft BioEmu, Tweedie-score
    AlphaflowPrior     — wraps AlphaFlow (Jing 2024), native velocity → score
    AF3SeedPrior       — wraps AlphaFold3 multi-seed inference
    MDSnapshotPrior    — wraps a fixed MD trajectory file
"""

from .base import PriorAdapter
from .delta import DeltaEnsemblePrior
from .alphaflow import (
    AlphaflowPrior,
    load_alphaflow_pool_from_outpdb,
    load_alphaflow_pool_from_tarball,
)

__all__ = [
    "PriorAdapter",
    "DeltaEnsemblePrior",
    "AlphaflowPrior",
    "load_alphaflow_pool_from_outpdb",
    "load_alphaflow_pool_from_tarball",
]
