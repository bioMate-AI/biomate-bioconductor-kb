"""
LLM Client for Galaxy AI Assistant

Supports multiple LLM providers: OpenAI, Anthropic Claude, Gemini, and local models.
With automatic cascading fallback for reliability.
"""

import json
import logging
import time
import uuid
import httpx
from typing import Dict, Any, List, Optional
from .config import AIConfig
from .llm_client_fallback_implementation import (
    FallbackChainManager,
    generate_with_fallback
)

log = logging.getLogger(__name__)


def _extract_anthropic_text(result: Dict[str, Any]) -> str:
    """Extract assistant text from Anthropic Messages API payload."""
    for block in result.get("content") or []:
        if isinstance(block, dict) and block.get("type") == "text":
            text = block.get("text")
            if text:
                return str(text).strip()
    raise Exception(
        f"Anthropic response had no text block (stop_reason={result.get('stop_reason')!r})"
    )


def _emit_llm_billing(
    user_id: str,
    session_id: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
    duration_ms: float,
) -> None:
    """Fire-and-forget billing emit after every successful Anthropic/OpenAI call."""
    # Always write to the durable file-based cost log first (no external deps).
    try:
        from galaxy.ai import cost_log
        cost_log.record(
            user_id=user_id or "anonymous",
            session_id=session_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            duration_ms=duration_ms,
        )
    except Exception as exc:
        log.warning("[CostLog] emit failed: %s", exc)

    if not user_id or user_id in ("", "unknown"):
        return
    try:
        from galaxy.ai.analytics.tracking_decorator import manual_track_call
        manual_track_call(
            session_id=session_id,
            step_name="llm_generate",
            scenario_name="ai_assistant",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            duration_ms=duration_ms,
            model_name=model,
            success=True,
        )
    except Exception as exc:
        log.debug("analytics track skipped: %s", exc)
    try:
        from galaxy.ai.billing.core.realtime_cost_service import get_cost_service
        from galaxy.ai.billing.core.cost_calculator import CostCalculator
        calc = CostCalculator()
        cost = calc.llm_call_cost(
            user_id=user_id,
            session_id=session_id,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )
        get_cost_service().record_llm_cost(
            user_id=user_id,
            input_usd=cost.input_cost,
            output_usd=cost.output_cost,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )
    except Exception as exc:
        log.debug("billing Redis emit skipped: %s", exc)
    try:
        from galaxy.ai.billing.core.lago_client import get_lago_client
        get_lago_client().emit_llm(
            user_id=user_id,
            session_id=session_id,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            model=model,
        )
    except Exception as exc:
        log.debug("billing Lago emit skipped: %s", exc)


