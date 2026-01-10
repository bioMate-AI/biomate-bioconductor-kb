"""
AI Assistant Configuration

Configuration settings for the Galaxy AI Assistant module.

Environment Variables:
    ANTHROPIC_API_KEY: API key for Claude models
    GOOGLE_API_KEY: API key for Gemini models
    OPENAI_API_KEY: API key for OpenAI models
    ZHIPU_API_KEY: API key for Zhipu GLM models
    DEEPSEEK_API_KEY: API key for DeepSeek models

Ollama (local models) does not require an API key.
"""

from typing import Dict, Any, Optional, List
import os


class AIConfig:
    """Configuration for AI Assistant components."""

    def __init__(self, config_dict: Optional[Dict[str, Any]] = None):
        self.config = config_dict or {}

        # Primary LLM Configuration
        self.llm_provider = self.config.get('llm_provider', 'anthropic')
        self.llm_model = self.config.get('llm_model', 'claude-sonnet-4-5')
        self.llm_api_key = self._resolve_api_key()
        self.llm_base_url = self.config.get('llm_base_url', None)

        # Hybrid Routing Configuration
        self.enable_hybrid_routing = self.config.get('enable_hybrid_routing', False)
        self.prefer_local_models = self.config.get('prefer_local_models', True)
        self.cost_sensitive_routing = self.config.get('cost_sensitive_routing', True)

        # Ollama Configuration (for local models on ARM supercomputer)
        self.ollama_base_url = self.config.get('ollama_base_url', 'http://localhost:11434')
        self.ollama_default_model = self.config.get('ollama_default_model', 'qwen3:32b')
        self.ollama_use_fp16 = self.config.get('ollama_use_fp16', True)  # Use FP16 with 128GB memory

        # Zhipu Configuration
        self.zhipu_api_key = self.config.get('zhipu_api_key') or os.getenv('ZHIPU_API_KEY')
        self.zhipu_default_model = self.config.get('zhipu_default_model', 'glm-4.7')

        # Initialize remaining config
        self._init_remaining_config()

    def _resolve_api_key(self) -> Optional[str]:
        """Resolve API key from config or environment based on provider."""
        # Explicit config takes precedence
        if self.config.get('llm_api_key'):
            return self.config['llm_api_key']

        # Provider-specific environment variables
        provider = self.config.get('llm_provider', 'anthropic').lower()
        env_map = {
            'anthropic': 'ANTHROPIC_API_KEY',
            'gemini': 'GOOGLE_API_KEY',
            'google': 'GOOGLE_API_KEY',
            'openai': 'OPENAI_API_KEY',
            'deepseek': 'DEEPSEEK_API_KEY',
            'zhipu': 'ZHIPU_API_KEY',
            'ollama': None,  # No API key needed
            'local': None,
        }

        env_var = env_map.get(provider)
        if env_var:
            key = os.getenv(env_var)
            if key:
                return key

        # Fallback to generic keys
        return os.getenv('ANTHROPIC_API_KEY') or os.getenv('GALAXY_AI_API_KEY')

    def _init_remaining_config(self):
        """Initialize remaining configuration (called from __init__)."""
        # Tool Discovery Configuration
        self.max_tools_per_task = self.config.get('max_tools_per_task', 5)
        self.similarity_threshold = self.config.get('similarity_threshold', 0.7)
        self.enable_tool_caching = self.config.get('enable_tool_caching', True)

        # Workflow Generation Configuration
        self.max_workflow_steps = self.config.get('max_workflow_steps', 20)
        self.enable_parallel_execution = self.config.get('enable_parallel_execution', True)
        self.auto_parameter_inference = self.config.get('auto_parameter_inference', True)

        # Intent Parser Configuration
        self.intent_confidence_threshold = self.config.get('intent_confidence_threshold', 0.8)
        self.max_decomposition_depth = self.config.get('max_decomposition_depth', 3)

    def validate(self) -> bool:
        """Validate configuration settings."""
        # API key only required for non-local providers
        if self.llm_provider not in ['ollama', 'local'] and not self.llm_api_key:
            raise ValueError(f"LLM API key is required for provider: {self.llm_provider}")

        if self.similarity_threshold < 0 or self.similarity_threshold > 1:
            raise ValueError("similarity_threshold must be between 0 and 1")

        if self.intent_confidence_threshold < 0 or self.intent_confidence_threshold > 1:
            raise ValueError("intent_confidence_threshold must be between 0 and 1")

        return True

    def to_dict(self) -> Dict[str, Any]:
        """Convert configuration to dictionary."""
        return {
            'llm_provider': self.llm_provider,
            'llm_model': self.llm_model,
            'enable_hybrid_routing': self.enable_hybrid_routing,
            'prefer_local_models': self.prefer_local_models,
            'cost_sensitive_routing': self.cost_sensitive_routing,
            'ollama_base_url': self.ollama_base_url,
            'ollama_default_model': self.ollama_default_model,
            'zhipu_default_model': self.zhipu_default_model,
            'max_tools_per_task': self.max_tools_per_task,
            'similarity_threshold': self.similarity_threshold,
            'enable_tool_caching': self.enable_tool_caching,
            'max_workflow_steps': self.max_workflow_steps,
            'enable_parallel_execution': self.enable_parallel_execution,
            'auto_parameter_inference': self.auto_parameter_inference,
            'intent_confidence_threshold': self.intent_confidence_threshold,
            'max_decomposition_depth': self.max_decomposition_depth,
        }


# Default configuration - uses Claude as primary with hybrid routing disabled
DEFAULT_AI_CONFIG = AIConfig({
    'llm_provider': 'anthropic',
    'llm_model': 'claude-sonnet-4-5',
    'enable_hybrid_routing': False,
    'prefer_local_models': True,
    'cost_sensitive_routing': True,
    'ollama_default_model': 'qwen3:32b',
    'zhipu_default_model': 'glm-4.7',
    'max_tools_per_task': 5,
    'similarity_threshold': 0.7,
    'enable_tool_caching': True,
    'max_workflow_steps': 20,
    'enable_parallel_execution': True,
    'auto_parameter_inference': True,
    'intent_confidence_threshold': 0.8,
    'max_decomposition_depth': 3,
})