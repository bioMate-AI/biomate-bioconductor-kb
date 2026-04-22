"""
Gemini 3 Flash — thin wrapper replacing Claude Haiku for lightweight inference tasks.

Usage:
    from galaxy.ai.gemini_flash import call_gemini_flash, call_gemini_flash_vision

    text = call_gemini_flash(
        messages=[{"role": "user", "content": "Classify this query..."}],
        system="You are a bioinformatics classifier.",
        max_tokens=256,
        json_mode=True,
    )
"""

import logging
import os
from typing import Optional

log = logging.getLogger(__name__)

GEMINI_FLASH_MODEL = "gemini-3-flash-preview"


def _get_client():
    """Return a configured GenerativeModel instance."""
    import google.generativeai as genai  # noqa: PLC0415

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise ValueError("GEMINI_API_KEY not set")
    genai.configure(api_key=api_key)
    return genai


def call_gemini_flash(
    messages: list[dict],
    system: str = "",
    max_tokens: int = 1024,
    temperature: float = 0.0,
    json_mode: bool = False,
) -> str:
    """
    Call Gemini 3 Flash with an Anthropic-style messages list.

    Args:
        messages: List of {"role": "user"|"assistant", "content": str}
        system:   System instruction (optional)
        max_tokens: Maximum output tokens
        temperature: Sampling temperature (0 = deterministic)
        json_mode: Request JSON response MIME type

    Returns:
        Response text string
    """
    genai = _get_client()

    gen_config_kwargs: dict = {
        "max_output_tokens": max_tokens,
        "temperature": temperature,
    }
    if json_mode:
        gen_config_kwargs["response_mime_type"] = "application/json"

    generation_config = genai.types.GenerationConfig(**gen_config_kwargs)

    model = genai.GenerativeModel(
        GEMINI_FLASH_MODEL,
        system_instruction=system or None,
        generation_config=generation_config,
    )

    # Convert messages to Gemini content format
    # Gemini uses "user" / "model" roles
    gemini_history = []
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        content = msg.get("content", "")
        if not isinstance(content, str):
            content = str(content)
        gemini_history.append({"role": role, "parts": [content]})

    if not gemini_history:
        return ""

    if len(gemini_history) == 1:
        response = model.generate_content(gemini_history[0]["parts"][0])
    else:
        chat = model.start_chat(history=gemini_history[:-1])
        response = chat.send_message(gemini_history[-1]["parts"][0])

    return response.text


def call_gemini_flash_vision(
    image_b64: str,
    prompt: str,
    max_tokens: int = 512,
    mime_type: str = "image/png",
) -> str:
    """
    Call Gemini 3 Flash with a base64-encoded image.

    Args:
        image_b64: Base64-encoded image data (no data-URI prefix)
        prompt:    Text instruction
        max_tokens: Maximum output tokens
        mime_type: Image MIME type (default: image/png)

    Returns:
        Response text string
    """
    genai = _get_client()

    model = genai.GenerativeModel(
        GEMINI_FLASH_MODEL,
        generation_config=genai.types.GenerationConfig(max_output_tokens=max_tokens),
    )

    import base64  # noqa: PLC0415

    image_bytes = base64.b64decode(image_b64)
    response = model.generate_content([
        {"mime_type": mime_type, "data": image_bytes},
        prompt,
    ])
    return response.text