class LLMClient:
    """Universal LLM client supporting multiple providers."""

    def __init__(self, config: AIConfig):
        self.config = config
        self.provider = config.llm_provider.lower()
        self.model = config.llm_model
        self.api_key = config.llm_api_key
        self.base_url = config.llm_base_url

        # Billing context — set by callers that have a user in scope.
        # All generate() calls will forward these to _emit_llm_billing automatically.
        self.user_id: str = ""
        self.session_id: str = str(uuid.uuid4())

        # Initialize cascading fallback manager
        self.fallback_manager = FallbackChainManager()

        # Initialize provider-specific settings
        self._setup_provider()
        
    def _setup_provider(self):
        """Setup provider-specific configurations."""
        if self.provider == 'openai':
            self.api_base = self.base_url or "https://api.openai.com/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

        elif self.provider == 'anthropic':
            self.api_base = self.base_url or "https://api.anthropic.com"
            self.headers = {
                "x-api-key": self.api_key,
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01"
            }

        elif self.provider in ['gemini', 'google']:
            # Gemini uses API key in URL, not headers
            self.api_base = "https://generativelanguage.googleapis.com/v1beta"
            self.headers = {
                "Content-Type": "application/json"
            }

        elif self.provider == 'deepseek':
            self.api_base = self.base_url or "https://api.deepseek.com/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

        elif self.provider == 'ollama':
            # Ollama local models (qwen3, llama3, mistral, etc.)
            self.api_base = self.base_url or "http://localhost:11434/v1"
            self.headers = {
                "Content-Type": "application/json"
            }

        elif self.provider == 'zhipu':
            # Zhipu AI GLM models (GLM-4.7, GLM-4.6V-Flash, etc.)
            self.api_base = self.base_url or "https://open.bigmodel.cn/api/paas/v4"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

        elif self.provider == 'local':
            # For local models (e.g., LM Studio, vLLM)
            self.api_base = self.base_url or "http://localhost:1234/v1"
            self.headers = {
                "Content-Type": "application/json"
            }
            if self.api_key:
                self.headers["Authorization"] = f"Bearer {self.api_key}"

        else:
            raise ValueError(f"Unsupported LLM provider: {self.provider}")
    
    async def generate_async(self, prompt: str, **kwargs) -> str:
        """
        Generate response asynchronously with automatic cascading fallback.

        Priority order: Gemini 3.1 Pro → Gemini Flash → Claude → OpenAI → Local Qwen3
        Each provider gets 2 retry attempts before moving to next.
        """
        return await generate_with_fallback(
            llm_client=self,
            prompt=prompt,
            fallback_manager=self.fallback_manager,
            **kwargs
        )
    
    def call(self, *args, **kwargs) -> str:
        """Compatibility shim for the AutoFix3 stack.

        Twelve callers across the autofix package use `llm_client.call(...)`
        but LLMClient only ever defined `generate(prompt, **kwargs)`. Result:
        autofix3 was importable + status endpoint reported "operational" but
        DeepAnalysisAgent crashed at attempt 1 with AttributeError on the
        very first LLM call. Caught 2026-06-07 by end-to-end validation.

        Two prompt shapes are in active use:
          - `call(prompt_string, max_tokens=...)`
          - `call(messages=[{role, content}, ...], provider=..., temperature=..., max_tokens=...)`

        Both normalize to `generate(prompt_string, **filtered_kwargs)`:
          - messages joined with role separators
          - `provider` kwarg dropped (LLMClient already selects per AIConfig)
          - other kwargs (temperature, max_tokens, ...) forwarded as-is
        """
        prompt: Optional[str] = None
        if args:
            if isinstance(args[0], str):
                prompt = args[0]
            elif isinstance(args[0], list):
                prompt = self._messages_to_prompt(args[0])
        if prompt is None:
            messages = kwargs.pop("messages", None)
            if messages is not None:
                prompt = self._messages_to_prompt(messages)
            else:
                prompt = kwargs.pop("prompt", "")
        kwargs.pop("provider", None)
        return self.generate(prompt, **kwargs)

    @staticmethod
    def _messages_to_prompt(messages: List[Dict[str, str]]) -> str:
        """Flatten a chat-messages list into a single prompt string."""
        parts: List[str] = []
        for m in messages or []:
            role = (m.get("role") or "user").strip()
            content = m.get("content", "")
            if role == "user":
                parts.append(str(content))
            else:
                parts.append(f"[{role}] {content}")
        return "\n\n".join(parts)

    def generate(self, prompt: str, **kwargs) -> str:
        """Synchronous wrapper for generate_async.

        Properly handles event loop creation to avoid "Event loop is closed" errors.
        Works correctly in Python 3.10+ where get_event_loop() behavior changed.
        """
        import asyncio
        import concurrent.futures

        async_coro = self.generate_async(prompt, **kwargs)

        # Check if we're already inside an async context
        try:
            loop = asyncio.get_running_loop()
            # We're inside an async context - run in a separate thread
            def run_async():
                return asyncio.run(self.generate_async(prompt, **kwargs))

            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(run_async)
                return future.result(timeout=120)
        except RuntimeError:
            # No running event loop - safe to use asyncio.run()
            return asyncio.run(async_coro)
    
    async def _generate_openai(self, prompt: str, **kwargs) -> str:
        """Generate using OpenAI API."""
        # For newer models (gpt-5, gpt-4o-2024-08-06+), use max_completion_tokens
        # For older models, use max_tokens
        max_tokens_key = "max_completion_tokens" if "gpt-5" in self.model or "gpt-4o-2024" in self.model else "max_tokens"

        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant."},
                {"role": "user", "content": prompt}
            ],
            max_tokens_key: kwargs.get('max_tokens', 1000),
            # OpenAI supports a `seed` parameter for reproducible completions.
            # Anthropic and Gemini don't; for those, temperature=0 is the only
            # determinism lever. Set a fixed seed for OpenAI calls.
            "seed": int(kwargs.get('seed', 42)),
        }

        # GPT-5 only supports temperature=1 (default), older models support 0-2
        # For precise workflow generation, use temperature=0 (deterministic)
        if "gpt-5" not in self.model:
            data["temperature"] = kwargs.get('temperature', 0.0)

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=60.0  # Increased to 60s for slower models like gpt-5
            )
            
            if response.status_code == 200:
                result = response.json()
                usage = result.get("usage", {})
                _emit_llm_billing(
                    user_id=kwargs.get("user_id", self.user_id),
                    session_id=kwargs.get("session_id", ""),
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens", 0),
                    output_tokens=usage.get("completion_tokens", 0),
                    duration_ms=0.0,
                )
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"OpenAI API error: {response.status_code} {response.text}")
    
    async def _generate_anthropic(self, prompt: str, **kwargs) -> str:
        """Generate using Anthropic Claude API."""
        data = {
            "model": self.model,
            "max_tokens": kwargs.get('max_tokens', 1000),
            "messages": [
                {
                    "role": "user",
                    "content": f"You are a helpful bioinformatics assistant. {prompt}"
                }
            ]
        }

        # Add temperature if provided
        temperature = kwargs.get('temperature', 0.0)
        if temperature is not None:
            data["temperature"] = temperature

        t0 = time.monotonic()
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/v1/messages",
                headers=self.headers,
                json=data,
                timeout=120.0
            )

            if response.status_code == 200:
                result = response.json()
                # Emit billing for every successful call (fire-and-forget)
                usage = result.get("usage", {})
                _emit_llm_billing(
                    user_id=kwargs.get("user_id", ""),
                    session_id=kwargs.get("session_id", str(uuid.uuid4())),
                    model=self.model,
                    input_tokens=usage.get("input_tokens", 0),
                    output_tokens=usage.get("output_tokens", 0),
                    duration_ms=(time.monotonic() - t0) * 1000,
                )
                return _extract_anthropic_text(result)
            else:
                raise Exception(f"Anthropic API error: {response.status_code} {response.text}")

    async def _generate_gemini(self, prompt: str, **kwargs) -> str:
        """Generate using Google Gemini API."""
        # Gemini uses a different API format
        data = {
            "contents": [
                {
                    "parts": [
                        {"text": f"You are a helpful bioinformatics assistant. {prompt}"}
                    ]
                }
            ],
            "generationConfig": {
                "temperature": kwargs.get('temperature', 0.0),
                # Default bumped 1000 → 4096: leaves room for both thinking
                # tokens AND content output. Caller can still override.
                "maxOutputTokens": kwargs.get('max_tokens', 4096),
                # thinkingBudget=-1 = dynamic (model decides). Works on both
                # Flash and Pro:
                #   - Flash: budget=0 also works (saves latency) but -1 is uniform
                #   - Pro:   budget=0 returns HTTP 400 "model only works in
                #            thinking mode" — must be ≥1 or -1
                # Verified locally 2026-06-07: -1 → finishReason=STOP + real
                # text on both. Previously default-thinking-on with
                # maxOutputTokens=1000 ate the entire budget on thinking and
                # left empty content; parser raised "No content in Gemini
                # response" so the whole chain silently fell through to
                # Claude on every call. The "Gemini primary" policy was inert
                # for months because of this.
                "thinkingConfig": {
                    "thinkingBudget": kwargs.get('thinking_budget', -1),
                },
                # Honor json_mode=True from caller: forces Gemini to emit
                # valid JSON instead of markdown prose. Required for the
                # findings-analysis and prerequisites-validator paths that
                # post-parse with JSON.parse. Without this, Gemini Pro
                # returns markdown-formatted text + the downstream parser
                # falls back silently to degraded shape.
                **({"responseMimeType": "application/json"}
                   if kwargs.get('json_mode') else {}),
            }
        }

        async with httpx.AsyncClient() as client:
            # Gemini API endpoint format
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={self.api_key}"
            response = await client.post(
                url,
                json=data,
                timeout=120.0
            )

            if response.status_code == 200:
                result = response.json()
                # Extract text from Gemini response format
                candidates = result.get('candidates', [])
                if candidates:
                    content = candidates[0].get('content', {})
                    parts = content.get('parts', [])
                    if parts:
                        meta = result.get("usageMetadata", {})
                        _emit_llm_billing(
                            user_id=kwargs.get("user_id", self.user_id),
                            session_id=kwargs.get("session_id", ""),
                            model=self.model,
                            input_tokens=meta.get("promptTokenCount", 0),
                            output_tokens=meta.get("candidatesTokenCount", 0),
                            duration_ms=0.0,
                        )
                        return parts[0].get('text', '').strip()
                raise Exception("No content in Gemini response")
            else:
                raise Exception(f"Gemini API error: {response.status_code} {response.text}")

    async def _generate_openai_compatible(self, prompt: str, **kwargs) -> str:
        """Generate using OpenAI-compatible APIs (for Chinese models)."""
        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant. Please respond in Chinese when appropriate."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": kwargs.get('max_tokens', 1000),
            "temperature": kwargs.get('temperature', 0.0)
        }

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=120.0
            )

            if response.status_code == 200:
                result = response.json()
                usage = result.get("usage", {})
                _emit_llm_billing(
                    user_id=kwargs.get("user_id", self.user_id),
                    session_id=kwargs.get("session_id", ""),
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens", 0),
                    output_tokens=usage.get("completion_tokens", 0),
                    duration_ms=0.0,
                )
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"{self.provider.upper()} API error: {response.status_code} {response.text}")

    async def _generate_ollama(self, prompt: str, **kwargs) -> str:
        """Generate using Ollama local models (qwen3, llama3, mistral, etc.)."""
        # Check if we should use thinking mode for complex tasks
        use_thinking = kwargs.get('use_thinking', False)

        # Prepare the prompt - Qwen3 supports /think and /no_think toggles
        if use_thinking and 'qwen3' in self.model.lower():
            prompt = f"/think\n{prompt}"

        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant."},
                {"role": "user", "content": prompt}
            ],
            "options": {
                "num_predict": kwargs.get('max_tokens', 1000),
                "temperature": kwargs.get('temperature', 0.0)
            }
        }

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=300.0  # Longer timeout for local models
            )

            if response.status_code == 200:
                result = response.json()
                usage = result.get("usage", {})
                _emit_llm_billing(
                    user_id=kwargs.get("user_id", self.user_id),
                    session_id=kwargs.get("session_id", ""),
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens", 0),
                    output_tokens=usage.get("completion_tokens", 0),
                    duration_ms=0.0,
                )
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"Ollama API error: {response.status_code} {response.text}")

    async def _generate_zhipu(self, prompt: str, **kwargs) -> str:
        """Generate using Zhipu AI GLM models (GLM-4.7, GLM-4.6V-Flash, etc.)."""
        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": kwargs.get('max_tokens', 1000),
            "temperature": kwargs.get('temperature', 0.0)
        }

        # GLM-4.7 supports tool calling - add if provided
        if 'tools' in kwargs:
            data['tools'] = kwargs['tools']

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=120.0
            )

            if response.status_code == 200:
                result = response.json()
                usage = result.get("usage", {})
                _emit_llm_billing(
                    user_id=kwargs.get("user_id", self.user_id),
                    session_id=kwargs.get("session_id", ""),
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens", 0),
                    output_tokens=usage.get("completion_tokens", 0),
                    duration_ms=0.0,
                )
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"Zhipu API error: {response.status_code} {response.text}")

    async def _generate_local(self, prompt: str, **kwargs) -> str:
        """Generate using local model API (compatible with OpenAI format)."""
        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": kwargs.get('max_tokens', 1000),
            "temperature": kwargs.get('temperature', 0.0)
        }

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=120.0
            )

            if response.status_code == 200:
                result = response.json()
                usage = result.get("usage", {})
                _emit_llm_billing(
                    user_id=kwargs.get("user_id", self.user_id),
                    session_id=kwargs.get("session_id", ""),
                    model=self.model,
                    input_tokens=usage.get("prompt_tokens", 0),
                    output_tokens=usage.get("completion_tokens", 0),
                    duration_ms=0.0,
                )
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"Local model API error: {response.status_code} {response.text}")
    
    def test_connection(self) -> Dict[str, Any]:
        """Test connection to the LLM provider."""
        try:
            test_prompt = "Hello! Please respond with 'Connection successful' if you receive this message."
            response = self.generate(test_prompt)
            
            return {
                "success": True,
                "provider": self.provider,
                "model": self.model,
                "response": response[:100] + "..." if len(response) > 100 else response
            }
        except Exception as e:
            return {
                "success": False,
                "provider": self.provider,
                "model": self.model,
                "error": str(e)
            }


