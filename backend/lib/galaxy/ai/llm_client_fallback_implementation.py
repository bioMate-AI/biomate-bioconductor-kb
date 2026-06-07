"""
LLM Client with Multi-Provider Cascading Fallback

This module implements the cascading fallback logic based on the priority
order defined in backend/config/llm_providers.yml

Priority Order:
1. Gemini 3.1 Pro Preview (primary)
2. Gemini 3.0 Flash Preview (fallback 1)
3. Claude Sonnet 4.5 (fallback 2)
4. OpenAI GPT-4o (fallback 3)
5. Local Ollama Qwen3 32B (fallback 4)

This replaces the broken fallback logic in llm_client.py lines 193-236.
"""

import logging
import asyncio
import time
from pathlib import Path
from typing import Optional, List, Tuple, Dict, Any
import os
import yaml

log = logging.getLogger(__name__)

_DEFAULT_LLM_CONFIG = (
    Path(__file__).resolve().parents[3] / "config" / "llm_providers.yml"
)


class LLMProviderConfig:
    """Configuration for a single LLM provider."""

    def __init__(self, config_dict: Dict[str, Any]):
        self.provider = config_dict['provider']
        self.model = config_dict['model']
        self.description = config_dict.get('description', '')
        self.api_key_env = config_dict.get('api_key_env')
        self.base_url = config_dict.get('base_url')
        self.max_tokens = config_dict.get('max_tokens', 4096)
        self.temperature = config_dict.get('temperature', 0.7)
        self.retry_attempts = config_dict.get('retry_attempts', 2)
        self.timeout_seconds = config_dict.get('timeout_seconds', 120)

    def is_available(self) -> bool:
        """Check if this provider is available (has required API key)."""
        if self.api_key_env is None:
            # Local provider, always available
            return True
        return bool(self.get_api_key())

    def get_api_key(self) -> Optional[str]:
        """Get API key from environment."""
        if not self.api_key_env:
            return None
        key = os.environ.get(self.api_key_env)
        if key:
            return key
        # BioMate start scripts export GEMINI_API_KEY; config references GOOGLE_API_KEY.
        if self.api_key_env == "GOOGLE_API_KEY":
            return os.environ.get("GEMINI_API_KEY")
        return None


class FallbackChainManager:
    """Manages the fallback chain for LLM requests."""

    def __init__(self, config_path: Optional[str] = None):
        """
        Initialize fallback chain from config file.

        Args:
            config_path: Path to llm_providers.yml
        """
        self.config_path = config_path or str(_DEFAULT_LLM_CONFIG)
        self.primary: Optional[LLMProviderConfig] = None
        self.fallbacks: List[LLMProviderConfig] = []
        self.retry_config = {}

        self._load_config()

    def _load_config(self):
        """Load configuration from YAML file."""
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            # Load primary provider
            if 'primary' in config:
                self.primary = LLMProviderConfig(config['primary'])

            # Load fallback chain
            if 'fallbacks' in config:
                self.fallbacks = [
                    LLMProviderConfig(fb)
                    for fb in config['fallbacks']
                ]

            # Load retry configuration
            self.retry_config = config.get('retry', {})

            log.info(f"Loaded LLM fallback config: primary={self.primary.model}, "
                     f"fallbacks=[{', '.join(fb.model for fb in self.fallbacks)}]")

        except Exception as e:
            log.error(f"Failed to load LLM config from {self.config_path}: {e}")
            # Fall back to hardcoded defaults
            self._load_defaults()

    def _load_defaults(self):
        """Load hardcoded defaults if config file fails."""
        log.warning("Using hardcoded LLM provider defaults")

        # Primary: Gemini 3.1 Pro
        self.primary = LLMProviderConfig({
            'provider': 'gemini',
            'model': 'gemini-3.1-pro-preview',
            'api_key_env': 'GOOGLE_API_KEY',
            'retry_attempts': 2,
            'timeout_seconds': 120
        })

        # Fallback chain
        self.fallbacks = [
            LLMProviderConfig({
                'provider': 'gemini',
                'model': 'gemini-3.5-flash-preview',
                'api_key_env': 'GOOGLE_API_KEY',
                'retry_attempts': 2,
                'timeout_seconds': 60
            }),
            LLMProviderConfig({
                'provider': 'anthropic',
                'model': 'claude-sonnet-4-5',
                'api_key_env': 'ANTHROPIC_API_KEY',
                'retry_attempts': 2,
                'timeout_seconds': 120
            }),
            LLMProviderConfig({
                'provider': 'openai',
                'model': 'gpt-4o',
                'api_key_env': 'OPENAI_API_KEY',
                'retry_attempts': 2,
                'timeout_seconds': 120
            }),
            LLMProviderConfig({
                'provider': 'ollama',
                'model': 'qwen3:32b',
                'api_key_env': None,
                'base_url': 'http://localhost:11434',
                'retry_attempts': 2,
                'timeout_seconds': 180
            })
        ]

    def get_provider_chain(self) -> List[LLMProviderConfig]:
        """
        Get the full provider chain: [primary, ...fallbacks].

        Only includes providers that are available (have API keys configured).

        Returns:
            List of LLMProviderConfig in priority order
        """
        chain = []

        # Add primary if available
        if self.primary and self.primary.is_available():
            chain.append(self.primary)
        else:
            if self.primary:
                log.warning(f"Primary provider {self.primary.model} not available "
                            f"(missing {self.primary.api_key_env})")

        # Add available fallbacks
        for fallback in self.fallbacks:
            if fallback.is_available():
                chain.append(fallback)
            else:
                log.debug(f"Fallback provider {fallback.model} not available "
                          f"(missing {fallback.api_key_env})")

        if not chain:
            log.error("No LLM providers available! Check API keys.")

        return chain


