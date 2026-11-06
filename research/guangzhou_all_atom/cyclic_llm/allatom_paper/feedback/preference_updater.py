"""U3: graded preference tuning with the variance fix (docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md section 7).

Why the earlier unified GRPO stalled (`docs/20261023_RL_DATAGEN_STUDY_DESIGN_SURVEY.md`; `v4_eval/audit_dpo_result.json`):
a binary reward plus a start policy that is consistent per prompt gives ZERO within-group variance, so the z-scored group
advantage is 0 for ~95-100% of groups (frac_reward_zero_std ~0.95-1.0, KL ~0.001, relative weight change ~0.001).
Fix implemented here (numpy only; the torch DPO step lives in the smoke script):
  (1) graded reward = continuous verifier score (never thresholded);
  (2) rank-based group advantage (ties -> average rank), no division by the group std;
  (3) groups need >= `group_size` members and non-trivial score spread, otherwise they are dropped and COUNTED;
  (4) DPO-style pairs from rank-ordered samples with a score margin (needs no within-group variance beyond the margin);
  (5) KL / relative-weight-change gate (`KLWeightGate`): after 3 rounds, KL < 0.01 or relative change < 0.005 ->
      raise lr/rank once, then stop.
Also contains `LegacyBinaryGRPO`, the previous recipe, so tests can show it fails where the new updater learns."""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from contracts import PreferencePair  # noqa: E402  (the frozen interface from workstream I-A)


def rank_advantage(scores: Sequence[float]) -> np.ndarray:
    """Rank-based advantage in [-0.5, 0.5]; ties share the average rank; all-equal -> zeros. No division by std."""
    s = np.asarray(scores, float)
    n = len(s)
    if n < 2:
        return np.zeros(n)
    order = np.argsort(s, kind="mergesort")
    ranks = np.empty(n)
    i = 0
    while i < n:
        j = i
        while j + 1 < n and s[order[j + 1]] == s[order[i]]:
            j += 1
        ranks[order[i:j + 1]] = 0.5 * (i + j)
        i = j + 1
    if np.ptp(s) == 0:
        return np.zeros(n)
    return ranks / (n - 1) - 0.5


@dataclass
class PairSet:
    winners: List[int] = field(default_factory=list)   # indices into the sample list
    losers: List[int] = field(default_factory=list)
    gaps: List[float] = field(default_factory=list)
    groups: List[object] = field(default_factory=list)

    def __len__(self):
        return len(self.winners)


