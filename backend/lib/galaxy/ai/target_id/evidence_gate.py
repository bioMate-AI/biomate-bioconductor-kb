"""Evidence-gate calibration + fusion (ported, product-side).

Each channel's raw scores are z-scored against a null, then a target FIRES on a channel
when z >= z_thresh. OR-nominate (>=1 fired, recall) vs AND-corroborate (>=2 fired, precision)
yields a confidence tier, with a per-target auditable breakdown. Mirrors the research
``knowledge_channels.evidence_gate`` (OR/AND tiers, matched-null z) but self-contained here.

v1 null = robust median/MAD z (fast, deterministic). A matched **permutation** null
(value/degree-binned) is the pre-registered v2 upgrade; ``channel_z(..., method=...)`` is the
seam for it. numpy-only; no galaxy imports.
"""
import math
from typing import Dict

from .types import TargetEvidence

Z_CAP = 12.0


def channel_z(scores, cap=Z_CAP, method="robust"):
    """Calibrate one channel's raw scores to z vs a null. Returns {target: z}.

    method="robust": z = (x - median) / (1.4826 * MAD), clipped to +/-cap; falls back to
    std when MAD is degenerate. (method="permutation" is a reserved v2 hook — not yet
    implemented; raising keeps us honest rather than silently returning a different null.)
    """
    import numpy as np
    if not scores:
        return {}
    if method != "robust":
        raise NotImplementedError(
            "channel_z: only method='robust' is implemented in v1; "
            "matched-permutation null is the pre-registered v2 upgrade"
        )
    keys = list(scores)
    vals = np.asarray([float(scores[k]) for k in keys], dtype=float)
    med = float(np.median(vals))
    mad = float(np.median(np.abs(vals - med)))
    scale = 1.4826 * mad
    if scale < 1e-9:
        std = float(vals.std())
        scale = std if std > 1e-9 else 1.0
    z = np.clip((vals - med) / scale, -cap, cap)
    return {k: float(zz) for k, zz in zip(keys, z)}


def evidence_gate(per_channel_z, z_thresh=2.0):
    """Fuse per-channel z into per-target TargetEvidence (OR/AND confidence tiers).

    per_channel_z: {channel_name: {target: z}}. Returns {target: TargetEvidence}.
    """
    targets = set()
    for d in per_channel_z.values():
        targets.update(d.keys())
    out = {}
    for t in targets:
        present = {ch: d[t] for ch, d in per_channel_z.items() if t in d}
        fired = [ch for ch, z in present.items() if z >= z_thresh]
        zs = [present[ch] for ch in fired]
        n = len(fired)
        tier = "corroborated" if n >= 2 else ("nominated" if n >= 1 else "none")
        out[t] = TargetEvidence(
            target=t,
            per_channel_z=present,
            fired_channels=sorted(fired, key=lambda c: -present[c]),
            n_fired=n,
            tier=tier,
            max_z=max(present.values()) if present else 0.0,
            mean_fired_z=(sum(zs) / n if n else 0.0),
        )
    return out


def gate_score(ev):
    """Scalar rank key within a tier: n_fired + tanh(mean_fired_z / 5). 0 if nothing fired."""
    if ev.n_fired == 0:
        return 0.0
    return ev.n_fired + math.tanh(ev.mean_fired_z / 5.0)


_TIER_RANK = {"corroborated": 2, "nominated": 1, "none": 0}


def rank_evidence(evidence):
    """Order targets by (tier, gate_score) descending. Returns a list of (target, TargetEvidence)."""
    items = list(evidence.items())
    items.sort(key=lambda kv: (_TIER_RANK.get(kv[1].tier, 0), gate_score(kv[1])), reverse=True)
    return items