# Provider-specific model mappings

# Anthropic Claude models (Primary)
CLAUDE_MODELS = [
    "claude-sonnet-4-5",             # Claude 4.5 Sonnet - Best balance
    "claude-opus-4-5",               # Claude 4.5 Opus - Most capable
    "claude-haiku-4-5",              # Claude 4.5 Haiku - Fast & efficient
]

# Google Gemini models
GEMINI_MODELS = [
    "gemini-3-flash-preview",        # Gemini 3 Flash Preview - Primary cloud model (BioMate default)
    "gemini-2.0-flash-exp",          # Gemini 2.0 Flash - Latest experimental
    "gemini-1.5-pro",                # Gemini 1.5 Pro - Production ready
    "gemini-1.5-flash",              # Gemini 1.5 Flash - Fast responses
    "gemini-nano",                   # Gemini Nano - Edge/mobile
]

# OpenAI models
OPENAI_MODELS = [
    "gpt-4o",                        # GPT-4o - Multimodal
    "gpt-4-turbo",                   # GPT-4 Turbo
    "gpt-3.5-turbo",                 # GPT-3.5 - Economic
]

# DeepSeek models
DEEPSEEK_MODELS = [
    "deepseek-chat",                 # General chat
    "deepseek-coder",                # Code specialist
]

