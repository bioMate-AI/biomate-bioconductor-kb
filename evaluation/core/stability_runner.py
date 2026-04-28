"""
stability_runner.py
-------------------
Measures response consistency when the same query is posed N times.

Metrics:
  consistency_rate  — % of tasks where all N runs give the same score bucket
  score_variance    — mean std of scores across runs per task
  kappa             — Cohen's κ inter-run agreement (binary correct/incorrect)
  flip_rate         — % of tasks that change correct↔incorrect at least once

Usage:
    runner = StabilityRunner(client, n_repeats=3, sample_fraction=0.2)
    report = runner.run(tasks, score_fn)
    print(report.summary())
"""
from __future__ import annotations

import random
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple


@dataclass
class TaskStabilityResult:
    task_id: str
    scores: List[float]          # one per repeat
    latencies: List[float]
    costs: List[float]

    @property
    def mean_score(self) -> float:
        return sum(self.scores) / len(self.scores) if self.scores else 0.0

    @property
    def score_std(self) -> float:
        if len(self.scores) < 2:
            return 0.0
        mean = self.mean_score
        return (sum((s - mean) ** 2 for s in self.scores) / (len(self.scores) - 1)) ** 0.5

    @property
    def is_consistent(self) -> bool:
        """All runs agree (all correct or all incorrect)."""
        if not self.scores:
            return True
        buckets = [s >= 0.5 for s in self.scores]
        return all(b == buckets[0] for b in buckets)

    @property
    def flipped(self) -> bool:
        """At least one run disagrees with the others."""
        return not self.is_consistent


@dataclass
class StabilityReport:
    benchmark: str
    model: str
    n_tasks: int
    n_repeats: int
    sample_fraction: float

    consistency_rate: float       # % tasks consistent across all N runs
    flip_rate: float              # % tasks that flipped correct↔incorrect
    mean_score: float             # average score across all runs
    score_variance: float         # mean per-task score std
    kappa: float                  # Cohen's κ (inter-run agreement)

    mean_latency_sec: float
    latency_std_sec: float
    p95_latency_sec: float

    total_cost_usd: float
    mean_cost_per_task_usd: float

    per_task: List[TaskStabilityResult] = field(default_factory=list)

    def summary(self) -> str:
        lines = [
            f"Stability Report — {self.benchmark} ({self.model})",
            f"  Tasks sampled:      {self.n_tasks} ({self.sample_fraction:.0%} of full set)",
            f"  Repeats per task:   {self.n_repeats}",
            f"  Consistency rate:   {self.consistency_rate:.1%}  (all {self.n_repeats} runs agree)",
            f"  Flip rate:          {self.flip_rate:.1%}  (correct↔incorrect at least once)",
            f"  Mean score:         {self.mean_score:.3f} ± {self.score_variance:.3f}",
            f"  Cohen's κ:          {self.kappa:.3f}",
            f"  Latency:            {self.mean_latency_sec:.1f}s mean, "
            f"{self.latency_std_sec:.1f}s std, {self.p95_latency_sec:.1f}s p95",
            f"  Total cost:         ${self.total_cost_usd:.4f}",
            f"  Cost/task:          ${self.mean_cost_per_task_usd:.5f}",
        ]
        return "\n".join(lines)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "benchmark": self.benchmark,
            "model": self.model,
            "n_tasks": self.n_tasks,
            "n_repeats": self.n_repeats,
            "sample_fraction": self.sample_fraction,
            "consistency_rate": round(self.consistency_rate, 4),
            "flip_rate": round(self.flip_rate, 4),
            "mean_score": round(self.mean_score, 4),
            "score_variance": round(self.score_variance, 4),
            "kappa": round(self.kappa, 4),
            "mean_latency_sec": round(self.mean_latency_sec, 2),
            "latency_std_sec": round(self.latency_std_sec, 2),
            "p95_latency_sec": round(self.p95_latency_sec, 2),
            "total_cost_usd": round(self.total_cost_usd, 6),
            "mean_cost_per_task_usd": round(self.mean_cost_per_task_usd, 6),
        }


def _cohen_kappa(run_a: List[float], run_b: List[float]) -> float:
    """Cohen's κ between two binary score lists."""
    assert len(run_a) == len(run_b)
    n = len(run_a)
    if n == 0:
        return 0.0
    a = [s >= 0.5 for s in run_a]
    b = [s >= 0.5 for s in run_b]
    p_agree = sum(1 for x, y in zip(a, b) if x == y) / n
    p_a1 = sum(a) / n
    p_b1 = sum(b) / n
    p_chance = p_a1 * p_b1 + (1 - p_a1) * (1 - p_b1)
    if p_chance == 1.0:
        return 1.0
    return (p_agree - p_chance) / (1 - p_chance)


def _mean_pairwise_kappa(runs: List[List[float]]) -> float:
    """Average pairwise Cohen's κ across all run pairs."""
    if len(runs) < 2:
        return 1.0
    kappas = []
    for i in range(len(runs)):
        for j in range(i + 1, len(runs)):
            kappas.append(_cohen_kappa(runs[i], runs[j]))
    return sum(kappas) / len(kappas)


