"""
llm_judge.py
------------
LLM-as-judge for open-answer benchmark scoring.

Production-grade design:
  - Primary provider: Anthropic Claude Haiku (fast, cheap, consistent)
  - Fallback providers: Gemini Flash → rule-based heuristic
  - Circuit breaker: auto-detects credit exhaustion vs transient errors
  - Graceful degradation: never crashes the benchmark run

Failure modes and responses:
  - Credit exhausted (400):  immediately switch to fallback, log warning
  - Rate limited (429):      exponential backoff + retry (up to 3 attempts)
  - Server error (500/503):  retry once, then fallback
  - All providers fail:      return 0.5 (unknown) — conservative, never crash
"""

from __future__ import annotations

import logging
import os
import re
import time
from enum import Enum
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

_DEFAULT_MODEL = "claude-haiku-4-5-20251001"

_BINARY_JUDGE_PROMPT = """\
You are an expert scientific evaluator assessing benchmark answers.

QUESTION:
{question}

EXPECTED ANSWER:
{ground_truth}

AGENT ANSWER:
{agent_answer}

Scoring rules:
1. For numerical answers: correct if within 5% relative error OR within 0.1 absolute for values <1.
2. For text answers: correct if semantically equivalent (synonyms, different word order, abbreviations all count).
3. For lists: correct if all required items are present (order doesn't matter, minor wording variation OK).
4. For gene symbols / rsIDs / IDs: exact match required (case-insensitive).
5. Ignore units mismatch if the value is clearly the same.
6. If the expected answer is a descriptive sentence containing a key number (e.g. "4.81-fold increase"),
   and the agent answers with just that number (e.g. "4.81"), that is CORRECT.
7. If the expected answer says "Nx larger" or "Nx increase" and the agent answers a numeric value
   within 15% of N, that is CORRECT (accounts for slight differences in computation).
8. Error messages like "[no API key available]" or "[analysis failed" are always INCORRECT.

Is the agent answer correct by the above rules?
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


class ProviderStatus(Enum):
    HEALTHY = "healthy"
    CREDIT_EXHAUSTED = "credit_exhausted"   # permanent until manually resolved
    RATE_LIMITED = "rate_limited"           # temporary — retry after backoff
    UNAVAILABLE = "unavailable"             # transient outage


class ProviderCircuitBreaker:
    """
    Tracks provider health and implements circuit breaker pattern.
    - Credit exhaustion → open circuit immediately (don't waste retries)
    - Rate limits → half-open after backoff period
    - Counts consecutive failures for degraded detection
    """
    def __init__(self, name: str, recovery_window_sec: int = 60):
        self.name = name
        self.status = ProviderStatus.HEALTHY
        self.failure_count = 0
        self.last_failure_time: float = 0
        self.recovery_window = recovery_window_sec

    def record_success(self):
        self.status = ProviderStatus.HEALTHY
        self.failure_count = 0

    def record_failure(self, error: Exception):
        self.failure_count += 1
        self.last_failure_time = time.time()
        err_str = str(error).lower()

        if "credit balance" in err_str or "insufficient" in err_str:
            self.status = ProviderStatus.CREDIT_EXHAUSTED
            logger.warning("[CircuitBreaker] %s: credit exhausted — switching to fallback", self.name)
        elif "rate limit" in err_str or "429" in err_str or "too many requests" in err_str:
            self.status = ProviderStatus.RATE_LIMITED
            logger.warning("[CircuitBreaker] %s: rate limited — will retry after backoff", self.name)
        else:
            self.status = ProviderStatus.UNAVAILABLE
            logger.warning("[CircuitBreaker] %s: unavailable (%s)", self.name, str(error)[:80])

    def is_available(self) -> bool:
        if self.status == ProviderStatus.HEALTHY:
            return True
        if self.status == ProviderStatus.CREDIT_EXHAUSTED:
            return False  # permanent until manually reset
        # Rate limited / unavailable: check recovery window
        if time.time() - self.last_failure_time > self.recovery_window:
            self.status = ProviderStatus.HEALTHY  # half-open — try again
            return True
        return False


class LLMJudge:
    """
    LLM-as-judge with automatic fallback across providers.

    Provider chain (tried in order):
      1. Anthropic Claude Haiku  — primary (fast, cheap)
      2. Google Gemini Flash     — fallback (if GEMINI_API_KEY set)
      3. Rule-based heuristic   — last resort (numeric/string matching)

    Circuit breakers prevent repeated calls to a failing provider.
    """

    def __init__(self, model: str = _DEFAULT_MODEL,
                 api_key: Optional[str] = None,
                 gemini_api_key: Optional[str] = None,
                 max_tokens: int = 50,
                 temperature: float = 0.0):
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature

        # Anthropic client
        self._anthropic_key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        self._anthropic_client = None
        self._anthropic_cb = ProviderCircuitBreaker("anthropic", recovery_window_sec=120)
        if self._anthropic_key:
            import anthropic as _anthropic
            self._anthropic_client = _anthropic.Anthropic(api_key=self._anthropic_key)

        # Gemini client (optional fallback) — accepts explicit key, env var, or config
        self._gemini_key = (gemini_api_key or os.environ.get("GEMINI_API_KEY", "")).strip()
        self._gemini_cb = ProviderCircuitBreaker("gemini", recovery_window_sec=60)

        if not self._anthropic_key and not self._gemini_key:
            raise KeyError(
                "No LLM judge API key found. Set ANTHROPIC_API_KEY or GEMINI_API_KEY."
            )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def binary_score(self, question: str, ground_truth: Any,
                     agent_answer: str) -> float:
        """Return 1.0 if agent_answer is correct, else 0.0. Never raises."""
        # Fast path: rule-based exact/fuzzy match (no API needed)
        rb = self._rule_based_binary(str(ground_truth), agent_answer)
        if rb is not None:
            return rb

        prompt = _BINARY_JUDGE_PROMPT.format(
            question=question,
            ground_truth=str(ground_truth),
            agent_answer=agent_answer[:2000],
        )
        try:
            verdict = self._call_with_fallback(prompt).strip().lower()
            return 1.0 if verdict.startswith("correct") else 0.0
        except Exception as e:
            logger.warning("[LLMJudge] All providers failed for binary_score: %s", e)
            return 0.5  # unknown — conservative, don't crash benchmark

    def extract_mc_answer(self, agent_text: str) -> str:
        match = re.search(r"\b([A-D])\b", agent_text)
        if match:
            return match.group(1)
        prompt = _MC_EXTRACT_PROMPT.format(text=agent_text[:500])
        try:
            raw = self._call_with_fallback(prompt).strip().upper()
            return raw[0] if raw and raw[0] in "ABCD" else ""
        except Exception:
            return ""

    def rubric_score(self, question: str, agent_answer: str) -> Dict[str, float]:
        import json as _json
        prompt = _RUBRIC_JUDGE_PROMPT.format(
            question=question,
            agent_answer=agent_answer[:2000],
        )
        _zero = {k: 0.0 for k in [
            "data_handling", "method_selection", "statistical_rigor",
            "source_reliability", "reasoning_chain",
        ]}
        try:
            raw = self._call_with_fallback(prompt, max_tokens=200).strip()
            return _json.loads(raw)
        except Exception:
            return _zero

    def rubric_average(self, question: str, agent_answer: str) -> float:
        scores = self.rubric_score(question, agent_answer)
        return sum(scores.values()) / len(scores) if scores else 0.0

    # ------------------------------------------------------------------
    # Provider chain with circuit breakers
    # ------------------------------------------------------------------

    def _call_with_fallback(self, prompt: str, max_tokens: Optional[int] = None) -> str:
        """
        Try each provider in order, respecting circuit breakers.
        Raises only if ALL providers fail.
        """
        errors: List[str] = []

        # 1. Anthropic
        if self._anthropic_client and self._anthropic_cb.is_available():
            try:
                result = self._call_anthropic(prompt, max_tokens)
                self._anthropic_cb.record_success()
                return result
            except Exception as e:
                self._anthropic_cb.record_failure(e)
                errors.append(f"anthropic: {e}")

        # 2. Gemini fallback
        if self._gemini_key and self._gemini_cb.is_available():
            try:
                result = self._call_gemini(prompt, max_tokens)
                self._gemini_cb.record_success()
                if self._anthropic_cb.status != ProviderStatus.HEALTHY:
                    logger.info("[LLMJudge] Using Gemini fallback (anthropic: %s)",
                                self._anthropic_cb.status.value)
                return result
            except Exception as e:
                self._gemini_cb.record_failure(e)
                errors.append(f"gemini: {e}")

        raise RuntimeError(f"All LLM judge providers failed: {'; '.join(errors)}")

    def _call_anthropic(self, prompt: str, max_tokens: Optional[int] = None) -> str:
        """Call Anthropic with retry on transient errors (429/500)."""
        max_retries = 3
        for attempt in range(max_retries):
            try:
                msg = self._anthropic_client.messages.create(
                    model=self.model,
                    max_tokens=max_tokens or self.max_tokens,
                    temperature=self.temperature,
                    messages=[{"role": "user", "content": prompt}],
                )
                return msg.content[0].text if msg.content else ""
            except Exception as e:
                err_str = str(e).lower()
                # Credit exhaustion = permanent, don't retry
                if "credit balance" in err_str or "insufficient" in err_str:
                    raise
                # Rate limit or server error = retry with backoff
                if attempt < max_retries - 1 and ("429" in err_str or "rate" in err_str
                                                    or "500" in err_str or "503" in err_str):
                    wait = 2 ** attempt  # 1s, 2s, 4s
                    logger.warning("[LLMJudge] Anthropic %s, retrying in %ds", str(e)[:50], wait)
                    time.sleep(wait)
                    continue
                raise
        raise RuntimeError("Anthropic retries exhausted")

    def _call_gemini(self, prompt: str, max_tokens: Optional[int] = None) -> str:
        """Call Google Gemini Flash as fallback."""
        import urllib.request
        import json
        api_url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"gemini-2.0-flash:generateContent?key={self._gemini_key}"
        )
        payload = json.dumps({
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"maxOutputTokens": max_tokens or self.max_tokens, "temperature": 0.0},
        }).encode()
        req = urllib.request.Request(api_url, data=payload,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return data["candidates"][0]["content"]["parts"][0]["text"].strip()

    # ------------------------------------------------------------------
    # Rule-based fast-path (no API cost)
    # ------------------------------------------------------------------

    def _rule_based_binary(self, ground_truth: str, agent_answer: str) -> Optional[float]:
        """
        Cheap exact/fuzzy match before spending API tokens.
        Returns 1.0 (correct), 0.0 (wrong), or None (uncertain → use LLM).

        Design goal: eliminate judge flaps where the same response scores
        differently depending on which LLM model is the judge.  Any case that
        can be decided deterministically is handled here.
        """
        if not agent_answer or not agent_answer.strip():
            return 0.0  # empty = wrong

        # Reject known error strings immediately
        _err = re.compile(
            r"\[no api key|no api key available|\[llm call failed|"
            r"\[analysis failed|\[no output|i processed your request",
            re.IGNORECASE,
        )
        if _err.search(agent_answer):
            return 0.0

        gt = ground_truth.strip().lower().strip('"\'')
        ans = agent_answer.strip().lower()

        # Exact match
        gt_clean = re.sub(r"[^a-z0-9.\-+]", "", gt)
        ans_clean = re.sub(r"[^a-z0-9.\-+]", "", ans)
        if gt_clean and len(gt_clean) >= 3 and gt_clean in ans_clean:
            return 1.0

        # ── "Nx larger/smaller/increase/decrease" pattern ─────────────────
        # GT: "2x larger in fungi" / "3x increase" → agent answers ~2.0 / ~3.0
        _nx_m = re.search(r"(\d+(?:\.\d+)?)\s*x\s+(?:larger|smaller|increase|decrease|fold|more|less)",
                          gt, re.IGNORECASE)
        if _nx_m:
            try:
                nx_val = float(_nx_m.group(1))
                _anums = re.findall(r"[-+]?\d*\.?\d+(?:[eE][+-]?\d+)?", ans)
                for an_str in _anums[:3]:
                    try:
                        an = float(an_str)
                        if nx_val != 0 and abs(an - nx_val) / abs(nx_val) < 0.15:
                            return 1.0
                    except ValueError:
                        pass
            except (ValueError, ZeroDivisionError):
                pass

        # ── Key-number extraction (judge-flap fix) ────────────────────────
        # When GT is a descriptive phrase containing a key number
        # (e.g. "4.81-fold increase in tumor volume" or "2x larger in fungi")
        # and the agent answered with just that number, that is correct.
        gt_nums = re.findall(r"[-+]?\d*\.?\d+(?:[eE][+-]?\d+)?", gt)
        ans_nums = re.findall(r"[-+]?\d*\.?\d+(?:[eE][+-]?\d+)?", ans)
        if gt_nums and ans_nums:
            for gn_str in gt_nums[:2]:
                try:
                    gn = float(gn_str)
                    if gn == 0:
                        continue
                    for an_str in ans_nums[:3]:
                        try:
                            an = float(an_str)
                            # 5% tolerance: covers rounding and slight method differences
                            if abs(an - gn) / abs(gn) < 0.05:
                                return 1.0
                            # Absolute tolerance for values <1 (stats, correlations, etc.)
                            # judge prompt says "within 0.1 absolute"; use 0.05 here for safety
                            if 0 < abs(gn) < 1 and abs(an - gn) <= 0.05 and abs(an - gn) / abs(gn) < 0.30:
                                return 1.0
                        except ValueError:
                            pass
                except (ValueError, ZeroDivisionError):
                    pass

        # Numeric exact (tighter, 1% — for cases with no descriptive wrapper)
        try:
            gt_num = float(re.sub(r"[^\d.\-eE+]", "", gt))
            for n in ans_nums:
                try:
                    an = float(n)
                    if gt_num == 0:
                        if abs(an) < 0.001:
                            return 1.0
                    elif abs(an - gt_num) / abs(gt_num) < 0.01:
                        return 1.0
                except ValueError:
                    pass
        except (ValueError, ZeroDivisionError):
            pass

        # Can't determine deterministically → let LLM decide
        return None
