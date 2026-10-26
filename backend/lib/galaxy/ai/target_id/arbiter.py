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


# Per-source reliability weights (general priors, NOT eval-tuned) — the Open Targets precedent of
# down-weighting noisy sources (raw text-mining 0.2, etc.). Curated genetics/essentiality = 1.0; network/
# pathway guilt-by-association = 0.5; raw literature text-mining = 0.2; unknown (e.g. a frozen FM on
# probation) = 0.7. Override per-call via channel_weights. See
# benchmarks/evidence_ranking_refs/EVIDENCE_RANKING_SCHEMES.md.
# llm_reasoned re-tiered 0.2 -> 0.5 (2026-10-25): a frontier-LLM structured target assessment is a real
# evidence channel, not raw text-mining — it was the STRONGEST single channel (lifts the fusion 9/10
# immune diseases) in docs/20261025_TARGETID_LLM_CHANNEL_CONTRIBUTION.md. Principled re-tiering to the
# network/pathway tier, corroborated (not fit) by that benchmark; still below curated genetics (1.0).
DEFAULT_RELIABILITY = {
    "genetics_ot": 1.0, "table": 1.0, "depmap": 1.0, "clin": 1.0,
    "ppi_string": 0.5, "pathway_comembership": 0.5,
    "llm_reasoned": 0.5,
}
_DEFAULT_UNKNOWN_WEIGHT = 0.7


def _to_unit(scores):
    """Map a channel's raw scores to [0,1]. Already-[0,1] scores (OpenTargets, STRING, LLM) pass
    through; others (pathway counts, z-scores) are min-maxed. Returns {target: s in [0,1]}."""
    import numpy as np
    if not scores:
        return {}
    vals = np.asarray(list(scores.values()), dtype=float)
    lo, hi = float(vals.min()), float(vals.max())
    if 0.0 <= lo and hi <= 1.0:
        return {k: float(v) for k, v in scores.items()}        # already calibrated — consume as-is
    rng = hi - lo
    if rng < 1e-12:
        v = 1.0 if hi > 0 else 0.0
        return {k: v for k in scores}
    return {k: (float(v) - lo) / rng for k, v in scores.items()}