# Modified LLMClient.generate_async method
async def generate_with_fallback(
    llm_client,
    prompt: str,
    fallback_manager: Optional[FallbackChainManager] = None,
    **kwargs
) -> str:
    """
    Generate LLM response with automatic cascading fallback.

    This function should replace the current LLMClient.generate_async method
    in backend/lib/galaxy/ai/llm_client.py

    Args:
        llm_client: The LLMClient instance
        prompt: User prompt
        fallback_manager: FallbackChainManager (created once at app startup)
        **kwargs: Additional arguments (user_id, session_id, etc.)

    Returns:
        Generated text from the first successful provider

    Raises:
        Exception if all providers fail
    """
    if fallback_manager is None:
        fallback_manager = FallbackChainManager()

    # Inject billing context
    kwargs.setdefault("user_id", llm_client.user_id)
    kwargs.setdefault("session_id", llm_client.session_id)

    # Get provider chain
    provider_chain = fallback_manager.get_provider_chain()

    if not provider_chain:
        raise Exception("No LLM providers configured or available")

    errors = []
    total_attempts = 0

    # Try each provider in order
    for provider_config in provider_chain:
        provider_name = f"{provider_config.provider}:{provider_config.model}"

        try:
            log.info(f"Attempting LLM call with {provider_name} "
                     f"(attempt {total_attempts + 1}/{sum(p.retry_attempts for p in provider_chain)})")

            # Try this provider with retry
            result = await _try_provider_with_retry(
                llm_client=llm_client,
                provider_config=provider_config,
                prompt=prompt,
                **kwargs
            )

            # Success!
            if provider_config != provider_chain[0]:
                # This was a fallback
                log.warning(f"✅ Fallback to {provider_name} succeeded after primary failed")
            else:
                log.info(f"✅ Primary provider {provider_name} succeeded")

            return result

        except Exception as e:
            error_msg = f"{provider_name}: {str(e)[:100]}"
            log.error(f"❌ {error_msg}")
            errors.append(error_msg)
            total_attempts += provider_config.retry_attempts
            continue  # Try next provider

    # All providers failed
    error_summary = "; ".join(errors)
    raise Exception(
        f"All {len(provider_chain)} LLM providers failed after {total_attempts} total attempts. "
        f"Errors: {error_summary}"
    )


async def _try_provider_with_retry(
    llm_client,
    provider_config: LLMProviderConfig,
    prompt: str,
    **kwargs
) -> str:
    """
    Try a specific provider with exponential backoff retry.

    Args:
        llm_client: The LLMClient instance
        provider_config: Provider configuration
        prompt: User prompt
        **kwargs: Additional arguments

    Returns:
        Generated text

    Raises:
        Exception if all retry attempts fail
    """
    # Save original config
    orig_provider = llm_client.provider
    orig_model = llm_client.model
    orig_api_key = llm_client.api_key
    orig_api_base = llm_client.api_base
    orig_headers = llm_client.headers

    try:
        # Switch to this provider
        llm_client.provider = provider_config.provider
        llm_client.model = provider_config.model
        llm_client.api_key = provider_config.get_api_key()

        if provider_config.base_url:
            llm_client.api_base = provider_config.base_url

        llm_client._setup_provider()  # Re-setup with new config

        # Try with exponential backoff
        for attempt in range(provider_config.retry_attempts):
            try:
                # Route to correct provider method
                if provider_config.provider == 'gemini' or provider_config.provider == 'google':
                    result = await llm_client._generate_gemini(prompt, **kwargs)
                elif provider_config.provider == 'anthropic':
                    result = await llm_client._generate_anthropic(prompt, **kwargs)
                elif provider_config.provider == 'openai':
                    result = await llm_client._generate_openai(prompt, **kwargs)
                elif provider_config.provider == 'ollama':
                    result = await llm_client._generate_ollama(prompt, **kwargs)
                elif provider_config.provider == 'local':
                    result = await llm_client._generate_local(prompt, **kwargs)
                else:
                    raise ValueError(f"Unsupported provider: {provider_config.provider}")

                return result

            except Exception as e:
                if attempt < provider_config.retry_attempts - 1:
                    # Exponential backoff: 2s, 4s, 8s, ...
                    wait_time = min(2 ** (attempt + 1), 60)  # Cap at 60s
                    log.warning(
                        f"{provider_config.provider}:{provider_config.model} "
                        f"attempt {attempt + 1}/{provider_config.retry_attempts} failed, "
                        f"retrying in {wait_time}s: {str(e)[:100]}"
                    )
                    await asyncio.sleep(wait_time)
                else:
                    # Last attempt failed, raise
                    raise e

    finally:
        # Always restore original config
        llm_client.provider = orig_provider
        llm_client.model = orig_model
        llm_client.api_key = orig_api_key
        llm_client.api_base = orig_api_base
        llm_client.headers = orig_headers


# Integration example:
"""
To integrate this into the existing LLMClient:

1. In backend/lib/galaxy/ai/llm_client.py, add at top:
   from galaxy.ai.llm_client_fallback_implementation import (
       FallbackChainManager,
       generate_with_fallback
   )

2. In LLMClient.__init__, add:
   self.fallback_manager = FallbackChainManager()

3. Replace the current generate_async method with:
   async def generate_async(self, prompt: str, **kwargs) -> str:
       return await generate_with_fallback(
           llm_client=self,
           prompt=prompt,
           fallback_manager=self.fallback_manager,
           **kwargs
       )

That's it! The new cascading fallback is now active.
"""
