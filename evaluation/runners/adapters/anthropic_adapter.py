"""Anthropic Claude (Sonnet 4.6 / Opus 4.7) adapter."""
from __future__ import annotations

from ._base import AdapterError, assert_env, strip_thinking


class AnthropicAdapter:
    style = "instruction_style"

    def __init__(self, model: str = "claude-sonnet-4-6", name: str | None = None):
        self.model = model
        self.name = name or model.replace("-", "_").replace(".", "_")
        self._client = None

    def _ensure_client(self) -> None:
        if self._client is not None:
            return
        try:
            from anthropic import Anthropic
        except ImportError as e:
            raise AdapterError(f"anthropic SDK not installed: {e}") from e
        api_key = assert_env("ANTHROPIC_API_KEY")
        self._client = Anthropic(api_key=api_key)

    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        max_new_tokens: int = 400,
    ) -> str:
        self._ensure_client()
        # tenacity retry handled in the orchestrator (so it's consistent
        # across providers); this method does one call.
        # claude-opus-4-8 (and successor reasoning models) deprecate temperature.
        kwargs = dict(
            model=self.model,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}],
            max_tokens=max_new_tokens,
        )
        if "opus-4-8" not in self.model:
            kwargs["temperature"] = 0.3
        resp = self._client.messages.create(**kwargs)
        text = "".join(
            block.text for block in resp.content if getattr(block, "type", "") == "text"
        )
        return strip_thinking(text.strip())

    def close(self) -> None:
        self._client = None
