"""Innovation-demonstration harness — the §3 target-ID head-to-head.

Runs the pre-registered arms (docs/20261020_INNOVATION_DEMONSTRATION_PROTOCOL.md) and scores each
against a gold target set with a permutation null:
  - "system"        : the fused evidence-gate ranking over ALL channels
  - "channel:<name>": each single channel alone (the baselines the system must beat)
  - (clinical/field-tool arm: TIDE/IMPRES + leave-cohort-out ICB — see run_clinical_arm; needs the
    TIGER bulk cohorts, a documented stage-2, NOT faked here)

Metrics (sklearn): AUROC + average precision + precision@k vs gold, over the union candidate
universe (gold genes a channel missed are negatives at score 0 so recall is penalised). The
permutation null (shuffle gold labels, quantile of AUROC) gives the "beats_null" bar — mandatory
because DisGeNET-style gold is annotation-depth biased.

PASS gate P1 (pre-registered): system AUROC > every single channel AND > the null bar.
3.9-safe; sklearn/numpy imported lazily in the metric fn.
"""
from typing import Any, Dict, List, Optional, Sequence

from .arbiter import EvidenceGateArbiter, HarmonicSumArbiter, _collect_per_channel_z
from .types import ChannelResult


def _rank_metrics(scores: Dict[str, float], gold: set, universe: List[str],
                  k_list: Sequence[int]) -> Dict[str, Any]:
    import numpy as np
    from sklearn.metrics import average_precision_score, roc_auc_score
    y = np.array([1 if t in gold else 0 for t in universe], dtype=int)
    s = np.array([float(scores.get(t, 0.0)) for t in universe], dtype=float)
    npos = int(y.sum())
    if npos == 0 or npos == len(y):
        return {"auroc": None, "ap": None, "prec_at_k": {}, "n_pos": npos, "n": len(y)}
    order = np.argsort(-s)
    preck = {}
    for k in k_list:
        kk = min(k, len(order))
        preck[k] = round(float(y[order[:kk]].sum()) / kk, 4) if kk else None
    return {"auroc": round(float(roc_auc_score(y, s)), 4),
            "ap": round(float(average_precision_score(y, s)), 4),
            "prec_at_k": preck, "n_pos": npos, "n": len(y)}


def _perm_null_auroc(gold: set, universe: List[str], ref_scores: Dict[str, float],
                     n_perm: int = 500, quantile: float = 0.95, seed: int = 0) -> float:
    """AUROC bar under label permutation (fix the score vector, shuffle which targets are gold)."""
    import numpy as np
    from sklearn.metrics import roc_auc_score
    s = np.array([float(ref_scores.get(t, 0.0)) for t in universe], dtype=float)
    npos = sum(1 for t in universe if t in gold)
    if npos == 0 or npos >= len(universe):
        return float("nan")
    rng = np.random.RandomState(seed)
    idx = np.arange(len(universe))
    aucs = []
    for _ in range(n_perm):
        yp = np.zeros(len(universe), dtype=int)
        yp[rng.choice(idx, npos, replace=False)] = 1
        aucs.append(roc_auc_score(yp, s))
    return round(float(np.quantile(aucs, quantile)), 4)


def run_demonstration(channel_results: List[ChannelResult], gold: Sequence[str],
                      k_list: Sequence[int] = (10, 20, 50), n_perm: int = 500,
                      z_thresh: float = 2.0, null_method: str = "robust") -> Dict[str, Any]:
    """Run the target-ID arms vs gold. Returns {arms, null_bar, pass_P1, ...}."""
    gold = set(str(g).upper() for g in gold)
    ok = [cr for cr in channel_results if cr.ok]
    chan_universe = {t for cr in ok for t in cr.scores}
    universe = sorted(chan_universe | gold)

    # system arm (adopted scheme): Open Targets harmonic sum + reliability weights
    system_scores = {t: 0.0 for t in universe}
    for ts in HarmonicSumArbiter().rank(channel_results, {}):
        system_scores[ts.target] = ts.score

    # comparison arm: the earlier binary evidence gate (kept to show harmonic > gate)
    gate_scores = {t: 0.0 for t in universe}
    for ts in EvidenceGateArbiter(z_thresh=z_thresh, null_method=null_method).rank(channel_results, {}):
        gate_scores[ts.target] = ts.score

    # single-channel arms: each channel's z over the universe
    pcz = _collect_per_channel_z(channel_results, method=null_method)

    arms: Dict[str, Any] = {
        "system": _rank_metrics(system_scores, gold, universe, k_list),            # harmonic (default)
        "system_gate": _rank_metrics(gate_scores, gold, universe, k_list),          # old binary gate
    }
    for ch, zmap in pcz.items():
        arms["channel:" + ch] = _rank_metrics({t: zmap.get(t, 0.0) for t in universe}, gold, universe, k_list)

    null_bar = _perm_null_auroc(gold, universe, system_scores, n_perm=n_perm)

    sys_auroc = arms["system"]["auroc"]
    single_aurocs = [v["auroc"] for k, v in arms.items() if k.startswith("channel:") and v["auroc"] is not None]
    best_single = max(single_aurocs) if single_aurocs else None
    pass_p1 = bool(
        sys_auroc is not None and single_aurocs
        and sys_auroc > best_single
        and (null_bar != null_bar or sys_auroc > null_bar)  # null_bar NaN -> skip that clause
    )
    return {
        "arms": arms,
        "null_bar_auroc_p95": null_bar,
        "best_single_channel_auroc": best_single,
        "system_auroc": sys_auroc,
        "pass_P1_system_beats_singles_and_null": pass_p1,
        "universe_size": len(universe),
        "n_gold_in_universe": sum(1 for t in universe if t in gold),
        "channels": [cr.channel for cr in ok],
    }


def run_clinical_arm(*args, **kwargs):
    """STAGE 2 (documented, not faked): ICB-response leave-cohort-out with field tools.

    The clinical half of the demonstration (protocol §3 P2/P3): score the TIGER bulk ICB cohorts
    (s3://.../acquisitions/icb_bulk_tigeR, 11 cohorts) by our fused system vs TIDE / IMPRES /
    IFN-gamma-GEP, leave-cohort-out, and test predictive>prognostic (gate-3 interaction). Requires
    the bulk expression matrices + field-tool signature implementations; wire before claiming P2/P3.
    """
    raise NotImplementedError(
        "clinical arm (TIDE/IMPRES, leave-cohort-out ICB) is stage-2 — needs the TIGER bulk cohorts "
        "and field-tool signatures; build before claiming the predictive>prognostic (P2/P3) gates"
    )