class StabilityRunner:
    """
    Runs benchmark tasks N times and measures consistency.

    Parameters
    ----------
    ask_fn : callable(question: str) -> (score: float, latency: float, cost: float)
        Function that poses a question and returns (score, latency_sec, cost_usd).
    n_repeats : int
        How many times to run each sampled task.
    sample_fraction : float
        Fraction of tasks to sample (0.0–1.0). Default 0.2 (20%).
    seed : int
        Random seed for reproducible sampling.
    delay_between_calls : float
        Seconds to sleep between API calls to avoid rate limits.
    """

    def __init__(
        self,
        ask_fn: Callable[[str], Tuple[float, float, float]],
        n_repeats: int = 3,
        sample_fraction: float = 0.2,
        seed: int = 42,
        delay_between_calls: float = 0.5,
    ):
        self.ask_fn = ask_fn
        self.n_repeats = n_repeats
        self.sample_fraction = sample_fraction
        self.seed = seed
        self.delay = delay_between_calls

    def sample_tasks(self, tasks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Stratified sample by subtask type."""
        rng = random.Random(self.seed)

        # Group by subtask
        by_subtask: Dict[str, List] = {}
        for t in tasks:
            st = t.get("subtask", "unknown")
            by_subtask.setdefault(st, []).append(t)

        sampled = []
        for st, group in by_subtask.items():
            k = max(1, round(len(group) * self.sample_fraction))
            sampled.extend(rng.sample(group, min(k, len(group))))

        return sampled

    def run(
        self,
        tasks: List[Dict[str, Any]],
        question_fn: Callable[[Dict], str],
        score_fn: Callable[[str, str, str], float],
        benchmark: str = "unknown",
        model: str = "unknown",
        verbose: bool = True,
    ) -> StabilityReport:
        """
        Run sampled tasks N times each.

        Parameters
        ----------
        tasks : list of task dicts with keys: task_id, subtask, ground_truth
        question_fn : callable(task) -> question string
        score_fn : callable(subtask, response, ground_truth) -> float
        """
        sampled = self.sample_tasks(tasks)
        n = len(sampled)

        if verbose:
            print(f"\nStability run: {n} tasks × {self.n_repeats} repeats "
                  f"({self.sample_fraction:.0%} sample from {len(tasks)} total)")

        per_task_results: List[TaskStabilityResult] = []

        for i, task in enumerate(sampled):
            task_id  = task["task_id"]
            subtask  = task["subtask"]
            gt       = task["ground_truth"]
            question = question_fn(task)

            scores, latencies, costs = [], [], []

            for rep in range(self.n_repeats):
                if verbose:
                    print(f"  [{i+1:2d}/{n}] {subtask[:20]:20s} rep={rep+1}", end="", flush=True)
                try:
                    score, latency, cost = self.ask_fn(question)
                    scores.append(score)
                    latencies.append(latency)
                    costs.append(cost)
                    if verbose:
                        print(f" score={score:.2f} {latency:.1f}s")
                except Exception as exc:
                    if verbose:
                        print(f" ERROR: {str(exc)[:50]}")
                    scores.append(0.0)
                    latencies.append(0.0)
                    costs.append(0.0)

                if rep < self.n_repeats - 1:
                    time.sleep(self.delay)

            per_task_results.append(TaskStabilityResult(
                task_id=task_id,
                scores=scores,
                latencies=latencies,
                costs=costs,
            ))

        # Aggregate
        n_consistent    = sum(1 for r in per_task_results if r.is_consistent)
        n_flipped       = sum(1 for r in per_task_results if r.flipped)
        consistency_rate = n_consistent / n if n > 0 else 0.0
        flip_rate        = n_flipped / n if n > 0 else 0.0

        all_scores = [s for r in per_task_results for s in r.scores]
        mean_score = sum(all_scores) / len(all_scores) if all_scores else 0.0
        score_var  = sum(r.score_std for r in per_task_results) / n if n > 0 else 0.0

        # Kappa: average pairwise across runs
        if self.n_repeats >= 2 and n > 0:
            run_scores = [
                [r.scores[rep] if rep < len(r.scores) else 0.0 for r in per_task_results]
                for rep in range(self.n_repeats)
            ]
            kappa = _mean_pairwise_kappa(run_scores)
        else:
            kappa = 1.0

        # Latency stats
        all_lat = [l for r in per_task_results for l in r.latencies if l > 0]
        all_lat_sorted = sorted(all_lat)
        mean_lat = sum(all_lat) / len(all_lat) if all_lat else 0.0
        std_lat  = (sum((l - mean_lat) ** 2 for l in all_lat) / max(1, len(all_lat) - 1)) ** 0.5
        p95_lat  = all_lat_sorted[int(0.95 * len(all_lat_sorted))] if all_lat_sorted else 0.0

        total_cost = sum(c for r in per_task_results for c in r.costs)

        return StabilityReport(
            benchmark=benchmark,
            model=model,
            n_tasks=n,
            n_repeats=self.n_repeats,
            sample_fraction=self.sample_fraction,
            consistency_rate=consistency_rate,
            flip_rate=flip_rate,
            mean_score=mean_score,
            score_variance=score_var,
            kappa=kappa,
            mean_latency_sec=mean_lat,
            latency_std_sec=std_lat,
            p95_latency_sec=p95_lat,
            total_cost_usd=total_cost,
            mean_cost_per_task_usd=total_cost / max(n * self.n_repeats, 1),
            per_task=per_task_results,
        )
