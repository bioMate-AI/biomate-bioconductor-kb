"""Uniform interface for the unified 5-model regulatory LLM eval.

Every adapter loads its model lazily and is closed explicitly so GPU-memory
swap (between LoRA-equipped Qwen and base Qwen) actually frees VRAM.
"""
from __future__ import annotations

from typing import Protocol, Optional


class AdapterError(RuntimeError):
    pass


class ModelAdapter(Protocol):
    """Uniform generate-and-close contract.

    Implementations:
      - LocalQwenAdapter   (Qwen3-8B + optional LoRA on local GPU)
      - AnthropicAdapter   (Sonnet 4.6, Opus 4.7 via Anthropic API)
      - OpenAIAdapter      (GPT-4o, o3-mini via OpenAI API)
      - GeminiAdapter      (Gemini 3 Flash Preview, 2.5 Pro via Google API)
    """
    name: str
    style: str   # "sft_style" (Qwen) or "instruction_style" (API)

    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        max_new_tokens: int = 400,
    ) -> str:
        """Return generated text. Strip any `<think>…</think>` defensively."""
        ...

    def close(self) -> None:
        """Free model resources (GPU memory, HTTP sessions)."""
        ...


def strip_thinking(text: str) -> str:
    """Defense against `<think>…</think>` leaking into output across providers.

    Some Qwen3 variants emit the tag even with `enable_thinking=False`, and
    occasionally frontier models leak chain-of-thought tokens too.
    """
    import re
    return re.sub(r"<think>.*?</think>\s*", "", text, flags=re.DOTALL).strip()


def assert_env(var: str) -> str:
    import os
    val = os.environ.get(var, "").strip()
    if not val:
        raise AdapterError(f"Missing env var: {var}")
    return val
