"""PMO-style budgeted evaluation harness for the all-atom hybrid-LLM paper (design phase, 2026-10-31).

What it enforces (the point of the harness is to make the comparison impossible to game):
  * every optimiser gets the SAME budget of calls to a TRAIN verifier (an `oracle`); duplicates (by canonical SMILES) and
    invalid / constraint-failing proposals are free but counted and capped (a proposal cap stops infinite loops);
  * the sample-efficiency metric is AUC of the top-k mean score vs number of oracle calls, normalised by the budget (scale-free; Track E A4: use z-scores against the generation space as verifier outputs, NOT percentiles against natural peptides, which saturate)
    (the formulation of Gao et al. 2022, 'Sample Efficiency Matters', arXiv 2206.12411; the exact implementation details
    of the original code are [UNVERIFIED] here: this file defines its own metric precisely, see `topk_curve` / `auc_topk`);
  * HELD-OUT verifiers can never be called during optimisation (role guard) and must be independent of the train
    verifiers (`check_independent`: different names and disjoint `trained_on` source sets) - this is the Goodhart guard;
  * paired-by-seed contrasts with typed intervals (percentile bootstrap of the mean | t-interval | objective-cluster
    bootstrap), a minimum-detectable-effect helper, and the pre-registered gate rule.
No third-party modelling code. RDKit is used only for canonicalisation (injectable; identity fallback)."""
from __future__ import annotations

import hashlib
import math
import random
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, FrozenSet, List, Optional, Sequence

import numpy as np

try:  # RDKit canonicalisation (stereo-aware); identity fallback keeps the harness importable without RDKit
    from rdkit import Chem, RDLogger

    RDLogger.DisableLog("rdApp.*")

    def default_canon(s):
        if not isinstance(s, str) or not s:
            return None
        m = Chem.MolFromSmiles(s)
        return Chem.MolToSmiles(m, isomericSmiles=True) if m is not None else None

    HAVE_RDKIT = True
except Exception:  # pragma: no cover
    HAVE_RDKIT = False

    def default_canon(s):
        return s if isinstance(s, str) and s else None


class BudgetExhausted(Exception):
    """Raised when the oracle-call budget or the proposal cap is spent; optimisers must stop."""


class HeldOutVerifierError(Exception):
    """Raised when a non-train verifier is used as an optimisation oracle, or independence is violated."""


@dataclass(frozen=True)
class Verifier:
    name: str
    fn: Callable[[str], float]
    role: str = "train"                      # "train" (budgeted objective) | "heldout" (final audit only) | "constraint"
    cost: float = 1.0                        # relative cost units per call (for cost-aware reporting)
    trained_on: FrozenSet[str] = frozenset() # source/lab names the verifier was fitted on (independence check)


def check_independent(train_verifiers: Sequence[Verifier], heldout_verifiers: Sequence[Verifier]) -> bool:
    """Train-time verifiers must differ from evaluation verifiers by name AND share no fitting sources."""
    tn = {v.name for v in train_verifiers}
    for h in heldout_verifiers:
        if h.role != "heldout":
            raise HeldOutVerifierError(f"{h.name}: role {h.role!r} is not 'heldout'")
        if h.name in tn:
            raise HeldOutVerifierError(f"verifier {h.name!r} is used for both training and evaluation")
        for t in train_verifiers:
            shared = set(t.trained_on) & set(h.trained_on)
            if shared:
                raise HeldOutVerifierError(f"{t.name} and {h.name} share fitting sources: {sorted(shared)}")
    return True


def hash_noise_verifier(name: str = "shuffled", salt: str = "0") -> Verifier:
    """Label-free reward in [0,1) from a hash of the canonical SMILES: the SHUFFLED-REWARD control (no optimiser can
    learn it; any 'gain' over random search is selection noise)."""
    def fn(s: str) -> float:
        h = hashlib.sha256((salt + "|" + s).encode()).digest()
        return int.from_bytes(h[:8], "big") / float(1 << 64)
    return Verifier(name=name, fn=fn, role="train")


