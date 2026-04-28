"""
ollama_eval_client.py
---------------------
Direct Ollama client for benchmark evaluation.

Calls http://localhost:11434/v1/chat/completions directly — bypasses BioMate's
full pipeline (intent classifier, tool use, workflow routing) so we measure raw
LLM capability, comparable to published baselines that also test bare models.

Usage:
    client = OllamaEvalClient(model="qwen3:32b")
    resp = client.ask("What is the function of BRCA1?")
    print(resp.text, resp.tokens_per_sec, resp.cost_usd)
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

import requests

# ---------------------------------------------------------------------------
# Pricing: local Ollama = $0 financial cost.
# Hardware amortized cost uses machine cost / (lifetime × utilization).
# Default: $4,000 machine, 3yr, 50% utilization → $0.305/hr → $0.0000847/sec
# ---------------------------------------------------------------------------
_HW_COST_PER_SEC = float(os.environ.get(
    "OLLAMA_HW_COST_PER_SEC",
    str(4000 / (3 * 365 * 24 * 0.5) / 3600)   # ≈ $0.0000847/sec
))

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")

# Bio-reasoning system prompt (same style as BioMate uses)
_SYSTEM_PROMPT = (
    "You are an expert bioinformatics and molecular biology assistant. "
    "Answer questions accurately and concisely. "
    "For multiple-choice questions, state your answer as a single letter (A, B, C, or D) "
    "on the first line, then explain briefly."
)


@dataclass
class OllamaChatResponse:
    text: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_sec: float = 0.0
    tokens_per_sec: float = 0.0
    # Financial cost = $0 for local; hardware amortized cost based on latency
    cost_usd: float = 0.0          # always 0.0 — no API fee
    hw_cost_usd: float = 0.0       # amortized hardware cost
    error: Optional[str] = None


class OllamaEvalClient:
    """
    Thin eval wrapper around Ollama's OpenAI-compatible API.
    Implements the same .ask() interface shape as BioMateEvalClient
    so it can be dropped into existing adapter run() methods.
    """

    def __init__(
        self,
        model: str = "qwen3:32b",
        base_url: str = OLLAMA_BASE_URL,
        timeout: float = 300.0,
        max_tokens: int = 1024,
        temperature: float = 0.0,
        system_prompt: str = _SYSTEM_PROMPT,
    ):
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.system_prompt = system_prompt
        self._session = requests.Session()
        self._session.headers.update({"Content-Type": "application/json"})

    # ------------------------------------------------------------------
    # Public API (mirrors BioMateEvalClient shape)
    # ------------------------------------------------------------------

    def ask(self, question: str, **kwargs) -> OllamaChatResponse:
        """Send a single-turn question and return a structured response."""
        t0 = time.time()
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user",   "content": question},
            ],
            "stream": False,
            "options": {
                "num_predict": kwargs.get("max_tokens", self.max_tokens),
                "temperature": kwargs.get("temperature", self.temperature),
                "num_ctx": 32768,   # 32K context window
            },
        }

        try:
            resp = self._session.post(
                f"{self.base_url}/v1/chat/completions",
                json=payload,
                timeout=self.timeout,
            )
            resp.raise_for_status()
        except Exception as exc:
            latency = time.time() - t0
            return OllamaChatResponse(
                text="", model=self.model,
                latency_sec=latency,
                hw_cost_usd=latency * _HW_COST_PER_SEC,
                error=str(exc),
            )

        data = resp.json()
        latency = time.time() - t0

        text = ""
        choices = data.get("choices", [])
        if choices:
            text = choices[0].get("message", {}).get("content", "") or ""

        usage = data.get("usage", {})
        in_tok  = usage.get("prompt_tokens", 0)
        out_tok = usage.get("completion_tokens", 0)
        tps     = out_tok / latency if latency > 0 else 0.0

        return OllamaChatResponse(
            text=text.strip(),
            model=self.model,
            input_tokens=in_tok,
            output_tokens=out_tok,
            latency_sec=latency,
            tokens_per_sec=round(tps, 2),
            cost_usd=0.0,
            hw_cost_usd=round(latency * _HW_COST_PER_SEC, 6),
        )

    def health_check(self) -> Dict[str, Any]:
        """Verify Ollama is running and the model is available."""
        try:
            r = self._session.get(f"{self.base_url}/api/tags", timeout=5)
            r.raise_for_status()
            models = [m["name"] for m in r.json().get("models", [])]
            available = any(self.model.split(":")[0] in m for m in models)
            return {
                "ollama_running": True,
                "model_available": available,
                "installed_models": models,
                "model": self.model,
            }
        except Exception as exc:
            return {"ollama_running": False, "error": str(exc)}

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
        mean_tps     = sum(r["tps"]     for r in results) / len(results)
        mean_latency = sum(r["latency"] for r in results) / len(results)
        return {
            "model": self.model,
            "mean_tps": round(mean_tps, 1),
            "mean_latency_sec": round(mean_latency, 1),
            "n": len(results),
        }

    def clone(self) -> "OllamaEvalClient":
        return OllamaEvalClient(
            model=self.model,
            base_url=self.base_url,
            timeout=self.timeout,
            max_tokens=self.max_tokens,
            temperature=self.temperature,
            system_prompt=self.system_prompt,
        )