class GradedPreferenceUpdater:
    """`make_pairs(samples, scores, margin, group_by)` -> (PairSet, diagnostics). `scores` are graded (continuous) values,
    invalid molecules must be passed as None/NaN and are excluded (counted). `group_by` is the prompt id of each sample."""

    def __init__(self, group_size: int = 16, margin: float = 0.05, max_pairs_per_group: int = 8,
                 min_group_std: float = 1e-6, beta: float = 0.1, policy=None):
        self.group_size, self.margin, self.max_pairs = int(group_size), float(margin), int(max_pairs_per_group)
        self.min_std, self.beta = float(min_group_std), float(beta)
        self.policy = policy                        # object with dpo_step(pairs, lr, beta) -> metrics (LoRA policy or tabular)
        self.last_index_pairs = PairSet()           # index form of the last make_pairs call (for tabular/torch policies)

    def step(self, pairs: Sequence[PreferencePair], lr: float, beta: Optional[float] = None) -> Dict[str, float]:
        if self.policy is None:
            raise RuntimeError("GradedPreferenceUpdater.step needs a policy exposing dpo_step(pairs, lr, beta)")
        return self.policy.dpo_step(pairs, lr, self.beta if beta is None else beta)

    def make_pairs(self, samples: Sequence[str], scores: Sequence[Optional[float]], margin: Optional[float] = None,
                   group_by: Optional[Sequence[object]] = None) -> Tuple[List[PreferencePair], Dict[str, float]]:
        margin = self.margin if margin is None else float(margin)
        n = len(samples)
        gb = list(group_by) if group_by is not None else [0] * n
        by_g: Dict[object, List[int]] = {}
        n_invalid = 0
        for i in range(n):
            sc = scores[i]
            if sc is None or not np.isfinite(sc):
                n_invalid += 1
                continue
            by_g.setdefault(gb[i], []).append(i)
        ps = PairSet()
        n_groups = len(by_g)
        n_small = n_zero = n_used = 0
        for g, idx in by_g.items():
            if len(idx) < self.group_size:
                n_small += 1
                continue
            sc = np.array([scores[i] for i in idx], float)
            if np.std(sc) < self.min_std:
                n_zero += 1
                continue
            order = np.argsort(-sc, kind="mergesort")
            m = min(self.max_pairs, len(idx) // 2)
            made = 0
            for r in range(m):                      # i-th best against i-th worst
                w, l = idx[order[r]], idx[order[len(idx) - 1 - r]]
                gap = float(scores[w] - scores[l])
                if gap >= margin:
                    ps.winners.append(w), ps.losers.append(l), ps.gaps.append(gap), ps.groups.append(g)
                    made += 1
            n_used += made > 0
        diag = {
            "n_samples": n, "n_invalid_excluded": n_invalid, "n_groups": n_groups,
            "frac_small_groups_dropped": n_small / max(1, n_groups),
            "frac_zero_variance_groups": n_zero / max(1, n_groups),
            "frac_groups_retained": n_used / max(1, n_groups),
            "n_pairs": len(ps), "mean_gap": float(np.mean(ps.gaps)) if len(ps) else 0.0,
        }
        diag["mean_margin"] = diag["mean_gap"]                  # names required by contracts.PreferenceUpdater
        diag["n_groups_kept"] = n_used
        self.last_index_pairs = ps
        pairs = [PreferencePair(chosen=samples[w], rejected=samples[l], margin=g, group=str(grp))
                 for w, l, g, grp in zip(ps.winners, ps.losers, ps.gaps, ps.groups)]
        return pairs, diag


def dpo_loss_and_grad_coef(lw, ll, rlw, rll, beta: float):
    """DPO loss  -log sigmoid(beta*((lw-rlw)-(ll-rll))). Returns (loss, d loss / d z) with z = beta*(...)."""
    z = beta * ((np.asarray(lw) - np.asarray(rlw)) - (np.asarray(ll) - np.asarray(rll)))
    loss = np.logaddexp(0.0, -z)
    dz = -1.0 / (1.0 + np.exp(z))              # derivative of -log(sigmoid(z)) wrt z
    return loss, dz


class KLWeightGate:
    """Per the design (section 7 item 5): from round `check_from` on, if KL to the reference < `kl_min` OR the relative
    weight change < `relw_min`: first violation -> 'raise_lr_rank_once'; a second violation (checked at least
    `recheck_after` rounds later) -> 'stop'. Otherwise 'continue'."""

    def __init__(self, kl_min: float = 0.01, relw_min: float = 0.005, check_from: int = 3, recheck_after: int = 2):
        self.kl_min, self.relw_min, self.check_from, self.recheck_after = kl_min, relw_min, check_from, recheck_after
        self.raised_at: Optional[int] = None

    def update(self, round_idx: int, kl: float, rel_weight_change: float) -> str:
        if round_idx < self.check_from:
            return "continue"
        bad = (kl < self.kl_min) or (rel_weight_change < self.relw_min)
        if not bad:
            return "continue"
        if self.raised_at is None:
            self.raised_at = round_idx
            return "raise_lr_rank_once"
        if round_idx - self.raised_at >= self.recheck_after:
            return "stop"
        return "continue"


class LegacyBinaryGRPO:
    """The previous recipe, kept as a control that must FAIL where the new updater learns: binary reward 1[score >= thr],
    group advantage (r - mean)/(std + eps); a zero-variance group gets advantage exactly 0 (no gradient)."""

    def __init__(self, threshold: float, eps: float = 1e-6):
        self.thr, self.eps = float(threshold), float(eps)

    def advantages(self, scores_by_group: Dict[object, Sequence[float]]):
        out, n_zero = {}, 0
        for g, sc in scores_by_group.items():
            r = (np.asarray(sc, float) >= self.thr).astype(float)
            sd = r.std()
            if sd < 1e-12:
                n_zero += 1
                out[g] = np.zeros_like(r)
            else:
                out[g] = (r - r.mean()) / (sd + self.eps)
        return out, n_zero / max(1, len(scores_by_group))