class BudgetedOracle:
    """Call-counting wrapper around ONE train verifier. Calling it with a proposal returns a score (float) or None."""

    def __init__(self, verifier: Verifier, budget: int, canon: Callable = default_canon,
                 constraint: Optional[Callable[[str], bool]] = None, max_proposals: Optional[int] = None, deadline: Optional[float] = None):
        if verifier.role != "train":
            raise HeldOutVerifierError(f"{verifier.name}: only 'train' verifiers can be optimisation oracles (role={verifier.role!r})")
        if budget < 1:
            raise ValueError("budget must be >= 1")
        self.verifier, self.budget, self.canon, self.constraint = verifier, int(budget), canon, constraint
        self.max_proposals = int(max_proposals) if max_proposals else 20 * int(budget)
        self.deadline = deadline               # absolute time.time() after which the next call raises BudgetExhausted (uniform wall-clock cap, amendment A4)
        self.calls = 0
        self.cache: Dict[str, float] = {}
        self.log: List[tuple] = []           # (call_index, canonical_smiles, score)
        self.n_proposals = self.n_invalid = self.n_dup = self.n_constraint_fail = 0

    @property
    def exhausted(self) -> bool:
        return self.calls >= self.budget

    def __call__(self, smiles: str) -> Optional[float]:
        if self.deadline is not None and time.time() > self.deadline:
            raise BudgetExhausted("wall-clock cap reached")
        self.n_proposals += 1
        if self.n_proposals > self.max_proposals:
            raise BudgetExhausted("proposal cap reached")
        c = self.canon(smiles)
        if c is None:
            self.n_invalid += 1
            return None
        if self.constraint is not None and not self.constraint(c):
            self.n_constraint_fail += 1
            return None
        if c in self.cache:
            self.n_dup += 1
            return self.cache[c]
        if self.calls >= self.budget:
            raise BudgetExhausted("oracle-call budget spent")
        score = float(self.verifier.fn(c))
        self.calls += 1
        self.cache[c] = score
        self.log.append((self.calls, c, score))
        return score

    def scores(self) -> np.ndarray:
        return np.array([r[2] for r in self.log], float)

    def topk_curve(self, k: int = 10) -> np.ndarray:
        """Length-`budget` array: mean of the best min(k, n) scores after t calls, t = 1..budget; if the run stopped early
        the last value is carried forward (PMO-style padding); no calls -> zeros."""
        s = self.scores()
        out = np.zeros(self.budget, float)
        if len(s) == 0:
            return out
        best: List[float] = []
        for t, x in enumerate(s):
            best.append(float(x))
            best.sort(reverse=True)
            best = best[:k]
            out[t] = float(np.mean(best))
        if len(s) < self.budget:
            out[len(s):] = out[len(s) - 1]
        return out

    def top_smiles(self, k: int = 10) -> List[str]:
        return [r[1] for r in sorted(self.log, key=lambda r: -r[2])[:k]]


def auc_topk(curve: np.ndarray) -> float:
    """Area under the top-k-mean-vs-calls curve divided by the budget (= mean of the curve; rectangular rule)."""
    return float(np.mean(curve)) if len(curve) else float("nan")


def calls_to_threshold(curve: np.ndarray, thr: float) -> Optional[int]:
    idx = np.where(curve >= thr)[0]
    return int(idx[0]) + 1 if len(idx) else None


def run_one(optimizer: Callable, verifier: Verifier, budget: int, seed: int, k: int = 10,
            canon: Callable = default_canon, constraint: Optional[Callable[[str], bool]] = None,
            heldout: Sequence[Verifier] = (), max_proposals_factor: int = 20, max_seconds: Optional[float] = None) -> dict:
    """optimizer(oracle, rng) -> None must stop on BudgetExhausted (it is caught here)."""
    if heldout:
        check_independent([verifier], heldout)
    oracle = BudgetedOracle(verifier, budget, canon, constraint, max_proposals=max_proposals_factor * budget,
                            deadline=None if max_seconds is None else time.time() + float(max_seconds))
    rng = random.Random(seed)
    try:
        optimizer(oracle, rng)
    except BudgetExhausted:
        pass
    curve = oracle.topk_curve(k)
    top = oracle.top_smiles(k)
    out = {"seed": seed, "calls": oracle.calls, "auc_topk": auc_topk(curve), "final_topk": float(curve[-1]),
           "curve": curve, "top_smiles": top, "n_proposals": oracle.n_proposals, "n_invalid": oracle.n_invalid,
           "n_dup": oracle.n_dup, "n_constraint_fail": oracle.n_constraint_fail, "heldout": {}}
    for h in heldout:  # applied ONLY to the final top-k of the run
        vals = [float(h.fn(s)) for s in top]
        out["heldout"][h.name] = float(np.mean(vals)) if vals else float("nan")
    return out


