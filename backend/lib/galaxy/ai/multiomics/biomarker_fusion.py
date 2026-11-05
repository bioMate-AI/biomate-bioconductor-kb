"""Cross-omics biomarker-driver ranking (the scoring step that makes the general
fusion engine usable end-to-end).

After multi-omics integration assigns patients to subtypes (e.g. the SNF run in
``snf_multiomics/main.nf``), the clinical question is *which features drive the
subtypes, corroborated across layers?* ``evidence_fusion.fuse_omics_biomarkers``
answers the fusion half, but it needs a per-layer ``{feature: score}`` — the
evidence each layer gives that a feature separates the subtypes. Nothing computed
that score, so the fusion engine was dormant for multi-omics. This module supplies
it: per layer, per feature, a one-way ANOVA **F-statistic** of the feature's values
across the subtype labels (between-subtype variance / within-subtype variance;
higher = more discriminative), then hands the per-layer score maps to
``fuse_omics_biomarkers`` → ``target_id.arbiter.fuse_channels`` — the SAME engine
target-ID uses, now exercised on a second, independent problem.

Serves the SYSUCC/faculty stratification spearhead: subtype a cohort by multi-omics,
then name the RNA/protein/methylation drivers that agree across layers.

3.9-safe; numpy only (imported lazily so the module loads without it).
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Sequence

from .evidence_fusion import fuse_omics_biomarkers

log = logging.getLogger(__name__)


# A parsed layer matrix: feature names, sample names, and a features x samples grid.
LayerMatrix = Dict[str, Any]   # {"features": [str], "samples": [str], "values": [[float]]}


def _f_statistic_per_feature(
    values: Sequence[Sequence[float]],
    sample_names: Sequence[str],
    labels: Dict[str, Any],
) -> List[float]:
    """One-way ANOVA F per feature across the subtype labels of the given samples.

    ``values`` is features x samples (same column order as ``sample_names``).
    Features with no within-group spread or a single populated group get F=0
    (uninformative), never NaN/inf — so a flat/ID column contributes no evidence.
    """
    import numpy as np

    X = np.asarray(values, dtype=float)                       # features x samples
    if X.ndim != 2 or X.shape[1] != len(sample_names):
        raise ValueError("values must be features x samples matching sample_names")
    grp = np.array([str(labels.get(s, "")) for s in sample_names])
    groups = [g for g in sorted(set(grp)) if g != ""]
    # Column masks per group (samples with a known subtype label).
    masks = [grp == g for g in groups]
    n_total = int(sum(int(m.sum()) for m in masks))
    out: List[float] = []
    for row in X:
        present = [row[m] for m in masks if m.sum() > 0]
        k = len(present)
        if k < 2 or n_total <= k:
            out.append(0.0)
            continue
        grand = float(np.concatenate(present).mean())
        ss_between = sum(len(g) * (float(g.mean()) - grand) ** 2 for g in present)
        ss_within = sum(float(((g - g.mean()) ** 2).sum()) for g in present)
        df_between = k - 1
        df_within = n_total - k
        if ss_within <= 0 or df_within <= 0:
            # No within-group variance → perfectly separable; cap to a large but
            # finite F so it ranks high without poisoning the null with inf.
            out.append(1e6 if ss_between > 0 else 0.0)
            continue
        f = (ss_between / df_between) / (ss_within / df_within)
        out.append(float(f) if f == f and f != float("inf") else 0.0)  # NaN/inf guard
    return out


def rank_cross_omics_drivers(
    layer_matrices: Dict[str, LayerMatrix],
    cluster_labels: Dict[str, Any],
    *,
    method: str = "evidence_gate",
    weights: Optional[Dict[str, float]] = None,
    top_k: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Rank features that drive the subtypes, corroborated across omics layers.

    layer_matrices: ``{layer_name: {"features": [...], "samples": [...],
        "values": [[float] features x samples]}}`` — one parsed matrix per layer
        (same contract the SNF ``.nf`` reads: features x samples).
    cluster_labels: ``{sample: subtype}`` — e.g. the ``snf_clusters.csv`` output.
    method/weights/top_k: passed through to the fusion engine (see
        ``evidence_fusion.fuse_omics_biomarkers``).

    Returns the fused ranking: ranked dicts with ``entity`` (=feature), ``score``,
    ``tier`` (corroborated >=2 layers / nominated / none), ``n_fired``,
    ``fired_channels`` (the layers that nominated it). A feature strong in two
    layers outranks one strong in a single layer, because the engine calibrates
    each layer against its own null before gating.
    """
    per_layer_scores: Dict[str, Dict[str, float]] = {}
    for layer, mat in (layer_matrices or {}).items():
        feats = list(mat.get("features") or [])
        samples = list(mat.get("samples") or [])
        values = mat.get("values") or []
        if not feats or not samples:
            continue
        fvals = _f_statistic_per_feature(values, samples, cluster_labels)
        per_layer_scores[str(layer)] = {f: fvals[i] for i, f in enumerate(feats)}
    if not per_layer_scores:
        return []
    log.info("[multiomics] cross-omics biomarker fusion over %d layers (%s)",
             len(per_layer_scores), ", ".join(per_layer_scores))
    return fuse_omics_biomarkers(per_layer_scores, method=method, weights=weights, top_k=top_k)
