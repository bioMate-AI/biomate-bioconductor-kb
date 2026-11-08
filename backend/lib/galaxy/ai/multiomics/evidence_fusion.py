"""Cross-omics biomarker evidence fusion.

A REAL second consumer of the general fusion engine (`target_id.arbiter.fuse_channels`),
which turns Pattern A ("general core, single consumer") into exercised generality: the
fusion math was previously reached only through target identification. Here each omics
layer contributes a channel of ``{feature: score}``, and the engine calibrates each layer
against its own null, then gates/aggregates — so features that are consistently strong
*across* layers surface as corroborated.

Serves the SYSUCC/faculty stratification spearhead's biomarker step: after multi-omics
integration subtypes patients, "which genes/proteins drive the subtypes across RNA,
protein and methylation?" is exactly a multi-source evidence-fusion question.

3.9-safe; pure-Python layer over the arbiter (numpy via the arbiter only).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from galaxy.ai.target_id.arbiter import fuse_channels


def fuse_omics_biomarkers(
    per_layer_scores: Dict[str, Dict[str, float]],
    *,
    method: str = "evidence_gate",
    weights: Optional[Dict[str, float]] = None,
    top_k: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Rank features corroborated across omics layers.

    per_layer_scores: ``{layer_name: {feature: score}}`` — one dict per omics layer
        (e.g. ``{"rna": {gene: -log10(padj)*sign, ...}, "proteomics": {...}, "methylation": {...}}``).
        Higher score = stronger evidence from that layer; a feature absent from a layer is
        treated as low (not unknown) evidence, so cross-layer corroboration is possible.
    method:  ``"evidence_gate"`` (prior-free z-gate) or ``"harmonic_sum"`` (weighted).
    weights: optional per-layer reliability ``{layer: w in [0,1]}`` for harmonic_sum
        (e.g. down-weight a noisier layer).
    Returns ranked dicts ``{entity (=feature), score, tier, rank, n_fired (=#layers that
    fired), fired_channels (=the layers), per_channel_z}``. ``tier`` = corroborated
    (>=2 layers), nominated (1), or none.
    """
    channels = [(str(layer), dict(scores)) for layer, scores in (per_layer_scores or {}).items()]
    return fuse_channels(channels, method=method, weights=weights, top_k=top_k)