# ---------------------------------------------------------------- trivial baselines / controls
def random_search(sampler: Callable[[random.Random], str]) -> Callable:
    def opt(oracle: BudgetedOracle, rng: random.Random) -> None:
        while True:
            oracle(sampler(rng))
    return opt


def copy_seed(seeds: Sequence[str]) -> Callable:
    """CONTROL: proposes only the given seeds (cycling); can score at most len(seeds) unique molecules."""
    def opt(oracle: BudgetedOracle, rng: random.Random) -> None:
        i = 0
        while True:
            oracle(seeds[i % len(seeds)])
            i += 1
    return opt


# ---------------------------------------------------------------- statistics
def _tcrit(df: int, level: float = 0.95) -> float:
    try:
        from scipy import stats
        return float(stats.t.ppf(0.5 + level / 2, df))
    except Exception:  # pragma: no cover - normal approximation fallback (anti-conservative for small df)
        return 1.959964 if abs(level - 0.95) < 1e-9 else 2.575829


def _boot_ci(x: np.ndarray, level: float = 0.95, B: int = 5000, seed: int = 12345):
    rng = np.random.default_rng(seed)
    n = len(x)
    if n < 2:
        return [float(x[0]), float(x[0])] if n == 1 else [float("nan"), float("nan")]
    means = x[rng.integers(0, n, size=(B, n))].mean(axis=1)
    a = (1 - level) / 2 * 100
    return [float(np.percentile(means, a)), float(np.percentile(means, 100 - a))]


def summarise(values: Sequence[float], level: float = 0.95) -> dict:
    x = np.asarray([v for v in values if v == v], float)
    n = len(x)
    if n == 0:
        return {"n": 0}
    sd = float(x.std(ddof=1)) if n > 1 else float("nan")
    half = _tcrit(n - 1, level) * sd / math.sqrt(n) if n > 1 else float("nan")
    return {"n": n, "mean": float(x.mean()), "sd": sd, "ci_boot_mean": _boot_ci(x, level),
            "ci_t": [float(x.mean() - half), float(x.mean() + half)], "interval_types": "ci_boot_mean=percentile bootstrap CI of the mean over seeds; ci_t=t-interval"}


