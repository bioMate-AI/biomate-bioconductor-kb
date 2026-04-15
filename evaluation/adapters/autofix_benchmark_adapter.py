"""
AutofixBenchmarkAdapter — Tests BioMate's error diagnosis and fix-planning capability.

Each case presents a broken workflow state (params + error log) via BioMate's
/api/workflows/explain_error endpoint (or chat) and checks whether the response:
  1. Correctly identifies the root cause category
  2. Proposes the right fix action
  3. Does NOT hallucinate a fix for the wrong problem

Scoring uses LLM judge (Haiku) for free-text evaluation.

Categories:
  - genome_mismatch (5 cases): hg38/hg19 mismatches, index/annotation mismatches
  - missing_input  (5 cases): missing files, S3 path errors, required params absent
  - param_type_error (5 cases): string→int coercions, boolean type errors
  - resource_failure (5 cases): OOM, timeout, disk full

Usage:
    adapter = AutofixBenchmarkAdapter(config)
    results = adapter.run(client, max_tasks=None)
"""

import time
from pathlib import Path
from typing import Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult
from evaluation.core.llm_judge import LLMJudge

_DATASET_PATH = Path(__file__).parent.parent / "datasets" / "autofix_benchmark" / "cases.yaml"

# System prompt sent to BioMate for each case
_SYSTEM_PROMPT = """\
You are BioMate, a bioinformatics workflow assistant. A user's workflow has failed.
Diagnose the root cause and describe the specific fix they should apply.
Be concise: 1–3 sentences max. State the exact parameter change or action needed.
"""

_CASE_PROMPT_TEMPLATE = """\
A {workflow} workflow failed with the following error. Diagnose the problem and state the exact fix.

Workflow parameters:
{params}

Error log:
{error_log}

What is the root cause and the specific fix?
"""

# LLM judge scoring prompt
_JUDGE_PROMPT_TEMPLATE = """\
A bioinformatics workflow failed and an AI assistant was asked to diagnose it.

CASE: {description}
EXPECTED FIX: {expected_fix}
AI RESPONSE: {ai_response}

Score the AI's response on two criteria:
1. Root cause identification: Did the AI correctly identify the root cause category ({category})?
2. Fix accuracy: Did the AI propose a fix that matches or is equivalent to the expected fix?

Respond with a JSON object:
{{"root_cause_correct": true/false, "fix_correct": true/false, "explanation": "brief note"}}

Only output valid JSON, nothing else.
"""


class AutofixBenchmarkAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for autofix diagnostic capability.

    Does NOT run actual broken workflows — instead tests BioMate's
    error diagnosis and fix-planning via the chat/explain_error API.
    """

    def __init__(self, config: dict):
        super().__init__(config)
        self._cases: list[dict] = []
        llm_config = config.get("llm_judge", {})
        try:
            self._judge = LLMJudge(
                model=llm_config.get("model", "claude-haiku-4-5-20251001"),
                api_key=llm_config.get("api_key"),  # None → falls back to ANTHROPIC_API_KEY env var
                max_tokens=llm_config.get("max_tokens", 200),
                temperature=llm_config.get("temperature", 0.0),
            )
        except (KeyError, Exception):
            self._judge = None  # fallback to keyword scoring when no API key

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """Score via LLM judge — used by base class run() if not overriding."""
        return self._score_response(
            ai_response=agent_response,
            expected_fix=str(task.ground_truth),
            category=task.metadata.get("category", "unknown"),
            description=task.metadata.get("description", ""),
        )

    def load_tasks(self) -> list[BenchmarkTask]:
        with open(_DATASET_PATH) as f:
            data = yaml.safe_load(f)

        tasks = []
        for case in data["cases"]:
            params_str = "\n".join(f"  {k}: {v}" for k, v in case["params"].items())
            prompt = _CASE_PROMPT_TEMPLATE.format(
                workflow=case["workflow"],
                params=params_str,
                error_log=case["error_log"].strip(),
            )
            task = BenchmarkTask(
                task_id=case["id"],
                question=prompt,
                ground_truth=case["expected_fix"],
                metadata={
                    "category": case["category"],
                    "workflow": case["workflow"],
                    "description": case["description"],
                    "expected_fixer_class": case.get("expected_fixer_class", ""),
                    "fix_difficulty": case.get("fix_difficulty", "medium"),
                    "benchmark": "autofix_benchmark",
                },
            )
            tasks.append(task)
        return tasks

    def run(self, client, max_tasks: Optional[int] = None) -> list[BenchmarkResult]:
        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        results = []
        for i, task in enumerate(tasks):
            print(f"  [{i+1}/{len(tasks)}] {task.task_id} ({task.metadata['category']}) ...", end=" ", flush=True)
            t0 = time.time()

            # Send to BioMate
            try:
                response = client.ask(task.question)
                ai_response = response.text if hasattr(response, "text") else str(response)
            except Exception as exc:
                print(f"ERROR: {exc}")
                results.append(BenchmarkResult(
                    task_id=task.task_id,
                    benchmark="autofix_benchmark",
                    score=0.0,
                    agent_response="",
                    ground_truth=task.ground_truth,
                    latency_sec=time.time() - t0,
                    error=str(exc),
                    metadata=task.metadata,
                ))
                continue

            # Score with LLM judge
            score = self._score_response(
                ai_response=ai_response,
                expected_fix=task.ground_truth,
                category=task.metadata["category"],
                description=task.metadata["description"],
            )
            elapsed = time.time() - t0

            indicator = "✓" if score >= 0.75 else ("~" if score >= 0.4 else "✗")
            print(f"{indicator} score={score:.2f} ({elapsed:.0f}s)")

            results.append(BenchmarkResult(
                task_id=task.task_id,
                benchmark="autofix_benchmark",
                score=score,
                agent_response=ai_response[:2000],
                ground_truth=task.ground_truth,
                latency_sec=elapsed,
                metadata=task.metadata,
            ))

        return results

    def _score_response(
        self,
        ai_response: str,
        expected_fix: str,
        category: str,
        description: str,
    ) -> float:
        """
        Score the AI response using LLM judge.
        Returns 0.0–1.0: 1.0 = both root cause and fix correct,
                         0.5 = root cause correct but fix wrong/partial,
                         0.0 = wrong root cause.
        """
        judge_prompt = _JUDGE_PROMPT_TEMPLATE.format(
            description=description,
            expected_fix=expected_fix,
            ai_response=ai_response[:1500],
            category=category,
        )
        if self._judge is None:
            return self._keyword_score(ai_response, expected_fix)
        try:
            judge_response = self._judge._call(judge_prompt, max_tokens=200)
            import json, re
            # Extract JSON from response
            json_match = re.search(r'\{[^{}]+\}', judge_response, re.DOTALL)
            if json_match:
                verdict = json.loads(json_match.group())
                root_cause_ok = bool(verdict.get("root_cause_correct", False))
                fix_ok = bool(verdict.get("fix_correct", False))
                if root_cause_ok and fix_ok:
                    return 1.0
                elif root_cause_ok:
                    return 0.5
                else:
                    return 0.0
        except Exception as exc:
            # Fallback: keyword match
            return self._keyword_score(ai_response, expected_fix)

        return 0.0

    def _keyword_score(self, ai_response: str, expected_fix: str) -> float:
        """Fallback scorer: check if key terms from expected fix appear in response."""
        response_lower = ai_response.lower()
        # Extract key terms from expected fix (words >4 chars, not stopwords)
        stopwords = {"with", "from", "this", "that", "should", "must", "using", "when", "into"}
        terms = [w.lower() for w in expected_fix.split() if len(w) > 4 and w.lower() not in stopwords]
        if not terms:
            return 0.0
        hits = sum(1 for t in terms if t in response_lower)
        return min(1.0, hits / max(1, len(terms) * 0.6))
