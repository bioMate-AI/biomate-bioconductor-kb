"""Local Qwen3-27B (Q4_K_M, llama.cpp) via OpenAI-compatible endpoint."""
from __future__ import annotations
import os
from ._base import strip_thinking


class Qwen27bLlamaCppAdapter:
    style = "instruction_style"

    def __init__(self, base_url: str | None = None,
                 model: str = "Qwen/Qwen3.8-27B", name: str = "qwen27b_local"):
        self.base_url = (base_url or os.environ.get("LOCAL_LLM_URL",
                         "http://127.0.0.1:8000/v1")).rstrip("/")
        self.model = model
        self.name = name
        self._session = None

    def _ensure(self) -> None:
        if self._session is None:
            import requests
            self._session = requests.Session()

    def generate(self, system_prompt: str, user_prompt: str,
                 max_new_tokens: int = 400) -> str:
        self._ensure()
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "max_tokens": max_new_tokens,
            "temperature": 0.3,
        }
        r = self._session.post(self.base_url + "/chat/completions",
                               json=payload, timeout=600)
        r.raise_for_status()
        d = r.json()
        text = d["choices"][0]["message"]["content"] or ""
        return strip_thinking(text.strip())

    def close(self) -> None:
        if self._session is not None:
            self._session.close()
            self._session = None
