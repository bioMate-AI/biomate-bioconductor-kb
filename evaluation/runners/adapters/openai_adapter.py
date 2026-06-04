"""OpenAI (GPT-4o / o3-mini) adapter."""
from __future__ import annotations

from ._base import AdapterError, assert_env, strip_thinking


class OpenAIAdapter:
    style = "instruction_style"

    def __init__(self, model: str = "gpt-4o", name: str | None = None):
        self.model = model
        self.name = name or model.replace("-", "_").replace(".", "_")
        self._client = None

    def _ensure_client(self) -> None:
        if self._client is not None:
            return
        try:
            from openai import OpenAI
        except ImportError as e:
            raise AdapterError(f"openai SDK not installed: {e}") from e
        api_key = assert_env("OPENAI_API_KEY")
        self._client = OpenAI(api_key=api_key)

    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        max_new_tokens: int = 400,
    ) -> str:
        self._ensure_client()
        kwargs = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }
        # o-series and gpt-5 family use max_completion_tokens (not max_tokens);
        # both reject temperature. Reasoning tokens eat the budget before any
        # visible output. Setting reasoning_effort="minimal" prevents the
        # empty-output trap we hit on the v6 eval (90/100 outputs were blank
        # at max_completion_tokens=2400 because the model spent the whole
        # budget on reasoning). "minimal" gives short reasoning + actual prose.
        if self.model.startswith("o") or self.model.startswith("gpt-5"):
            kwargs["max_completion_tokens"] = max(max_new_tokens * 6, 2400)
            kwargs["reasoning_effort"] = "minimal"
        else:
            kwargs["max_tokens"] = max_new_tokens
            kwargs["temperature"] = 0.3
        resp = self._client.chat.completions.create(**kwargs)
        text = resp.choices[0].message.content or ""
        return strip_thinking(text.strip())

    def close(self) -> None:
        self._client = None
