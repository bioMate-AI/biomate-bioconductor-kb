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
    NaN-aware: each group is summarized over its present (finite) values, so one
    missing cell does not zero a feature. A single populated group → F=0.

    LIMITATION (perfectly-separable features, ``ss_within≈0``): the F-statistic is
    then formally +∞ regardless of effect size, so there is no canonical finite
    ordering among such features. We regularize the denominator with a small floor
    (``1e-9·(|grand mean|+1)²``) to keep F finite and give SOME ordering — but for
    equal-separation features of different offset, a mean-centered feature (grand≈0)
    scores higher than an offset one, which is a heuristic, not a true effect-size
    ranking. Mitigation: standardize features per layer upstream (so magnitudes are
    comparable and ``ss_within`` is rarely exactly 0); the EvidenceGate also
    robust-z-scores each layer's F distribution downstream, which normalizes within a
    layer. Continuous omics with real within-group noise never hit this path. (A
    variance/``ss_between``-scaled floor was considered and rejected: it collapses all
    perfectly-separable features to one constant F — worse than the current ordering.)
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
        # NaN-aware: use each group's PRESENT (finite) values. A single missing/
        # non-numeric cell must not zero the whole feature — real omics matrices are
        # sparse, and the SNF .nf mean-imputes, so dropping-on-NaN also disagreed with it.
        present = [g[np.isfinite(g)] for g in (row[m] for m in masks)]
        present = [g for g in present if g.size > 0]
        k = len(present)
        n_tot = int(sum(g.size for g in present))
        if k < 2 or n_tot <= k:
            out.append(0.0)
            continue
        grand = float(np.concatenate(present).mean())
        ss_between = sum(g.size * (float(g.mean()) - grand) ** 2 for g in present)
        ss_within = sum(float(((g - g.mean()) ** 2).sum()) for g in present)
        df_between = k - 1
        df_within = n_tot - k
        # Regularize the within-group variance with a tiny magnitude-scaled floor so a
        # PERFECTLY separable feature (ss_within≈0 — e.g. binarized methylation / a
        # label re-encoding) still orders by EFFECT SIZE (ss_between) instead of every
        # such feature saturating one flat cap (which erased effect size — Reviewer F2).
        denom = max(ss_within / df_within, 1e-9 * (abs(grand) + 1.0) ** 2)
        f = (ss_between / df_between) / denom
        out.append(float(f) if np.isfinite(f) else 0.0)
    return out


def _score_and_fuse(layer_matrices, labels, method, weights, top_k):
    """Per-layer F-stat scoring + fusion for one labelling. Returns ranked dicts."""
    per_layer_scores: Dict[str, Dict[str, float]] = {}
    for layer, mat in (layer_matrices or {}).items():
        feats = list(mat.get("features") or [])
        samples = list(mat.get("samples") or [])
        values = mat.get("values") or []
        if not feats or not samples:
            continue
        fvals = _f_statistic_per_feature(values, samples, labels)
        per_layer_scores[str(layer)] = {f: fvals[i] for i, f in enumerate(feats)}
    if not per_layer_scores:
        return []
    return fuse_omics_biomarkers(per_layer_scores, method=method, weights=weights, top_k=top_k)


def rank_cross_omics_drivers(
    layer_matrices: Dict[str, LayerMatrix],
    cluster_labels: Dict[str, Any],
    *,
    method: str = "evidence_gate",
    weights: Optional[Dict[str, float]] = None,
    top_k: Optional[int] = None,
    n_perm: int = 0,
    alpha: float = 0.05,
    perm_seed: int = 0,
) -> List[Dict[str, Any]]:
    """Rank features that drive the subtypes, corroborated across omics layers.

    layer_matrices: ``{layer_name: {"features": [...], "samples": [...],
        "values": [[float] features x samples]}}`` — one parsed matrix per layer
        (same contract the SNF ``.nf`` reads: features x samples).
    cluster_labels: ``{sample: subtype}`` — e.g. the ``snf_clusters.csv`` output.
    method/weights/top_k: passed through to the fusion engine (see
        ``evidence_fusion.fuse_omics_biomarkers``).
    n_perm: if >0, run a label-permutation significance test (the EvidenceGate TIER
        is a relative-tail triage, not a significance test — on random labels it still
        "corroborates" each layer's top tail, so a null-aware cutoff is required before
        CLAIMING a driver). Shuffles the labels ``n_perm`` times, builds the null of the
        **max** fused score per permutation (family-wise / max-statistic control), and
        annotates each returned driver with ``perm_p`` (empirical p vs that null) and
        ``significant`` (``score`` beats the ``1-alpha`` null quantile). Default 0 keeps
        the fast triage behaviour (what the per-run findings hook uses).

    Returns the fused ranking: ranked dicts with ``entity`` (=feature), ``score``,
    ``tier`` (corroborated >=2 layers / nominated / none), ``n_fired``,
    ``fired_channels`` (+ ``perm_p``/``significant`` when ``n_perm>0``). A feature
    strong in two layers outranks one strong in a single layer, because the engine
    calibrates each layer against its own null before gating.
    """
    results = _score_and_fuse(layer_matrices, cluster_labels, method, weights, top_k)
    if not results:
        return []
    log.info("[multiomics] cross-omics biomarker fusion over %d layers (perm=%d)",
             len(layer_matrices or {}), n_perm)
    if n_perm and n_perm > 0:
        import random as _random
        base = list(cluster_labels.keys())
        vals = [cluster_labels[s] for s in base]
        rng = _random.Random(perm_seed)
        null_max: List[float] = []
        for _ in range(int(n_perm)):
            shuf = vals[:]
            rng.shuffle(shuf)
            prs = _score_and_fuse(layer_matrices, dict(zip(base, shuf)),
                                  method, weights, None)
            null_max.append(max((float(r.get("score", 0.0)) for r in prs), default=0.0))
        for r in results:
            sc = float(r.get("score", 0.0))
            ge = sum(1 for m in null_max if m >= sc)
            p = (ge + 1) / (int(n_perm) + 1)                 # +1 smoothing (never 0)
            r["perm_p"] = p
            # Significance = the smoothed empirical p clears alpha. This is the
            # Westfall-Young maxT decision and is consistent with the reported
            # perm_p (a separate quantile threshold could disagree at small n_perm
            # where min achievable p = 1/(n_perm+1) > alpha — Reviewer F6).
            r["significant"] = p <= alpha
    return results


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
    n_perm: int = 0,
    alpha: float = 0.05,
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
                from galaxy.ai.ml_training.datasets import stage_s3_to_local
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
    return rank_cross_omics_drivers(layer_matrices, labels, top_k=top_k,
                                    n_perm=n_perm, alpha=alpha)