class HarmonicSumArbiter(Arbiter):
    """Open Targets weighted-harmonic-sum aggregation + convergence/conflict flag + veto hook.

    THE adopted open-source scheme (replaces the binary gate as default; see
    benchmarks/evidence_ranking_refs/EVIDENCE_RANKING_SCHEMES.md):
      - consume each channel's [0,1] score (don't recompute; min-max only non-[0,1] channels),
        multiply by a per-source RELIABILITY WEIGHT (OT precedent; noisy sources down-weighted),
      - per target: sort the weighted scores desc and take Sum(s_i / i^2), normalised by Sum(1/i^2)
        over the channels present -> [0,1]. Monotonic: a channel strong in one source is never
        dragged BELOW its own evidence by a weak/absent source (the averaging-drag the gate hit),
      - convergence TIER: >=2 channels strong -> corroborated; 1 -> nominated; 0 -> none,
      - CONFLICT flag: exactly one strong channel while others are present-but-weak (disagreement),
      - VETO hook: optional callable(target, context)->bool to hard-cap a target (Pharos-TDL-style
        lexicographic safety/essentiality liability) regardless of score.
    """

    name = "harmonic_sum"

    def __init__(self, channel_weights=None, strong_thresh: float = 0.5, veto=None,
                 primary_channel: Optional[str] = None):
        self.channel_weights = dict(DEFAULT_RELIABILITY)
        if channel_weights:
            self.channel_weights.update(channel_weights)
        self.strong_thresh = strong_thresh
        self.veto = veto
        # HONEST DEFAULT (2026-10-21, benchmark_multidisease.py): the multi-channel fusion does NOT beat the
        # single strongest channel (OpenTargets) across 17 diseases — expansion dilutes, corroboration ties.
        # So when ``primary_channel`` is set, ranking is BY THAT CHANNEL ALONE (never worse than it); the
        # other channels only ANNOTATE each primary candidate with corroboration/conflict + provenance. We
        # surface OpenTargets well + show agreement across sources; we do NOT claim the fusion out-ranks OT.
        self.primary_channel = primary_channel

    def _weight(self, channel: str) -> float:
        return float(self.channel_weights.get(channel, _DEFAULT_UNKNOWN_WEIGHT))

    def rank(self, channel_results: List[ChannelResult], context: Dict[str, Any]) -> List[TargetScore]:
        from .types import TargetEvidence
        ok = [cr for cr in channel_results if cr.ok]
        unit = {cr.channel: _to_unit(cr.scores) for cr in ok}
        # OT-PRIMARY mode: rank only the primary channel's candidates, by its score (== that channel's own
        # ranking), using the rest purely as corroboration annotation. Guarantees we never rank worse than OT.
        if self.primary_channel and self.primary_channel in unit:
            prim = unit[self.primary_channel]
            rows = []
            for t in sorted(prim):
                per = {ch: unit[ch].get(t, 0.0) for ch in unit}
                strong = [ch for ch, s in per.items() if s >= self.strong_thresh]
                present = [ch for ch, s in per.items() if s > 0]
                corrob = [ch for ch in strong if ch != self.primary_channel]
                tier = "corroborated" if (self.primary_channel in strong and corrob) else (
                    "nominated" if self.primary_channel in strong else "supporting")
                conflict = bool(self.primary_channel in strong and not corrob and len(present) > 1)
                ev = TargetEvidence(
                    target=t, per_channel_z={ch: round(s, 4) for ch, s in per.items() if s > 0},
                    fired_channels=strong, n_fired=len(strong), tier=tier,
                    max_z=max(per.values()) if per else 0.0,
                    mean_fired_z=(sum(per[c] for c in strong) / len(strong) if strong else 0.0),
                    conflict=conflict,
                    note=("ranked by %s; corroborated by %s" % (self.primary_channel, ",".join(corrob)))
                    if corrob else ("ranked by %s (no independent corroboration)" % self.primary_channel),
                )
                score = prim[t]
                if self.veto is not None:
                    try:
                        if self.veto(t, context or {}):
                            ev.tier = "vetoed"; ev.note = "hard veto (safety/essentiality liability)"; score = 0.0
                    except Exception:
                        pass
                rows.append((t, float(score), ev))
            rows.sort(key=lambda r: -r[1])
            return [TargetScore(target=t, score=s, tier=ev.tier, rank=i + 1, evidence=ev)
                    for i, (t, s, ev) in enumerate(rows)]
        universe = sorted({t for cr in ok for t in cr.scores})
        rows = []
        for t in universe:
            per = {cr.channel: unit[cr.channel].get(t, 0.0) for cr in ok}          # [0,1] per channel
            weighted = sorted(((ch, self._weight(ch) * s, s) for ch, s in per.items()), key=lambda x: -x[1])
            num = sum(w / ((i + 1) ** 2) for i, (_, w, _) in enumerate(weighted))
            den = sum(1.0 / ((i + 1) ** 2) for i in range(len(weighted))) or 1.0
            score = num / den
            strong = [ch for ch, _, s in weighted if s >= self.strong_thresh]
            present = [ch for ch, _, s in weighted if s > 0]
            tier = "corroborated" if len(strong) >= 2 else ("nominated" if len(strong) == 1 else "none")
            conflict = bool(len(strong) == 1 and len(present) > 1)
            ev = TargetEvidence(
                target=t, per_channel_z={ch: round(s, 4) for ch, s in per.items() if s > 0},
                fired_channels=strong, n_fired=len(strong), tier=tier,
                max_z=max(per.values()) if per else 0.0,
                mean_fired_z=(sum(per[c] for c in strong) / len(strong) if strong else 0.0),
                conflict=conflict,
                note=("disagreement: strong in %s only" % strong[0]) if conflict else "",
            )
            if self.veto is not None:
                try:
                    if self.veto(t, context or {}):
                        ev.tier = "vetoed"; ev.note = "hard veto (safety/essentiality liability)"; score = 0.0
                except Exception:
                    pass
            rows.append((t, float(score), ev))
        rows.sort(key=lambda r: -r[1])
        return [TargetScore(target=t, score=s, tier=ev.tier, rank=i + 1, evidence=ev)
                for i, (t, s, ev) in enumerate(rows)]


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
