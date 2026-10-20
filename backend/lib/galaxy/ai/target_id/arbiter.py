"""Arbiters: fuse channel evidence into a ranked, confidence-tiered target list.

Two arbiters, per the innovation-demonstration protocol:
  - EvidenceGateArbiter  : interpretable default — matched-null z per channel + OR/AND tiers
                           + per-target provenance. Always available (numpy only).
  - TabularArbiter       : the LEARNED ranker (GBDT / TabPFN) over the per-channel-z feature
                           matrix, trained on gold targets. This is the "more advanced but
                           still tabular" engine; a bespoke deep net is deliberately NOT the
                           default. Falls back to the gate when no model is fitted.

The VC / LLM / FM channels are just columns in the feature matrix — each must EARN lift
(linear-advantage) vs priors; the arbiter never privileges them. 3.9-safe.
"""
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

from . import evidence_gate as eg
from .types import ChannelResult, TargetScore


def _collect_per_channel_z(channel_results: List[ChannelResult], method="robust", baseline=0.0):
    """{channel: {target: z}} from the OK channels, z-scored over the UNION candidate universe.

    Each channel's raw scores are backfilled to ``baseline`` (default 0.0) for targets it did not
    score, then z-scored over that full universe. This is deliberate: a target absent from a
    channel's hit list is LOW evidence from that channel (not "unknown"), so a target that is a
    hit in two channels (and implicitly ~baseline in the rest) can corroborate. Without the
    backfill, a channel that only returns its top hits (e.g. OpenTargets associatedTargets, all
    high-scoring) would have nothing fire because its own hits cluster near their own median.
    """
    ok = [cr for cr in channel_results if cr.ok]
    universe = sorted({t for cr in ok for t in cr.scores})
    per_channel_z = {}
    for cr in ok:
        full = {t: float(cr.scores.get(t, baseline)) for t in universe}
        per_channel_z[cr.channel] = eg.channel_z(full, method=method)
    return per_channel_z


class Arbiter(ABC):
    name = "arbiter"

    @abstractmethod
    def rank(self, channel_results: List[ChannelResult], context: Dict[str, Any]) -> List[TargetScore]:
        raise NotImplementedError


class EvidenceGateArbiter(Arbiter):
    name = "evidence_gate"

    def __init__(self, z_thresh: float = 2.0, null_method: str = "robust"):
        self.z_thresh = z_thresh
        self.null_method = null_method

    def rank(self, channel_results: List[ChannelResult], context: Dict[str, Any]) -> List[TargetScore]:
        per_channel_z = _collect_per_channel_z(channel_results, method=self.null_method)
        evidence = eg.evidence_gate(per_channel_z, z_thresh=self.z_thresh)
        ranked = eg.rank_evidence(evidence)
        out = []
        for i, (target, ev) in enumerate(ranked):
            out.append(TargetScore(target=target, score=eg.gate_score(ev), tier=ev.tier, rank=i + 1, evidence=ev))
        return out


class TabularArbiter(Arbiter):
    """Learned tabular ranker over the per-channel-z feature matrix.

    model: any object with ``predict_proba(X)->[:,1]`` or ``predict(X)`` (e.g. a fitted
    LightGBM/XGBoost/CatBoost classifier, or TabPFN). If None/unfitted, delegates to the
    EvidenceGateArbiter so the system still ranks (honest fallback, never a fake score).
    ``feature_channels`` fixes the column order so train and inference match.
    """

    name = "tabular"

    def __init__(self, model: Any = None, feature_channels: Optional[List[str]] = None,
                 z_thresh: float = 2.0, null_method: str = "robust"):
        self.model = model
        self.feature_channels = feature_channels
        self._gate = EvidenceGateArbiter(z_thresh=z_thresh, null_method=null_method)
        self.null_method = null_method

    def feature_matrix(self, channel_results: List[ChannelResult]):
        """Return (targets, channels, X[np.ndarray]) — per-channel z, 0 where a channel is absent."""
        import numpy as np
        per_channel_z = _collect_per_channel_z(channel_results, method=self.null_method)
        channels = self.feature_channels or sorted(per_channel_z.keys())
        targets = sorted({t for d in per_channel_z.values() for t in d})
        X = np.zeros((len(targets), len(channels)), dtype=float)
        for j, ch in enumerate(channels):
            col = per_channel_z.get(ch, {})
            for i, t in enumerate(targets):
                X[i, j] = col.get(t, 0.0)
        return targets, channels, X

    def rank(self, channel_results: List[ChannelResult], context: Dict[str, Any]) -> List[TargetScore]:
        if self.model is None:
            # Honest fallback: no trained model yet -> interpretable gate ranking.
            out = self._gate.rank(channel_results, context)
            for t in out:
                t.evidence.per_channel_z = t.evidence.per_channel_z  # unchanged; marker for clarity
            return out
        import numpy as np
        targets, channels, X = self.feature_matrix(channel_results)
        if len(targets) == 0:
            return []
        try:
            if hasattr(self.model, "predict_proba"):
                y = np.asarray(self.model.predict_proba(X))[:, -1]
            else:
                y = np.asarray(self.model.predict(X), dtype=float)
        except Exception:
            # model failed -> fall back rather than crash the whole identification
            return self._gate.rank(channel_results, context)
        # Keep the gate's tier/provenance for interpretability, but rank by the learned score.
        evidence = eg.evidence_gate(_collect_per_channel_z(channel_results, method=self.null_method),
                                    z_thresh=self._gate.z_thresh)
        order = np.argsort(-y)
        out = []
        for rank, idx in enumerate(order):
            t = targets[idx]
            ev = evidence.get(t)
            if ev is None:
                from .types import TargetEvidence
                ev = TargetEvidence(target=t)
            out.append(TargetScore(target=t, score=float(y[idx]), tier=ev.tier, rank=rank + 1, evidence=ev))
        return out
