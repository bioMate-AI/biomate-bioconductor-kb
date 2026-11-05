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

import csv
import logging
import os
from typing import Any, Callable, Dict, List, Optional, Sequence

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


# ── Findings-hook orchestration: (cluster output + omics inputs) -> drivers ──────

def _parse_cluster_csv(text: str) -> Dict[str, Any]:
    """Parse a subtype/cluster assignment CSV into ``{sample: cluster}``.

    Accepts the SNF output (`snf_clusters.csv`: sample,cluster) and the generic
    `patient_stratification.csv`; tolerant of header aliases and quoting.
    """
    rows = list(csv.reader(text.splitlines()))
    rows = [r for r in rows if r]
    if not rows:
        return {}
    header = [h.strip().strip('"').lower() for h in rows[0]]
    def _idx(cands, default):
        for c in cands:
            if c in header:
                return header.index(c)
        return default
    s_i = _idx(["sample", "sample_id", "id", "patient", "barcode"], 0)
    c_i = _idx(["cluster", "subtype", "group", "label", "assignment"], 1 if len(header) > 1 else 0)
    out: Dict[str, Any] = {}
    for r in rows[1:]:
        if len(r) <= max(s_i, c_i):
            continue
        samp = r[s_i].strip().strip('"')
        clus = r[c_i].strip().strip('"')
        if samp and clus:
            out[samp] = clus
    return out


def _parse_feature_matrix(text: str) -> LayerMatrix:
    """Parse a features x samples CSV/TSV (col 1 = feature IDs, header = sample IDs)
    into ``{features, samples, values}`` — the same contract the SNF .nf reads."""
    sniff = text.splitlines()[:1]
    sep = "\t" if (sniff and "\t" in sniff[0] and "," not in sniff[0]) else ","
    rows = [r for r in csv.reader(text.splitlines(), delimiter=sep) if r]
    if len(rows) < 2:
        return {"features": [], "samples": [], "values": []}
    samples = [c.strip().strip('"') for c in rows[0][1:]]
    features: List[str] = []
    values: List[List[float]] = []
    for r in rows[1:]:
        features.append(r[0].strip().strip('"'))
        row = []
        for v in r[1:1 + len(samples)]:
            try:
                row.append(float(v))
            except (TypeError, ValueError):
                row.append(float("nan"))
        row += [float("nan")] * (len(samples) - len(row))
        values.append(row)
    return {"features": features, "samples": samples, "values": values}


def drivers_from_run(
    cluster_csv_text: str,
    omics_uris: Sequence[str],
    *,
    fetch_text: Optional[Callable[[str], str]] = None,
    top_k: Optional[int] = 25,
) -> List[Dict[str, Any]]:
    """Compute cross-omics biomarker drivers for a completed stratification run.

    cluster_csv_text: contents of the run's cluster/subtype CSV (e.g. snf_clusters.csv).
    omics_uris: the run's input layer matrices (``parameters.omics`` — s3://… or local);
        the layer name is each file's basename stem (rna.csv -> "rna").
    fetch_text: reads a URI to text; defaults to local read, else S3 via the AWS CLI
        staging helper (injectable so this is unit-testable with no network).

    Returns the fused driver ranking (see ``rank_cross_omics_drivers``), or ``[]`` when
    there are fewer than two usable layers or no labels.
    """
    labels = _parse_cluster_csv(cluster_csv_text or "")
    if not labels or not omics_uris:
        return []

    def _default_fetch(uri: str) -> str:
        if uri.startswith("s3://"):
            # Backend-native read (boto3 is present in the Galaxy backend); fall back
            # to the AWS-CLI staging helper (present in the ml-training image).
            try:
                import boto3  # type: ignore
                _, _, rest = uri.partition("s3://")
                bucket, _, key = rest.partition("/")
                obj = boto3.client("s3").get_object(Bucket=bucket, Key=key)
                return obj["Body"].read().decode("utf-8", "replace")
            except Exception:
                from .datasets import stage_s3_to_local
                local = stage_s3_to_local(uri)
                with open(local) as fh:
                    return fh.read()
        with open(uri) as fh:
            return fh.read()

    reader = fetch_text or _default_fetch
    layer_matrices: Dict[str, LayerMatrix] = {}
    for uri in omics_uris:
        name = os.path.splitext(os.path.basename(str(uri)))[0] or str(uri)
        try:
            layer_matrices[name] = _parse_feature_matrix(reader(str(uri)))
        except Exception as exc:  # best-effort per layer — a bad layer must not sink the rest
            log.warning("[multiomics] driver fusion: could not read layer %s (%s): %s",
                        name, uri, exc)
    if len(layer_matrices) < 2:
        return []
    return rank_cross_omics_drivers(layer_matrices, labels, top_k=top_k)
