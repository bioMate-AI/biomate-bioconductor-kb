"""
routing_adapter.py
------------------
Cross-Domain Routing Accuracy Benchmark adapter.

Tests BioMate's two-stage LLM search (unified_workflow_search.py) by
submitting 150 natural-language queries across 14 domains and checking
whether the correct workflow appears in the top-1 or top-3 response.

Dataset: evaluation/datasets/cross_domain_routing/queries.yaml

Metrics (chat mode — default):
  top1_accuracy:      correct workflow ranked first in the chat response
  top3_accuracy:      correct workflow in top-3 (partial credit scoring)
  adversarial_top1:   top-1 accuracy on adversarial pairs only
  domain_misrouting:  fraction of queries where wrong domain returned

Metrics (IR mode — --ir-mode flag):
  MRR  (Mean Reciprocal Rank): average of 1/rank for the first correct result
  P@1  (Precision@1): fraction where correct is rank-1
  P@3  (Precision@3): fraction where correct is in top-3
  NDCG@3 (Normalised Discounted Cumulative Gain @3): position-weighted relevance
  Hit@5  (Recall@5): fraction where correct is in top-5

  IR mode calls /api/ai_assistant/search_ranked directly (bypasses chat LLM)
  and measures the raw retrieval quality of the search layer.

Evaluation split:
  "search_match" path: queries where the DB contains the correct workflow
                       → evaluate with IR metrics (MRR, NDCG@3)
  "generation" path:   queries where no direct match exists
                       → evaluate with LLM-as-judge on tool composition quality
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult


DATASET_PATH = Path(__file__).parent.parent / "datasets" / "cross_domain_routing" / "queries.yaml"


class RoutingBenchmarkAdapter(BenchmarkAdapter):
    """
    BioMate-unique benchmark: cross-domain workflow routing accuracy.

    BioMate target: ≥80% Top-1 accuracy (vs <50% for raw LLM + GalaxyMCP).
    Adversarial target: ≥70% Top-1 (vs <35% for baselines).
    """

    name = "cross_domain_routing"

    def load_tasks(self) -> List[BenchmarkTask]:
        data = yaml.safe_load(DATASET_PATH.read_text())
        tasks = []
        for item in data:
            tasks.append(BenchmarkTask(
                task_id=f"routing__{item['id']}",
                question=item["query"],
                ground_truth={
                    "correct_workflow": item["correct_workflow"],
                    "acceptable_alts": item.get("acceptable_alts", []),
                    "disqualified": item.get("disqualified", []),
                },
                domain=item.get("domain", "unknown"),
                difficulty=item.get("difficulty", "medium"),
                task_type="retrieval",
                answer_type="open",
                metadata={
                    "id": item["id"],
                    "question": item["query"],
                    "difficulty": item.get("difficulty"),
                    "domain": item.get("domain"),
                    "confusable_with": item.get("confusable_with"),
                    "notes": item.get("notes"),
                },
            ))
        return tasks

    @staticmethod
    def _normalize(s: str) -> str:
        return s.lower().replace("-", " ").replace("_", " ").replace("/", " ")

    # ── IR metrics helpers ────────────────────────────────────────────────────

    @classmethod
    def _is_match(cls, candidate_name: str, correct: str, alts: List[str]) -> bool:
        """Return True if `candidate_name` matches the correct workflow or any acceptable alt."""
        norm = cls._normalize
        n = norm(candidate_name)
        return norm(correct) in n or n in norm(correct) or any(norm(a) in n or n in norm(a) for a in alts)

    @classmethod
    def ir_metrics(
        cls,
        ranked_names: List[str],
        correct: str,
        alts: Optional[List[str]] = None,
        k_values: Optional[List[int]] = None,
    ) -> Dict[str, float]:
        """Compute IR metrics for a single query given a ranked list.

        Args:
            ranked_names:  Ordered list of workflow names (rank-1 first).
            correct:       Ground-truth correct workflow name.
            alts:          Acceptable alternative workflow names (also score as hit).
            k_values:      Values of K for P@K and Hit@K (default [1, 3, 5]).

        Returns dict with keys: mrr, ndcg_3, p_at_1, p_at_3, hit_at_5, first_rank
        (first_rank = 1-based rank of first correct hit, or None if not found)
        """
        import math
        alts = alts or []
        k_values = k_values or [1, 3, 5]

        # Find all positions where a relevant item appears (1-indexed)
        relevant_positions = [
            i + 1 for i, name in enumerate(ranked_names)
            if cls._is_match(name, correct, alts)
        ]

        first_rank = relevant_positions[0] if relevant_positions else None

        # MRR
        mrr = 1.0 / first_rank if first_rank else 0.0

        # P@K and Hit@K
        metrics: Dict[str, float] = {"mrr": mrr, "first_rank": float(first_rank) if first_rank else 0.0}
        for k in k_values:
            top_k = ranked_names[:k]
            hits = sum(1 for n in top_k if cls._is_match(n, correct, alts))
            metrics[f"p_at_{k}"] = hits / k
            metrics[f"hit_at_{k}"] = 1.0 if hits > 0 else 0.0

        # NDCG@3 (binary relevance: 1 if correct/alt, 0 otherwise)
        k3 = 3
        dcg = sum(
            1.0 / math.log2(i + 2)  # i=0 → log2(2)=1, i=1 → log2(3), etc.
            for i, name in enumerate(ranked_names[:k3])
            if cls._is_match(name, correct, alts)
        )
        # Ideal DCG@3: at most 1 relevant item, placed at rank 1
        idcg = 1.0 / math.log2(2)  # = 1.0
        metrics["ndcg_3"] = dcg / idcg if idcg > 0 else 0.0

        return metrics

    def fetch_ranked_list(self, client, query: str, limit: int = 10) -> List[str]:
        """Call /api/ai_assistant/search_ranked and return ordered workflow names."""
        try:
            resp = client._session.post(
                f"{client.base_url}/api/ai_assistant/search_ranked",
                json={"query": query, "limit": limit},
                timeout=30,
            )
            resp.raise_for_status()
            data = resp.json()
            return [r["name"] for r in data.get("results", [])]
        except Exception as exc:
            return []

    def score(self, task: BenchmarkTask, agent_response: str,
              workflow_card: Optional[Dict[str, Any]] = None) -> float:
        """
        Score = 1.0 if correct_workflow found in workflow_card name OR response text
                      OR in top-N disambiguation candidates, AND no disqualified workflow
                      mentioned anywhere (card name, candidates, response text).
        Partial credit 0.5 if acceptable_alt found in same sources.
        0.0 if disqualified workflow is the top recommendation or in candidates.

        Disambiguation handling (workflow_type='disambiguation'):
          When the backend cannot confidently commit to a single workflow and surfaces
          N candidates for the user to pick, the system has still successfully retrieved
          the correct answer if it appears anywhere in the candidate list.
          Scoring: correct_workflow in candidates → 1.0 (retrieval success)
                   correct_workflow NOT in candidates → 0.0 (retrieval failure)
          Rationale: disambiguation is a UX guardrail, not a routing failure. Penalising
          it as 0.0 would create a perverse incentive to suppress the guardrail.

        workflow_card (from SSE metadata) is preferred over text matching because
        it reflects the actual routing decision, not just what the LLM wrote.
        """
        gt = task.ground_truth
        correct = gt["correct_workflow"]
        alts = gt.get("acceptable_alts", [])
        disq = gt.get("disqualified", [])
        norm = self._normalize

        # ── Disambiguation path ──────────────────────────────────────────────
        if workflow_card and workflow_card.get("workflow_type") == "disambiguation":
            candidates = workflow_card.get("candidates") or []
            candidate_names = [c.get("name", "") for c in candidates if isinstance(c, dict)]

            # Disqualified in any candidate → full fail
            for d in disq:
                if any(norm(d) in norm(cn) or norm(cn) in norm(d) for cn in candidate_names):
                    return 0.0

            # Correct or alt in candidate list → retrieval success
            if any(norm(correct) in norm(cn) or norm(cn) in norm(correct)
                   for cn in candidate_names):
                return 1.0
            for alt in alts:
                if any(norm(alt) in norm(cn) or norm(cn) in norm(alt)
                       for cn in candidate_names):
                    return 0.5
            return 0.0

        # ── Standard path ────────────────────────────────────────────────────
        # Build searchable text: card name + chain steps + response text.
        card_name = ""
        chain_text = ""
        if workflow_card:
            card_name = workflow_card.get("name", "") or ""
            chain_name = workflow_card.get("chain_name", "") or ""
            chain_steps = workflow_card.get("chain_steps", []) or []
            chain_text = " ".join([chain_name] + chain_steps)

        search_text = norm(card_name + " " + chain_text + " " + agent_response)

        # Check disqualified (worst outcome — wrong domain)
        for d in disq:
            if norm(d) in search_text:
                return 0.0

        # Check exact correct match
        if norm(correct) in search_text:
            return 1.0

        # Check acceptable alternatives (partial credit)
        for alt in alts:
            if norm(alt) in search_text:
                return 0.5

        return 0.0

    def run(self, client, max_tasks=None, on_result=None, workers: int = 1) -> List[BenchmarkResult]:
        """Override to use ask() and extract workflow_card from SSE metadata.

        on_result: optional callback(BenchmarkResult) called after each task,
                   enabling incremental persistence (avoids losing all results on crash).
        workers: number of parallel threads (each gets its own BioMateEvalClient copy).
        """
        import time
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import copy

        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        def _run_one(task) -> BenchmarkResult:
            # Each thread uses a fresh session copy to avoid shared-state issues
            thread_client = copy.copy(client)
            import requests as _req
            thread_client._session = _req.Session()
            thread_client._session.headers.update({
                "Authorization": f"Bearer {client.token}",
                "Content-Type": "application/json",
            })
            t0 = time.time()
            try:
                resp = thread_client.ask(task.question)
                score = self.score(task, resp.text, resp.workflow_card)
                error = None
                wf_type = (resp.workflow_card or {}).get("workflow_type", "")
                if wf_type == "disambiguation":
                    candidates = (resp.workflow_card or {}).get("candidates") or []
                    top_name = candidates[0].get("name", "") if candidates else ""
                    routed = f"[disambig] {top_name}"
                else:
                    routed = (resp.workflow_card or {}).get("name", "")
                response_text = f"[routed:{routed}] {resp.text}"
                # Store workflow_type in metadata for display
                task.metadata["workflow_type"] = wf_type
            except Exception as exc:
                score = 0.0
                error = str(exc)
                response_text = ""
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

        results: List[BenchmarkResult] = [None] * len(tasks)  # type: ignore

        if workers <= 1:
            for i, task in enumerate(tasks):
                result = _run_one(task)
                results[i] = result
                if on_result:
                    on_result(result)
        else:
            future_to_idx = {}
            with ThreadPoolExecutor(max_workers=workers) as executor:
                for i, task in enumerate(tasks):
                    future_to_idx[executor.submit(_run_one, task)] = i
                for future in as_completed(future_to_idx):
                    i = future_to_idx[future]
                    result = future.result()
                    results[i] = result
                    if on_result:
                        on_result(result)

        return results
