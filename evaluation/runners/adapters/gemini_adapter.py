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
        # We re-create the client per generate() so system_instruction can vary
        # by example. Configuration of the API key happens once.
        if getattr(self, "_configured", False):
            return
        try:
            import google.generativeai as genai
        except ImportError as e:
            raise AdapterError(f"google-generativeai SDK not installed: {e}") from e
        import os
        api_key = (os.environ.get("GEMINI_API_KEY")
                   or os.environ.get("GOOGLE_API_KEY") or "").strip()
        if not api_key:
            raise AdapterError("Missing env var: GEMINI_API_KEY (or GOOGLE_API_KEY)")
        genai.configure(api_key=api_key)
        self._genai = genai
        self._configured = True

    def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        max_new_tokens: int = 400,
    ) -> str:
        self._ensure_client()
        # Per-call client with system_instruction — the supported way to give
        # Gemini a system role. Concatenating into the user prompt makes the
        # model echo the rules instead of following them.
        gm = self._genai.GenerativeModel(
            self.model, system_instruction=system_prompt,
        )
        # Gemini Flash burns tokens on internal reasoning before any output
        # appears, so a 400-token budget yields ~60 chars of prose. Per memory
        # `feedback_gemini_model_selection` we floor at 1024; empirically for
        # IND prose we need 2048 to fit a 300-500 word paragraph.
        effective_max = max(max_new_tokens * 5, 2048)
        resp = gm.generate_content(
            user_prompt,
            generation_config={
                "max_output_tokens": effective_max,
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
        self._configured = False
        self._genai = None
