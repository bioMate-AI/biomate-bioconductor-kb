"""Google Gemini (3 Flash Preview / 2.5 Pro) adapter."""
from __future__ import annotations

from ._base import AdapterError, assert_env, strip_thinking


class GeminiAdapter:
    style = "instruction_style"

    def __init__(self, model: str = "gemini-3.5-flash", name: str | None = None):
        self.model = model
        self.name = name or model.replace("-", "_").replace(".", "_")
        self._client = None

    def _ensure_client(self) -> None:
        if self._client is not None:
            return
        try:
            import google.generativeai as genai
        except ImportError as e:
            raise AdapterError(f"google-generativeai SDK not installed: {e}") from e
        api_key = assert_env("GEMINI_API_KEY")
        genai.configure(api_key=api_key)
        self._client = genai.GenerativeModel(self.model)

    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        max_new_tokens: int = 400,
    ) -> str:
        self._ensure_client()
        # Gemini API: system instruction can be set per-call via the prompt prefix
        # or via system_instruction. We use the latter via re-create when needed,
        # but the simpler portable path is to inline as a prefix.
        full_prompt = f"{system_prompt}\n\n{user_prompt}"
        resp = self._client.generate_content(
            full_prompt,
            generation_config={
                "max_output_tokens": max_new_tokens,
                "temperature": 0.3,
                "top_p": 0.9,
            },
        )
        text = ""
        try:
            text = resp.text or ""
        except Exception:
            # Some safety-blocked responses don't have .text — fall through
            cands = getattr(resp, "candidates", None) or []
            if cands and getattr(cands[0], "content", None):
                parts = getattr(cands[0].content, "parts", [])
                text = "".join(getattr(p, "text", "") for p in parts)
        return strip_thinking(text.strip())

    def close(self) -> None:
        self._client = None
