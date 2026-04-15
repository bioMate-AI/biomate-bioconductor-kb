"""
memory_benchmark_adapter.py
---------------------------
BioMate Memory Benchmark adapter.

Tests whether P1 (episode memory injection) and P2 (correction routing injection)
actually shape LLM responses, aligned with the LongMemEval / LoCoMo / BABILong taxonomy.

Scenario types:
  recall      (MB-A) — LongMemEval: information extraction
  correction  (MB-B) — LongMemEval: knowledge update
  baseline    (MB-C) — LongMemEval: abstention (no pollution)
  temporal    (MB-T) — LongMemEval: temporal reasoning
  synthesis   (MB-S) — LongMemEval: multi-session reasoning / LoCoMo multi-hop
  adversarial (MB-X) — BABILong adversarial + LongMemEval abstention

Scoring:
  recall, temporal, synthesis: 1.0 if expected_recall terms found, 0.0 otherwise
  correction: 1.0 if expected_workflow found AND disqualified absent; 0.5 if expected found
              but disqualified also present; 0.0 if expected absent
  baseline: 1.0 if expected_workflow found, 0.0 otherwise
  adversarial: 1.0 if contamination_forbidden absent (or acceptable abstention phrase present);
               0.0 if hallucination/contamination detected

Setup:
  prepare(client)  — creates eval project, seeds episodes + corrections via API
  teardown(client) — currently no cleanup (seeded data is tiny; eval DB is ephemeral)

Dataset: evaluation/datasets/memory_benchmark/scenarios.yaml
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult


DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "memory_benchmark" / "scenarios.yaml"
)


class MemoryBenchmarkAdapter(BenchmarkAdapter):
    """
    BioMate-unique benchmark: episodic memory injection and correction routing.

    BioMate target: ≥75% overall weighted score.
    Type weights: A=30%, B=25%, C=15%, T=10%, S=10%, X=10%
    """

    name = "memory_benchmark"

    # Benchmark-specific type weights for weighted overall score
    TYPE_WEIGHTS = {
        "recall": 0.30,
        "correction": 0.25,
        "baseline": 0.15,
        "temporal": 0.10,
        "synthesis": 0.10,
        "adversarial": 0.10,
    }

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self._seeded_project_id: Optional[str] = None
        self._seed_results: Dict[str, Any] = {}

    # ------------------------------------------------------------------
    # Load tasks
    # ------------------------------------------------------------------

    def load_tasks(self) -> List[BenchmarkTask]:
        data = yaml.safe_load(DATASET_PATH.read_text())
        tasks = []
        for item in data:
            tasks.append(BenchmarkTask(
                task_id=f"memory__{item['id']}",
                question=item["query"].strip(),
                ground_truth={
                    "type": item["type"],
                    "expected_recall": item.get("expected_recall", []),
                    "expected_workflow": item.get("expected_workflow", []),
                    "disqualified_workflow": item.get("disqualified_workflow", []),
                    "contamination_forbidden": item.get("contamination_forbidden", []),
                    "expected_behavior": item.get("expected_behavior"),
                    "acceptable_responses": item.get("acceptable_responses", []),
                },
                domain=item.get("domain", "life_science"),
                difficulty=item.get("difficulty", "medium"),
                task_type="multi_turn",
                answer_type="open",
                metadata={
                    "id": item["id"],
                    "description": item.get("description", ""),
                    "seed_episode": item.get("seed_episode"),
                    "seed_episode_2": item.get("seed_episode_2"),
                    "seed_correction": item.get("seed_correction"),
                    "notes": item.get("notes", ""),
                },
            ))
        return tasks

    # ------------------------------------------------------------------
    # Prepare: seed all episodes and corrections before any tasks run
    # ------------------------------------------------------------------

    def prepare(self, client) -> None:
        """
        1. Create (or reuse) a dedicated memory-benchmark project.
        2. Seed episodes and corrections for each scenario that has seed data.
        """
        base = client.base_url
        headers = client._session.headers

        # Create project
        proj_resp = client._session.post(
            f"{base}/api/memory/projects",
            json={
                "name": "Memory Benchmark Eval",
                "description": "Auto-created by memory_benchmark_adapter — safe to delete",
                "primaryDomain": "multi_domain",
            },
            timeout=15,
        )
        if proj_resp.status_code in (200, 201):
            self._seeded_project_id = proj_resp.json().get("id")
        else:
            print(
                f"[MemoryBenchmark] WARNING: Could not create project "
                f"(status {proj_resp.status_code}). "
                f"Seeded episode assertions will still run but may all score 0."
            )
            return

        pid = self._seeded_project_id

        # Load scenarios to seed
        scenarios = yaml.safe_load(DATASET_PATH.read_text())

        for sc in scenarios:
            task_id = f"memory__{sc['id']}"
            seeded = {"episodes": [], "correction": None}

            # Seed first episode
            ep1 = sc.get("seed_episode")
            if ep1:
                ep1_id = self._seed_episode(client, pid, ep1)
                if ep1_id:
                    seeded["episodes"].append(ep1_id)

            # Seed second episode (temporal / synthesis scenarios)
            ep2 = sc.get("seed_episode_2")
            if ep2:
                # Small delay so timestamps differ (temporal ordering tests)
                time.sleep(0.3)
                ep2_id = self._seed_episode(client, pid, ep2)
                if ep2_id:
                    seeded["episodes"].append(ep2_id)

            # Seed correction
            corr = sc.get("seed_correction")
            if corr:
                corr_id = self._seed_correction(client, pid, corr)
                seeded["correction"] = corr_id

            self._seed_results[task_id] = seeded

        total_ep = sum(len(v["episodes"]) for v in self._seed_results.values())
        total_corr = sum(1 for v in self._seed_results.values() if v["correction"])
        print(
            f"[MemoryBenchmark] Seeded {total_ep} episodes and {total_corr} corrections "
            f"into project {pid}"
        )

    def _seed_episode(self, client, project_id: str, ep: Dict[str, Any]) -> Optional[int]:
        """POST an episode to the eval project. Returns episode ID or None."""
        payload = {
            "userQuery": ep.get("userQuery", ""),
            "assistantResponse": ep.get("assistantResponse", ""),
            "workflowGenerated": ep.get("workflowGenerated", True),
            "outcomeSuccess": ep.get("outcomeSuccess"),
            "whatWorked": ep.get("whatWorked", []),
            "whatFailed": ep.get("whatFailed", []),
            "lessonsLearned": ep.get("lessonsLearned", []),
            "importanceScore": ep.get("importanceScore", 0.5),
        }
        try:
            resp = client._session.post(
                f"{client.base_url}/api/memory/projects/{project_id}/episodes",
                json=payload,
                timeout=10,
            )
            if resp.status_code in (200, 201):
                return resp.json().get("id")
            print(f"[MemoryBenchmark] Episode seed failed (status {resp.status_code}): {resp.text[:200]}")
        except Exception as e:
            print(f"[MemoryBenchmark] Episode seed error: {e}")
        return None

    def _seed_correction(self, client, project_id: str, corr: Dict[str, Any]) -> Optional[int]:
        """POST a correction to the user's correction log. Returns correction ID or None."""
        payload = {
            "projectId": project_id,
            "suggestedApproach": corr.get("suggestedApproach"),
            "correctedApproach": corr.get("correctedApproach"),
            "userExplanation": corr.get("userExplanation", ""),
        }
        try:
            resp = client._session.post(
                f"{client.base_url}/api/memory/user/corrections",
                json=payload,
                timeout=10,
            )
            if resp.status_code in (200, 201):
                return resp.json().get("id")
            print(f"[MemoryBenchmark] Correction seed failed (status {resp.status_code}): {resp.text[:200]}")
        except Exception as e:
            print(f"[MemoryBenchmark] Correction seed error: {e}")
        return None

    # ------------------------------------------------------------------
    # POST episode (public endpoint, used by prepare)
    # ------------------------------------------------------------------

    def _create_episode(self, client, project_id: str, data: Dict[str, Any]) -> Optional[int]:
        return self._seed_episode(client, project_id, data)

    # ------------------------------------------------------------------
    # Scoring
    # ------------------------------------------------------------------

    @staticmethod
    def _normalize(s: str) -> str:
        return s.lower().replace("-", " ").replace("_", " ")

    def score(
        self,
        task: BenchmarkTask,
        agent_response: str,
        workflow_card: Optional[Dict[str, Any]] = None,
    ) -> float:
        gt = task.ground_truth
        scenario_type = gt.get("type", "baseline")
        resp_norm = self._normalize(agent_response)

        # ------------------------------------------------------------------
        # recall / temporal / synthesis — did the LLM surface expected terms?
        # ------------------------------------------------------------------
        if scenario_type in ("recall", "temporal", "synthesis"):
            expected = [self._normalize(t) for t in gt.get("expected_recall", [])]
            if not expected:
                return 0.5  # no assertion defined — neutral
            for term in expected:
                if term in resp_norm:
                    return 1.0
            return 0.0

        # ------------------------------------------------------------------
        # correction — did routing land on the corrected workflow?
        # ------------------------------------------------------------------
        if scenario_type == "correction":
            expected_wf = [self._normalize(w) for w in gt.get("expected_workflow", [])]
            disqualified = [self._normalize(w) for w in gt.get("disqualified_workflow", [])]

            # Check workflow card first (more reliable than response text)
            wf_name_norm = ""
            if workflow_card and workflow_card.get("name"):
                wf_name_norm = self._normalize(str(workflow_card["name"]))

            expected_found = any(w in resp_norm or w in wf_name_norm for w in expected_wf)
            disqualified_found = any(w in resp_norm or w in wf_name_norm for w in disqualified)

            if expected_found and not disqualified_found:
                return 1.0
            if expected_found and disqualified_found:
                return 0.5
            return 0.0

        # ------------------------------------------------------------------
        # baseline — routing correctness (regression test)
        # ------------------------------------------------------------------
        if scenario_type == "baseline":
            expected_wf = [self._normalize(w) for w in gt.get("expected_workflow", [])]
            wf_name_norm = ""
            if workflow_card and workflow_card.get("name"):
                wf_name_norm = self._normalize(str(workflow_card["name"]))
            if any(w in resp_norm or w in wf_name_norm for w in expected_wf):
                return 1.0
            return 0.0

        # ------------------------------------------------------------------
        # adversarial — no hallucination, no cross-domain contamination
        # ------------------------------------------------------------------
        if scenario_type == "adversarial":
            forbidden = [self._normalize(f) for f in gt.get("contamination_forbidden", [])]
            acceptable = [self._normalize(a) for a in gt.get("acceptable_responses", [])]

            # Any forbidden contamination = fail
            for f in forbidden:
                if f in resp_norm:
                    return 0.0

            # For abstention scenarios: must contain an acceptable abstain phrase
            if gt.get("expected_behavior") == "abstain":
                for a in acceptable:
                    if a in resp_norm:
                        return 1.0
                # No acceptable phrase but also no hallucination — partial credit
                return 0.5

            # Non-abstention adversarial: no contamination = pass
            return 1.0

        # Unknown type — neutral
        return 0.5

    # ------------------------------------------------------------------
    # Summary stats
    # ------------------------------------------------------------------

    @classmethod
    def compute_weighted_score(cls, results: List[BenchmarkResult]) -> Dict[str, Any]:
        """Compute per-type accuracy and weighted overall score."""
        by_type: Dict[str, List[float]] = {}
        for r in results:
            sc_type = r.metadata.get("scenario_type", "baseline")
            by_type.setdefault(sc_type, []).append(r.score)

        per_type_avg: Dict[str, float] = {
            t: sum(scores) / len(scores) for t, scores in by_type.items()
        }

        weighted = 0.0
        total_weight = 0.0
        for t, avg in per_type_avg.items():
            w = cls.TYPE_WEIGHTS.get(t, 0.0)
            weighted += avg * w
            total_weight += w
        if total_weight > 0:
            weighted /= total_weight

        return {
            "weighted_overall": weighted,
            "per_type": per_type_avg,
            "by_type_counts": {t: len(s) for t, s in by_type.items()},
        }