# Ollama local models
OLLAMA_MODELS = [
    "gemma4:31b",                    # Gemma 4 31B - Primary local model (BioMate default)
    "qwen3:32b",                     # Qwen3 32B - Strong reasoning, /think mode
    "qwen3:30b-a3b",                 # Qwen3 30B MoE - Fast (61 tok/s), good MCQ
    "qwen3:14b",                     # Qwen3 14B - Good balance
    "qwen3:8b",                      # Qwen3 8B - Fast
    "gemma3:27b",                    # Gemma 3 27B - Efficient
    "llama3.3:70b",                  # Llama 3.3 70B - Very capable
    "llama3.1:8b",                   # Llama 3.1 8B - Fast routing
    "mistral:7b",                    # Mistral 7B - Efficient
    "qwen3-coder:32b",               # Qwen3 Coder - Code specialist
]

# Zhipu GLM models
ZHIPU_MODELS = [
    "glm-4.7",                       # GLM-4.7 - Flagship, 400B MoE, best coding
    "glm-4.6v-flash",                # GLM-4.6V-Flash 9B - Fast vision+language
    "glm-4.6v",                      # GLM-4.6V 106B - Full vision model
    "glm-4-flash",                   # GLM-4 Flash - Economic
]


def get_recommended_model(provider: str) -> str:
    """Get recommended model for provider."""
    recommendations = {
        'anthropic': 'claude-sonnet-4-5',
        'gemini': 'gemini-3-flash-preview',
        'google': 'gemini-3-flash-preview',
        'openai': 'gpt-4o',
        'deepseek': 'deepseek-chat',
        'ollama': 'gemma4:31b',
        'zhipu': 'glm-4.7',
    }

    return recommendations.get(provider.lower(), 'claude-sonnet-4-5')


