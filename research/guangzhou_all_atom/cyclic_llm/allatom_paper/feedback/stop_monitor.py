"""U2: Goodhart-gap early stopping (GapStopMonitor) - parameters FIXED in the pre-registered amendment
(docs/20261031_ALLATOM_U2U3_NOTES.md section 3) before any simulation run.

Per round the monitor receives the scores of the SAME batch under the TRAIN verifier (the optimisation objective) and the
STOP verifier (independent of train; never optimised). It takes the top fraction `q` of the batch by TRAIN score and tracks
T_t, S_t = mean TRAIN and STOP score of that set in z-units (round-0 batch SD of each verifier). Gap g_t = (T_t-T_0)-(S_t-S_0), smoothed over the last `smooth` rounds.
Stop when, after `warmup` rounds, the STOP gain has not improved by more than `tol` for `patience` rounds AND the gap has risen
by at least `tau` above its running minimum (train keeps climbing while the independent verifier does not). The restore round is
the argmax of S_t. Held-out verifiers never enter."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Sequence

import numpy as np


@dataclass
class GapStopMonitor:
    q: float = 0.10
    patience: int = 3
    tau: float = 0.5
    tol: float = 0.05
    warmup: int = 2
    smooth: int = 2
    gaps: List[float] = field(default_factory=list)
    T: List[float] = field(default_factory=list)
    S: List[float] = field(default_factory=list)
    sd_t: float = 1.0
    sd_s: float = 1.0
    best_s: float = -float("inf")
    best_round: int = 0
    stale: int = 0
    gap_min: float = float("inf")
    stopped_at: int = -1

    def update(self, round_idx: int, train_scores: Sequence[float], stop_scores: Sequence[float]) -> Dict[str, object]:
        tr, st = np.asarray(train_scores, float), np.asarray(stop_scores, float)
        if round_idx == 0:
            self.sd_t = float(np.std(tr)) or 1.0
            self.sd_s = float(np.std(st)) or 1.0
        k = max(1, int(round(self.q * len(tr))))
        top = np.argsort(-tr)[:k]
        t, s = float(np.mean(tr[top])), float(np.mean(st[top]))
        self.T.append(t), self.S.append(s)
        gt = (t - self.T[0]) / self.sd_t
        gs = (s - self.S[0]) / self.sd_s
        gap = gt - gs
        self.gaps.append(gap)
        gap = float(np.mean(self.gaps[-self.smooth:]))           # smoothed gap (mean of the last `smooth` rounds)
        if gs > self.best_s + self.tol:
            self.best_s, self.best_round, self.stale = gs, round_idx, 0
        else:
            self.stale += 1
        self.gap_min = min(self.gap_min, gap)
        trend = gap - self.gap_min
        should = (self.stopped_at < 0 and round_idx >= self.warmup and self.stale >= self.patience and trend >= self.tau)
        if should:
            self.stopped_at = round_idx
        return dict(gap=gap, trend=trend, should_stop=self.stopped_at >= 0, restore_round=self.best_round, train_gain=gt,
                    stop_gain=gs)


class NeverStop:
    """Control: never stops (restore = last round)."""

    def __init__(self):
        self.n = 0

    def update(self, round_idx, train_scores, stop_scores):
        self.n = round_idx
        return dict(gap=0.0, trend=0.0, should_stop=False, restore_round=round_idx)


class AlwaysStop:
    """Control: stops at the first round after warmup (restore = that round)."""

    def __init__(self, warmup: int = 2):
        self.warmup = warmup
        self.stopped_at = -1

    def update(self, round_idx, train_scores, stop_scores):
        if self.stopped_at < 0 and round_idx >= self.warmup:
            self.stopped_at = round_idx
        return dict(gap=0.0, trend=0.0, should_stop=self.stopped_at >= 0, restore_round=self.stopped_at if self.stopped_at >= 0 else round_idx)
