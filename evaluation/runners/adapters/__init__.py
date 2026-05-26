"""Model adapters for the unified 5-model regulatory LLM eval.

All adapters implement the ModelAdapter Protocol in `_base.py`. See
`docs/20260521_UNIFIED_5MODEL_EVAL_PLAN.md` for the full plan.
"""
from ._base import ModelAdapter, AdapterError
from .local_qwen import LocalQwenAdapter
from .anthropic_adapter import AnthropicAdapter
from .openai_adapter import OpenAIAdapter
from .gemini_adapter import GeminiAdapter

__all__ = [
    "ModelAdapter", "AdapterError",
    "LocalQwenAdapter", "AnthropicAdapter", "OpenAIAdapter", "GeminiAdapter",
]
