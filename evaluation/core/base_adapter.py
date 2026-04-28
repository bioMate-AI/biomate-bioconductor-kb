"""
base_adapter.py
---------------
Abstract base class for all benchmark adapters.

Every adapter must implement:
    load_tasks()  -> List[BenchmarkTask]
    score(task, response) -> float   (0.0 – 1.0)

Optional overrides:
    prepare(client)   called once before any tasks run
    teardown(client)  called once after all tasks complete
    task_prompt(task) return the exact string sent to BioMate
                      (default: task.question)
"""

from __future__ import annotations

import abc
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class BenchmarkTask:
    task_id: str
    question: str                        # Exact string sent to BioMate
    ground_truth: Any                    # Expected answer (format varies by benchmark)
    domain: str = "life_science"
    difficulty: str = "medium"           # easy | medium | hard | adversarial
    task_type: str = "reasoning"         # reasoning | code | workflow | retrieval | multi_turn
    answer_type: str = "open"            # open | multiple_choice | json | binary
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class BenchmarkResult:
    task_id: str
    benchmark: str
    score: float                         # 0.0 – 1.0
    agent_response: str
    ground_truth: Any
    latency_sec: float
    metadata: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None
    timestamp: float = field(default_factory=time.time)
    # Cost tracking (filled by BioMateEvalClient when server returns token counts)
    input_tokens: Optional[int] = None
    output_tokens: Optional[int] = None
    cost_usd: Optional[float] = None
    model: Optional[str] = None


class BenchmarkAdapter(abc.ABC):
    """Abstract base for all benchmark adapters."""

    name: str = "unnamed"                # Override in subclass

    def __init__(self, config: Dict[str, Any]):
        self.config = config

    def prepare(self, client) -> None:
        """Called once before tasks run. Override for setup (e.g. login, download)."""

    def teardown(self, client) -> None:
        """Called once after all tasks complete."""

    @abc.abstractmethod
    def load_tasks(self) -> List[BenchmarkTask]:
        """Return all benchmark tasks to run."""

    @abc.abstractmethod
    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """Score agent_response against task.ground_truth. Return 0.0–1.0."""

    def task_prompt(self, task: BenchmarkTask) -> str:
        """Return the string to send to BioMate. Override to add system context."""
        return task.question

    def run(self, client, max_tasks: Optional[int] = None, skip: int = 0) -> List[BenchmarkResult]:
        """
        Execute all tasks against BioMate and return results.
        Uses client.ask() for single-turn tasks; override for multi-turn.
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed

        tasks = self.load_tasks()
        if skip:
            tasks = tasks[skip:]
        if max_tasks:
            tasks = tasks[:max_tasks]

        self.prepare(client)
        results: List[BenchmarkResult] = []

        import threading
        concurrency = self.config.get("concurrency", {}).get("max_parallel_tasks", 4)
        _thread_local = threading.local()

        def _get_thread_client():
            if not hasattr(_thread_local, "client"):
                _thread_local.client = client.clone() if hasattr(client, "clone") else client
            return _thread_local.client

        def _run_one(task: BenchmarkTask) -> BenchmarkResult:
            t0 = time.time()
            error = None
            response_text = ""
            response = None
            tc = _get_thread_client()
            try:
                response = tc.ask(self.task_prompt(task))
                response_text = response.text
            except Exception as exc:
                error = str(exc)

            score = 0.0
            if not error:
                try:
                    score = self.score(task, response_text)
                except Exception as exc:
                    error = f"scoring error: {exc}"

            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=score,
                agent_response=response_text,
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                metadata=task.metadata,
                error=error,
                input_tokens=response.input_tokens if response else None,
                output_tokens=response.output_tokens if response else None,
                cost_usd=response.cost_usd if response else None,
                model=response.model if response else None,
            )

        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = {pool.submit(_run_one, t): t for t in tasks}
            for future in as_completed(futures):
                results.append(future.result())

        self.teardown(client)
        return results

    def run_tasks(self, client, tasks: List[BenchmarkTask],
                  on_result=None) -> List[BenchmarkResult]:
        """
        Execute a pre-filtered task list. Avoids reloading via load_tasks().
        Each worker thread gets its own BioMateEvalClient to avoid session contention.
        on_result: optional callback(BenchmarkResult) called immediately as each task finishes.
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading

        self.prepare(client)
        results: List[BenchmarkResult] = []

        concurrency = self.config.get("concurrency", {}).get("max_parallel_tasks", 4)

        # Thread-local storage: each thread creates its own client clone
        _thread_local = threading.local()

        def _get_thread_client():
            if not hasattr(_thread_local, "client"):
                _thread_local.client = client.clone() if hasattr(client, "clone") else client
            return _thread_local.client

        def _run_one(task: BenchmarkTask) -> BenchmarkResult:
            t0 = time.time()
            error = None
            response_text = ""
            tc = _get_thread_client()
            try:
                # Use ask_task() if the adapter defines it (supports per-task retry logic)
                if hasattr(self, "ask_task"):
                    response_text = self.ask_task(tc, task)
                else:
                    response = tc.ask(self.task_prompt(task))
                    response_text = response.text
            except Exception as exc:
                error = str(exc)

            score = 0.0
            if not error:
                try:
                    score = self.score(task, response_text)
                except Exception as exc:
                    error = f"scoring error: {exc}"

            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=score,
                agent_response=response_text,
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                metadata=task.metadata,
                error=error,
            )

        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = {pool.submit(_run_one, t): t for t in tasks}
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                if on_result:
                    try:
                        on_result(result)
                    except Exception:
                        pass

        self.teardown(client)
        return results
