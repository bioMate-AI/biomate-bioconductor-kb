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
    """Defense against chain-of-thought leakage across providers.

    Strips:
      - `<think>…</think>` tags (some Qwen3 variants)
      - Italic-wrapped author notes Gemini-3-series emits before the draft
        (`*Wait, let's refine…*`, `*Let me draft a paragraph that…*`)
      - "Sentence 1:", "Sentence 2:" enumeration that meta-commentary uses
      - Anything before the first `[BioMate-generated draft]` token if present
        (the system prompt mandates that as the prefix)
    """
    import re
    text = re.sub(r"<think>.*?</think>\s*", "", text, flags=re.DOTALL)

    # If the mandated prefix is present, anchor on it — drop anything before
    anchor = "[BioMate-generated draft]"
    idx = text.find(anchor)
    if idx > 0:
        text = text[idx:]

    # Strip italic-wrapped meta-commentary at the start
    text = re.sub(r"^\s*\*[^*]{5,200}\*\s*", "", text, flags=re.MULTILINE)

    # Strip "Sentence N:" enumeration
    text = re.sub(r"^\s*Sentence\s+\d+\s*:\s*", "", text, flags=re.MULTILINE | re.IGNORECASE)

    return text.strip()


def assert_env(var: str) -> str:
    import os
    val = os.environ.get(var, "").strip()
    if not val:
        raise AdapterError(f"Missing env var: {var}")
    return val
