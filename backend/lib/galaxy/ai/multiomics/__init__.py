"""Flexible multi-omics integration intelligence layer.

BioMate's multi-omics *methods* (MOFA2, SNF, MCIA, intNMF, iClusterPlus, JIVE, MFA,
StabMap, ...) are Bioconductor/Nextflow subworkflows. This package is the layer that
makes them usable on *arbitrary* real data: inspect whatever modalities the user
brings, align samples (including partial-overlap / mosaic), pick the appropriate
integrator, and emit a per-modality normalization plan — so the user brings what they
have instead of choosing a method or running all of them.
"""

from .method_selector import (  # noqa: F401
    Modality,
    recommend,
    select_method,
    sample_alignment,
    normalization_plan,
    NORMALIZATION,
)

__all__ = [
    "Modality",
    "recommend",
    "select_method",
    "sample_alignment",
    "normalization_plan",
    "NORMALIZATION",
]
