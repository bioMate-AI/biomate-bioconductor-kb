"""
llm_judge.py
------------
LLM-as-judge for open-answer benchmark scoring.

Uses Claude Haiku by default (cheap, fast, consistent).
Returns binary 0.0 / 1.0 for compatibility with all benchmark adapters.

Can also perform:
  - Multiple-choice extraction (extract letter A/B/C/D from free-form text)
  - JSON field extraction (extract a specific field from a JSON-formatted response)
  - Partial-credit rubric scoring (0.0–1.0) for trace-based benchmarks
"""

from __future__ import annotations

import os
import re
from typing import Any, Dict, Optional

import anthropic

_DEFAULT_MODEL = "claude-haiku-4-5-20251001"

_BINARY_JUDGE_PROMPT = """\
You are an expert scientific evaluator.

QUESTION:
{question}

EXPECTED ANSWER:
{ground_truth}

AGENT ANSWER:
{agent_answer}

Is the agent answer correct or equivalent to the expected answer?
Respond with exactly one word: "correct" or "incorrect".
Do not add any explanation."""

_MC_EXTRACT_PROMPT = """\
Extract the answer option letter (A, B, C, or D) from the following text.
Respond with only the single letter.

TEXT:
{text}"""

_RUBRIC_JUDGE_PROMPT = """\
You are an expert scientific evaluator scoring an AI agent's analytical trace.

TASK:
{question}

AGENT TRACE / RESPONSE:
{agent_answer}

Score the response on each of the following dimensions (0.0 to 1.0):
- data_handling: Was the data correctly ingested and preprocessed?
- method_selection: Was the right tool/method chosen for the task?
- statistical_rigor: Were statistical procedures applied correctly?
- source_reliability: Did the agent use authoritative databases/references?
- reasoning_chain: Is the reasoning logically coherent?

Return a JSON object with these five keys and float values, nothing else.
Example: {{"data_handling": 0.8, "method_selection": 1.0, "statistical_rigor": 0.6, "source_reliability": 0.8, "reasoning_chain": 0.9}}"""


class LLMJudge:
    """Wrapper around Claude Haiku for automated benchmark scoring."""

    def __init__(self, model: str = _DEFAULT_MODEL,
                 api_key: Optional[str] = None,
                 max_tokens: int = 50,
                 temperature: float = 0.0):
        self.model = model
        resolved_key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        if not resolved_key:
            raise KeyError(
                "ANTHROPIC_API_KEY not set. Set the env var or add api_key to config.yaml llm_judge section."
            )
        self.client = anthropic.Anthropic(api_key=resolved_key)
        self.max_tokens = max_tokens
        self.temperature = temperature

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def binary_score(self, question: str, ground_truth: Any,
                     agent_answer: str) -> float:
        """Return 1.0 if agent_answer is correct, else 0.0."""
        prompt = _BINARY_JUDGE_PROMPT.format(
            question=question,
            ground_truth=str(ground_truth),
            agent_answer=agent_answer,
        )
        verdict = self._call(prompt).strip().lower()
        return 1.0 if verdict.startswith("correct") else 0.0

    def extract_mc_answer(self, agent_text: str) -> str:
        """
        Extract a multiple-choice letter (A/B/C/D) from free-form text.
        Falls back to regex scan of the raw text if LLM extraction fails.
        """
        # Fast path: regex scan
        match = re.search(r"\b([A-D])\b", agent_text)
        if match:
            return match.group(1)
        # LLM extraction for ambiguous cases
        prompt = _MC_EXTRACT_PROMPT.format(text=agent_text[:500])
        raw = self._call(prompt).strip().upper()
        return raw[0] if raw and raw[0] in "ABCD" else ""

    def rubric_score(self, question: str, agent_answer: str) -> Dict[str, float]:
        """
        Score an agent trace on 5 dimensions (data analysis quality rubric).
        Returns dict with keys: data_handling, method_selection,
        statistical_rigor, source_reliability, reasoning_chain.
        Average of all 5 = overall trace score (0.0–1.0).
        """
        import json as _json
        prompt = _RUBRIC_JUDGE_PROMPT.format(
            question=question,
            agent_answer=agent_answer[:2000],  # cap to avoid token overflow
        )
        raw = self._call(prompt, max_tokens=200).strip()
        try:
            scores = _json.loads(raw)
        except Exception:
            # Fallback: all zeros
            scores = {k: 0.0 for k in [
                "data_handling", "method_selection", "statistical_rigor",
                "source_reliability", "reasoning_chain",
            ]}
        return scores

    def rubric_average(self, question: str, agent_answer: str) -> float:
        """Convenience: return the mean of all 5 rubric dimensions."""
        scores = self.rubric_score(question, agent_answer)
        return sum(scores.values()) / len(scores) if scores else 0.0

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _call(self, prompt: str, max_tokens: Optional[int] = None) -> str:
        msg = self.client.messages.create(
            model=self.model,
            max_tokens=max_tokens or self.max_tokens,
            temperature=self.temperature,
            messages=[{"role": "user", "content": prompt}],
        )
        return msg.content[0].text if msg.content else ""