def paired_contrast(a: Sequence[float], b: Sequence[float], level: float = 0.95) -> dict:
    """a - b paired by position (seed). Reports both seed-level interval types; the WIDER one is `ci_wide`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    if len(a) != len(b):
        raise ValueError("paired contrast needs equal-length, seed-aligned inputs")
    d = a - b
    s = summarise(d, level)
    s["ci_wide"] = [min(s["ci_boot_mean"][0], s["ci_t"][0]), max(s["ci_boot_mean"][1], s["ci_t"][1])] if s["n"] > 1 else None
    s["sd_diff"] = s.get("sd")
    return s


def cluster_paired_contrast(per_cluster: Dict[str, Sequence[float]], level: float = 0.95, B: int = 5000, seed: int = 777) -> dict:
    """per_cluster[name] = paired differences (a-b) over seeds for ONE objective/target. The unit of generalisation is the
    objective: bootstrap over clusters of their mean differences."""
    names = sorted(per_cluster)
    means = np.array([float(np.mean(per_cluster[n])) for n in names], float)
    out = {"n_clusters": len(names), "mean_of_cluster_means": float(means.mean()) if len(means) else float("nan"),
           "ci_cluster_boot": _boot_ci(means, level, B, seed), "per_cluster": dict(zip(names, means.tolist())),
           "interval_type": "percentile bootstrap over objective clusters of the cluster-mean paired difference"}
    return out


def mde_paired(sd_diff: float, n: int, alpha: float = 0.05, power: float = 0.80) -> float:
    """Minimum detectable paired mean difference (normal approximation, two-sided)."""
    from statistics import NormalDist
    z = NormalDist().inv_cdf
    return float((z(1 - alpha / 2) + z(power)) * sd_diff / math.sqrt(n))


def gate_primary(contrasts: Dict[str, dict], margin=None, min_pass: int = 2) -> dict:
    """Pre-registered rule: the candidate beats the BEST baseline by >= margin with the interval's lower bound > 0 in at
    least `min_pass` objective families. contrasts[family] = paired_contrast(candidate, best_baseline) output.
    `margin` is REQUIRED (Track E amendment A4 withdrew the old default +0.03 on the saturating percentile scale): pass a float, or a dict
    family -> margin for the per-family relative margins of A4/A5 (in SD-AUC units, see track_e/verifiers_e.build_ladder(gen_ref=...))."""
    if margin is None:
        raise ValueError("gate_primary: margin is required (the +0.03 normalised-AUC default was withdrawn in Track E amendment A4)")
    passed = []
    for fam, c in contrasts.items():
        lo = c["ci_wide"][0] if c.get("ci_wide") else float("nan")
        m = margin[fam] if isinstance(margin, dict) else margin
        if c.get("mean", float("nan")) >= m and lo > 0:
            passed.append(fam)
    return {"passed_families": sorted(passed), "n_pass": len(passed), "min_pass": min_pass,
            "verdict": "PASS" if len(passed) >= min_pass else "FAIL"}


# ---------------------------------------------------------------- three-way verifier split (train / stop / heldout)
def check_three_way(train: Sequence[Verifier], stop: Sequence[Verifier], heldout: Sequence[Verifier]) -> bool:
    """Amendment A1: the 'stop' verifiers (used only to decide early stopping, never as an optimisation oracle) must
    differ from the train AND the held-out verifiers by name and share no fitting sources with either."""
    for v in stop:
        if v.role != "stop":
            raise HeldOutVerifierError(f"{v.name}: role {v.role!r} is not 'stop'")
    groups = [("train", list(train)), ("stop", list(stop)), ("heldout", list(heldout))]
    for i in range(len(groups)):
        for j in range(i + 1, len(groups)):
            (na, ga), (nb, gb) = groups[i], groups[j]
            for a in ga:
                for b in gb:
                    if a.name == b.name:
                        raise HeldOutVerifierError(f"verifier {a.name!r} appears in both {na} and {nb}")
                    shared = set(a.trained_on) & set(b.trained_on)
                    if shared:
                        raise HeldOutVerifierError(f"{na}:{a.name} and {nb}:{b.name} share fitting sources: {sorted(shared)}")
    for h in heldout:
        if h.role != "heldout":
            raise HeldOutVerifierError(f"{h.name}: role {h.role!r} is not 'heldout'")
    return True


class StopMonitor:
    """Goodhart-gap early stopping. After each feedback round call `update(train_scores, stop_scores)` with the train-verifier
    and stop-verifier scores of the SAME top-k molecules found so far. Both are assumed on the same normalised [0,1] scale.
    The monitor stops when the stop-verifier top-k mean has not improved by >= `min_gain` for `patience` consecutive rounds
    while the train-verifier mean kept improving (the gap between them is opening). It never sees held-out verifiers."""

    def __init__(self, patience: int = 2, min_gain: float = 0.005):
        self.patience, self.min_gain = int(patience), float(min_gain)
        self.hist: List[tuple] = []
        self.best_stop = -float("inf")
        self.stale = 0
        self.stopped_at: Optional[int] = None

    def update(self, train_scores: Sequence[float], stop_scores: Sequence[float]) -> bool:
        tm = float(np.mean(train_scores)) if len(train_scores) else float("nan")
        sm = float(np.mean(stop_scores)) if len(stop_scores) else float("nan")
        prev_t = self.hist[-1][0] if self.hist else -float("inf")
        self.hist.append((tm, sm, tm - sm))
        if sm >= self.best_stop + self.min_gain:
            self.best_stop, self.stale = sm, 0
        elif tm > prev_t:
            self.stale += 1            # train kept improving, stop-verifier did not
        if self.stale >= self.patience and self.stopped_at is None:
            self.stopped_at = len(self.hist)
        return self.stopped_at is not None

    @property
    def gap_curve(self) -> List[float]:
        return [g for _, _, g in self.hist]