def get_provider_models(provider: str) -> list:
    """Get available models for a specific provider."""
    model_maps = {
        'anthropic': CLAUDE_MODELS,
        'gemini': GEMINI_MODELS,
        'google': GEMINI_MODELS,
        'openai': OPENAI_MODELS,
        'deepseek': DEEPSEEK_MODELS,
        'ollama': OLLAMA_MODELS,
        'zhipu': ZHIPU_MODELS,
    }

    return model_maps.get(provider.lower(), [])


def get_all_providers() -> Dict[str, Dict[str, Any]]:
    """Get information about all supported providers."""
    return {
        'anthropic': {
            'name': 'Anthropic Claude',
            'models': CLAUDE_MODELS,
            'recommended': 'claude-sonnet-4-5',
            'api_key_required': True,
            'local': False,
            'description': 'Safe, reliable AI assistant with strong reasoning'
        },
        'gemini': {
            'name': 'Google Gemini',
            'models': GEMINI_MODELS,
            'recommended': 'gemini-2.0-flash-exp',
            'api_key_required': True,
            'local': False,
            'description': 'Google multimodal AI with strong performance'
        },
        'openai': {
            'name': 'OpenAI',
            'models': OPENAI_MODELS,
            'recommended': 'gpt-4o',
            'api_key_required': True,
            'local': False,
            'description': 'Industry-leading AI models'
        },
        'deepseek': {
            'name': 'DeepSeek',
            'models': DEEPSEEK_MODELS,
            'recommended': 'deepseek-chat',
            'api_key_required': True,
            'local': False,
            'description': 'Strong reasoning and coding capabilities'
        },
        'ollama': {
            'name': 'Ollama (Local)',
            'models': OLLAMA_MODELS,
            'recommended': 'qwen3:32b',
            'api_key_required': False,
            'local': True,
            'description': 'Local models via Ollama - qwen3, llama3, mistral'
        },
        'zhipu': {
            'name': 'Zhipu AI (GLM)',
            'models': ZHIPU_MODELS,
            'recommended': 'glm-4.7',
            'api_key_required': True,
            'local': False,
            'description': 'Chinese AI leader - GLM-4.7 flagship, strong coding'
        },
    }