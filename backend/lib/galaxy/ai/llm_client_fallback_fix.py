"""
Proper Multi-Provider Fallback for LLM Client

Current problem: If Claude (primary) fails → no backup at all!
This is a CRITICAL reliability issue.

Solution: Implement cascading fallback chain with retry at each level.

Fallback priority order:
1. Primary provider (configured in AIConfig)
2. Gemini Flash (fast, reliable, good fallback)
3. OpenAI GPT-4 (widely available)
4. Local Ollama (always works if installed)

Each provider gets 2 retry attempts before moving to next provider.
"""

import logging
from typing import Optional, List, Dict, Any
import os

log = logging.getLogger(__name__)


class FallbackChain:
    """Manages cascading fallback across multiple LLM providers."""

    # Fallback order (after primary fails)
    FALLBACK_ORDER = [
        ('gemini', 'gemini-2.0-flash-exp'),  # Fast, reliable
        ('openai', 'gpt-4o'),                # Widely available
        ('ollama', 'gemma4:31b'),            # Local fallback
    ]

    def __init__(self, primary_provider: str, primary_model: str):
        self.primary_provider = primary_provider
        self.primary_model = primary_model

    def get_fallback_providers(self) -> List[tuple]:
        """
        Get list of fallback providers to try (excluding primary).

        Returns list of (provider, model) tuples in priority order.
        """
        fallbacks = []

        # Don't include primary in fallback chain
        for provider, model in self.FALLBACK_ORDER:
            if provider != self.primary_provider:
                # Check if this provider is configured
                if self._is_provider_available(provider):
                    fallbacks.append((provider, model))

        return fallbacks

    def _is_provider_available(self, provider: str) -> bool:
        """Check if a provider has required credentials configured."""
        if provider == 'anthropic':
            return bool(os.environ.get('ANTHROPIC_API_KEY'))
        elif provider == 'gemini' or provider == 'google':
            return bool(os.environ.get('GEMINI_API_KEY'))
        elif provider == 'openai':
            return bool(os.environ.get('OPENAI_API_KEY'))
        elif provider == 'ollama' or provider == 'local':
            # Local providers always available if running
            return True
        else:
            return False


# Modified LLMClient.generate_async method
async def generate_async_with_fallback(self, prompt: str, **kwargs) -> str:
    """
    Generate response with automatic cascading fallback.

    Tries primary provider with 2 retries, then falls back to other
    providers in priority order.
    """
    kwargs.setdefault("user_id", self.user_id)
    kwargs.setdefault("session_id", self.session_id)

    # Build provider chain: primary + fallbacks
    fallback_chain = FallbackChain(self.provider, self.model)
    providers_to_try = [
        (self.provider, self.model)  # Primary first
    ] + fallback_chain.get_fallback_providers()

    errors = []

    for provider, model in providers_to_try:
        try:
            log.info(f"Attempting LLM call with provider={provider}, model={model}")

            # Try this provider with retry
            result = await self._generate_with_retry(
                provider=provider,
                model=model,
                prompt=prompt,
                max_attempts=2,  # 2 retries per provider
                **kwargs
            )

            if provider != self.provider:
                log.warning(f"✅ Fallback to {provider} succeeded after primary ({self.provider}) failed")

            return result

        except Exception as e:
            error_msg = f"{provider} failed: {str(e)[:100]}"
            log.error(error_msg)
            errors.append(error_msg)
            continue  # Try next provider

    # All providers failed
    error_summary = "; ".join(errors)
    raise Exception(f"All LLM providers failed. Tried {len(providers_to_try)} providers: {error_summary}")


async def _generate_with_retry(
    self,
    provider: str,
    model: str,
    prompt: str,
    max_attempts: int,
    **kwargs
) -> str:
    """
    Try to generate with a specific provider, with retry.

    Args:
        provider: Provider name ('anthropic', 'gemini', 'openai', 'ollama')
        model: Model name
        prompt: User prompt
        max_attempts: Number of retry attempts
        **kwargs: Additional arguments

    Returns:
        Generated text

    Raises:
        Exception if all attempts fail
    """
    import asyncio

    # Temporarily switch to this provider
    original_provider = self.provider
    original_model = self.model
    original_api_key = self.api_key
    original_api_base = self.api_base
    original_headers = self.headers

    try:
        self.provider = provider
        self.model = model

        # Get API key for this provider
        if provider == 'anthropic':
            self.api_key = os.environ.get('ANTHROPIC_API_KEY')
        elif provider in ['gemini', 'google']:
            self.api_key = os.environ.get('GEMINI_API_KEY')
        elif provider == 'openai':
            self.api_key = os.environ.get('OPENAI_API_KEY')
        elif provider == 'ollama':
            self.api_key = None  # Local doesn't need key

        if not self.api_key and provider not in ['ollama', 'local']:
            raise Exception(f"API key not configured for {provider}")

        self._setup_provider()  # Re-setup with new provider config

        # Try with exponential backoff
        for attempt in range(max_attempts):
            try:
                if provider == 'anthropic':
                    return await self._generate_anthropic(prompt, **kwargs)
                elif provider in ['gemini', 'google']:
                    return await self._generate_gemini(prompt, **kwargs)
                elif provider == 'openai':
                    return await self._generate_openai(prompt, **kwargs)
                elif provider == 'ollama':
                    return await self._generate_ollama(prompt, **kwargs)
                elif provider == 'local':
                    return await self._generate_local(prompt, **kwargs)
                else:
                    raise ValueError(f"Unsupported provider: {provider}")

            except Exception as e:
                if attempt < max_attempts - 1:
                    # Exponential backoff: 2s, 8s
                    wait_time = 2 ** (attempt + 1)
                    log.warning(f"{provider} attempt {attempt + 1} failed, retrying in {wait_time}s: {e}")
                    await asyncio.sleep(wait_time)
                else:
                    # Last attempt failed
                    raise e

    finally:
        # Always restore original config
        self.provider = original_provider
        self.model = original_model
        self.api_key = original_api_key
        self.api_base = original_api_base
        self.headers = original_headers


# Example usage and expected behavior:
"""
Scenario 1: Claude is primary, Gemini and OpenAI configured as backups

Request 1:
  Claude (attempt 1) → 429 rate limit
  Claude (attempt 2) → 429 rate limit
  Gemini (attempt 1) → Success ✅
  Total time: ~6 seconds

Request 2:
  Claude (attempt 1) → 500 server error
  Claude (attempt 2) → 500 server error
  Gemini (attempt 1) → timeout
  Gemini (attempt 2) → timeout
  OpenAI (attempt 1) → Success ✅
  Total time: ~30 seconds (but succeeded!)

Request 3 (all APIs down):
  Claude (2 attempts) → fail
  Gemini (2 attempts) → fail
  OpenAI (2 attempts) → fail
  Ollama (2 attempts) → fail
  Final error: "All LLM providers failed. Tried 4 providers: ..."
"""
