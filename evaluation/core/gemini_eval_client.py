"""
gemini_eval_client.py
---------------------
Direct Gemini API client for benchmark evaluation.

Calls the Gemini API directly — bypasses BioMate's pipeline so we measure
raw LLM capability, comparable to bare model baselines.

Usage:
    client = GeminiEvalClient(model="gemini-3-flash-preview")
    resp = client.ask("What is the function of BRCA1?")
    print(resp.text, resp.tokens_per_sec, resp.cost_usd)
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional

import requests

# Gemini 3 Flash Preview pricing (as of 2026-04)
_GEMINI_PRICING: Dict[str, Dict[str, float]] = {
    "gemini-3-flash-preview": {"input_per_1m": 0.075, "output_per_1m": 0.30},
    "gemini-2.0-flash-exp":   {"input_per_1m": 0.075, "output_per_1m": 0.30},
    "gemini-1.5-flash":       {"input_per_1m": 0.075, "output_per_1m": 0.30},
    "gemini-1.5-pro":         {"input_per_1m": 1.25,  "output_per_1m": 5.00},
}
_DEFAULT_PRICING = {"input_per_1m": 0.075, "output_per_1m": 0.30}

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

_SYSTEM_PROMPT = (
    "You are an expert bioinformatics and molecular biology assistant. "
    "Answer questions accurately and concisely. "
    "For multiple-choice questions, state your answer as a single letter (A, B, C, or D) "
    "on the first line, then explain briefly."
)


@dataclass
class GeminiChatResponse:
    text: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_sec: float = 0.0
    tokens_per_sec: float = 0.0
    cost_usd: float = 0.0
    hw_cost_usd: float = 0.0    # always 0 for cloud API
    error: Optional[str] = None


class GeminiEvalClient:
    """
    Direct Gemini REST client for eval benchmarking.
    Mirrors OllamaEvalClient's interface for drop-in use in benchmark runners.
    """

    def __init__(
        self,
        model: str = "gemini-3-flash-preview",
        api_key: Optional[str] = None,
        timeout: float = 120.0,
        max_tokens: int = 1024,
        temperature: float = 0.0,
        system_prompt: str = _SYSTEM_PROMPT,
    ):
        self.model = model
        self.api_key = api_key or os.environ.get("GEMINI_API_KEY", "")
        self.timeout = timeout
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.system_prompt = system_prompt
        self._pricing = _GEMINI_PRICING.get(model, _DEFAULT_PRICING)
        self._session = requests.Session()
        self._session.headers.update({"Content-Type": "application/json"})

    # ------------------------------------------------------------------
    # Public API (mirrors OllamaEvalClient / BioMateEvalClient shape)
    # ------------------------------------------------------------------

    def ask(self, question: str, **kwargs) -> GeminiChatResponse:
        """Send a single-turn question and return a structured response."""
        if not self.api_key:
            return GeminiChatResponse(
                text="", model=self.model, error="GEMINI_API_KEY not set"
            )

        url = (f"{GEMINI_BASE_URL}/models/{self.model}:generateContent"
               f"?key={self.api_key}")

        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": f"{self.system_prompt}\n\n{question}"}],
                }
            ],
            "generationConfig": {
                "maxOutputTokens": kwargs.get("max_tokens", self.max_tokens),
                "temperature": kwargs.get("temperature", self.temperature),
                "candidateCount": 1,
            },
        }

        t0 = time.time()
        try:
            resp = self._session.post(url, json=payload, timeout=self.timeout)
            resp.raise_for_status()
        except Exception as exc:
            latency = time.time() - t0
            return GeminiChatResponse(
                text="", model=self.model,
                latency_sec=latency, error=str(exc),
            )

        data    = resp.json()
        latency = time.time() - t0

        text = ""
        try:
            text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
        except (KeyError, IndexError):
            pass

        usage   = data.get("usageMetadata", {})
        in_tok  = usage.get("promptTokenCount", 0)
        out_tok = usage.get("candidatesTokenCount", 0)
        tps     = out_tok / latency if latency > 0 and out_tok > 0 else 0.0
        cost    = (in_tok * self._pricing["input_per_1m"]
                   + out_tok * self._pricing["output_per_1m"]) / 1_000_000

        return GeminiChatResponse(
            text=text,
            model=self.model,
            input_tokens=in_tok,
            output_tokens=out_tok,
            latency_sec=round(latency, 3),
            tokens_per_sec=round(tps, 2),
            cost_usd=round(cost, 8),
            hw_cost_usd=0.0,
        )

    def health_check(self) -> Dict[str, Any]:
        """Verify API key is set and model is reachable."""
        if not self.api_key:
            return {"available": False, "error": "GEMINI_API_KEY not set"}
        try:
            r = self._session.get(
                f"{GEMINI_BASE_URL}/models/{self.model}?key={self.api_key}",
                timeout=10,
            )
            if r.status_code == 200:
                return {"available": True, "model": self.model}
            return {"available": False, "error": f"HTTP {r.status_code}: {r.text[:200]}"}
        except Exception as exc:
            return {"available": False, "error": str(exc)}

    def speed_calibration(self, n: int = 3) -> Dict[str, float]:
        """Run n short prompts and report mean tok/s and latency."""
        prompt = "What is PCR? Answer in exactly one sentence."
        results = []
        for _ in range(n):
            r = self.ask(prompt)
            if not r.error:
                results.append({"tps": r.tokens_per_sec, "latency": r.latency_sec,
                                 "out_tokens": r.output_tokens})
        if not results:
            return {"mean_tps": 0.0, "mean_latency_sec": 0.0, "error": "all failed"}
        return {
            "model": self.model,
            "mean_tps":          round(sum(r["tps"]     for r in results) / len(results), 1),
            "mean_latency_sec":  round(sum(r["latency"] for r in results) / len(results), 1),
            "n": len(results),
        }
