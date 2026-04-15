"""
license_gating_adapter.py
-------------------------
License-Gated Orchestration Benchmark adapter.

Tests correct tool routing under 3 credential scenarios:
  A: full_licenses    (Schrödinger + MOE + Amber all available)
  B: no_licenses      (open-source tools only)
  C: partial_licenses (Schrödinger only)

No competitor has this capability. Target: 100% correct routing (0 silent failures).

Dataset: evaluation/datasets/license_gating/test_cases.yaml

Scoring per test case:
  correct_routing:      1.0 if tool matches scenario's expected tool
  no_silent_failure:    1.0 if system never attempted unavailable tool
  fallback_quality:     1.0 (GOOD) / 0.5 (ACCEPTABLE) / 0.0 (POOR)
  explanation_provided: 1.0 if user was told what's blocked

Final score = mean(correct_routing, no_silent_failure, fallback_quality,
                   explanation_provided)
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult
from ..core.llm_judge import LLMJudge


DATASET_PATH = Path(__file__).parent.parent / "datasets" / "license_gating" / "test_cases.yaml"

SCENARIOS = ["scenario_a", "scenario_b", "scenario_c"]

FALLBACK_QUALITY_SCORES = {"GOOD": 1.0, "ACCEPTABLE": 0.5, "POOR": 0.0}

# Keywords indicating a silent failure (tool attempted but likely unavailable)
SILENT_FAILURE_PATTERNS = [
    "failed to connect to license server",
    "license not found",
    "license error",
    "could not initialize",
    "schrodinger error",
    "moe error",
    "amber error",
]

# Keywords indicating an explanation was given
EXPLANATION_PATTERNS = [
    "not available", "license required", "not licensed",
    "you don't have", "requires a license", "unavailable",
    "alternative", "instead", "fallback",
    "not configured", "requires a", "requires license",
    "free alternative", "free equivalent", "without paying",
    "open.source", "free,", "open source",
]


class LicenseGatingAdapter(BenchmarkAdapter):
    """
    BioMate-unique benchmark: license-gated tool orchestration.

    Runs each test case under all 3 credential scenarios.
    task_id encodes both the case id and scenario: lic_dock_001__scenario_b
    """

    name = "license_gating"

    def __init__(self, config: Dict[str, Any],
                 scenarios: Optional[List[str]] = None):
        super().__init__(config)
        self.scenarios = scenarios or SCENARIOS
        self._judge: Optional[LLMJudge] = None

    def prepare(self, client) -> None:
        self._judge = LLMJudge(model=self.config["llm_judge"]["model"], api_key=self.config.get("llm_judge",{}).get("api_key"))

    def load_tasks(self) -> List[BenchmarkTask]:
        cases = yaml.safe_load(DATASET_PATH.read_text())
        tasks = []
        for case in cases:
            for scenario_key in self.scenarios:
                scenario_data = case.get(scenario_key)
                if not scenario_data:
                    continue
                tasks.append(BenchmarkTask(
                    task_id=f"license_gating__{case['id']}__{scenario_key}",
                    question=case["query"],
                    ground_truth=scenario_data,
                    domain=case.get("domain", "drug_docking"),
                    difficulty="medium",
                    task_type="workflow",
                    answer_type="open",
                    metadata={
                        "case_id": case["id"],
                        "scenario": scenario_key,
                        "required_tools": case.get("required_tools", []),
                        "silent_failure_risk": case.get("silent_failure_risk", "MEDIUM"),
                        "fallback_quality": case.get("scenario_b_fallback_quality", "GOOD"),
                        "full_case": case,
                    },
                ))
        return tasks

    @staticmethod
    def _tool_in_response(tool_id: str, response_lower: str) -> bool:
        """Check if a tool name (as identifier) is referenced in the response text."""
        if not tool_id:
            return False
        # Normalize both to space-separated lowercased words
        needle = tool_id.lower().replace("_", " ").replace("-", " ")
        if needle in response_lower:
            return True
        # Also accept if all key words (>=4 chars) are present in response
        key_words = [w for w in needle.split() if len(w) >= 4]
        if key_words and all(w in response_lower for w in key_words):
            return True
        return False

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        gt = task.ground_truth
        response_lower = agent_response.lower()
        scenario = task.metadata["scenario"]

        # 1. Correct routing score
        # Handle tools_used list (lic_mix_001 has multiple tools)
        if gt.get("tools_used"):
            # At least one of the expected tools should be mentioned
            tools_used = gt["tools_used"]
            hit = any(self._tool_in_response(t, response_lower) for t in tools_used)
            correct_routing = 1.0 if hit else 0.0
        else:
            expected_tool = gt.get("correct_tool") or ""
            if not expected_tool and gt.get("correct_response"):
                # Free-form expected response: check keywords (>=5 chars) present
                words = [w for w in gt["correct_response"].lower().split() if len(w) >= 5]
                correct_routing = 1.0 if words and sum(1 for w in words if w in response_lower) / len(words) >= 0.4 else 0.0
            else:
                correct_routing = 1.0 if self._tool_in_response(expected_tool, response_lower) else 0.0

        # 2. No silent failure score
        silent_failure = any(p in response_lower for p in SILENT_FAILURE_PATTERNS)
        no_silent_failure = 0.0 if silent_failure else 1.0

        # 3. Fallback quality (only applies when scenario_b and explanation needed)
        if scenario == "scenario_b" and gt.get("explanation_needed", False):
            fq_label = task.metadata.get("fallback_quality", "GOOD")
            fallback_quality = FALLBACK_QUALITY_SCORES.get(fq_label, 0.5) * correct_routing
        else:
            fallback_quality = 1.0  # not applicable

        # 4. Explanation provided (when needed)
        needs_explanation = gt.get("explanation_needed", False)
        if needs_explanation:
            explanation_given = any(p in response_lower for p in EXPLANATION_PATTERNS)
            explanation_score = 1.0 if explanation_given else 0.0
        else:
            explanation_score = 1.0  # not required

        return (correct_routing + no_silent_failure + fallback_quality + explanation_score) / 4.0

    def task_prompt(self, task: BenchmarkTask) -> str:
        """Return the raw user question — credential state is set server-side via the API."""
        return task.question

    def run(self, client, max_tasks=None):
        """
        Override run() to set real server-side credentials before each task instead of
        injecting a text prefix.  This exercises the actual credential-aware routing path.
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import time

        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        self.prepare(client)
        results = []

        concurrency = self.config.get("concurrency", {}).get("max_parallel_tasks", 1)
        # Run sequentially when concurrency=1 to avoid credential races between scenarios.
        # Multiple workers in the same scenario are fine, but scenario_a/b/c tasks for the
        # same tool would collide if run concurrently — cap at 1 worker per scenario bucket.

        def _run_one(task):
            t0 = time.time()
            error = None
            response_text = ""
            scenario = task.metadata.get("scenario", "scenario_b")
            try:
                # Set real credentials for this scenario before sending the request
                if hasattr(client, 'set_scenario_credentials'):
                    client.set_scenario_credentials(scenario)
                response = client.ask(self.task_prompt(task))
                # Include workflow card name in scored text so scoring can match
                # the actual routed workflow even when LLM text uses different phrasing.
                wf_card = getattr(response, 'workflow_card', None) or {}
                wf_name = wf_card.get('name', '') or wf_card.get('chain_name', '') if isinstance(wf_card, dict) else ''
                response_text = (
                    f"[WORKFLOW: {wf_name}]\n{response.text}" if wf_name else response.text
                )
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

        # Group tasks by scenario to avoid race conditions when running concurrently
        from itertools import groupby
        from operator import itemgetter

        scenario_groups: dict = {}
        for task in tasks:
            s = task.metadata.get("scenario", "scenario_b")
            scenario_groups.setdefault(s, []).append(task)

        for scenario, s_tasks in sorted(scenario_groups.items()):
            with ThreadPoolExecutor(max_workers=concurrency) as pool:
                futures = {pool.submit(_run_one, t): t for t in s_tasks}
                for future in as_completed(futures):
                    results.append(future.result())

        self.teardown(client)
        return results
