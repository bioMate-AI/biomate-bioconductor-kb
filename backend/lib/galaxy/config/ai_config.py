"""
AI Assistant Configuration for Galaxy

Configuration schema and validation for the Galaxy AI Assistant.
"""

import os
from typing import Dict, Any, Optional
from galaxy.util import string_as_bool
from ..ai.config import AIConfig

# ---------------------------------------------------------------------------
# LangSmith / LangChain tracing configuration
# ---------------------------------------------------------------------------

#: LangSmith API key.  Set LANGSMITH_API_KEY in the environment to enable
#: tracing.  Defaults to None (tracing disabled).
LANGSMITH_API_KEY: Optional[str] = os.getenv("LANGSMITH_API_KEY", None)

#: Whether to enable LangChain v2 tracing (requires LANGSMITH_API_KEY).
#: Set LANGCHAIN_TRACING_V2=true in the environment to enable.
LANGCHAIN_TRACING_V2: bool = os.getenv("LANGCHAIN_TRACING_V2", "false").lower() in (
    "1", "true", "yes", "on"
)

#: LangSmith project name used to group traces.
LANGSMITH_PROJECT: str = os.getenv("LANGSMITH_PROJECT", "biomate")


def configure_langsmith() -> bool:
    """
    Configure the process environment for LangSmith tracing.

    Sets the ``LANGCHAIN_TRACING_V2``, ``LANGSMITH_API_KEY``, and
    ``LANGSMITH_PROJECT`` environment variables so that any LangChain /
    LangGraph calls made in this process are automatically traced.

    This function is a no-op (and returns ``False``) when
    ``LANGSMITH_API_KEY`` is not set, so it is safe to call unconditionally.

    Returns
    -------
    bool
        ``True`` if LangSmith tracing was activated, ``False`` otherwise.
    """
    if not LANGSMITH_API_KEY:
        return False

    os.environ["LANGSMITH_API_KEY"] = LANGSMITH_API_KEY
    os.environ["LANGCHAIN_TRACING_V2"] = "true" if LANGCHAIN_TRACING_V2 else "false"
    os.environ["LANGSMITH_PROJECT"] = LANGSMITH_PROJECT

    import logging
    logging.getLogger(__name__).info(
        "LangSmith tracing enabled — project=%r", LANGSMITH_PROJECT
    )
    return True


def configure_ai_assistant(
    raw_config: Dict[str, Any],
    global_config_dir: str
) -> Optional[AIConfig]:
    """Configure AI Assistant from Galaxy configuration."""
    
    # Check if AI Assistant is enabled
    if not string_as_bool(raw_config.get('enable_ai_assistant', False)):
        return None
    
    # Extract AI-specific configuration
    ai_config_dict = {}
    
    # LLM Configuration — auto-detect provider from available API keys
    _api_key = raw_config.get('ai_llm_api_key') or os.getenv('ANTHROPIC_API_KEY') or os.getenv('OPENAI_API_KEY') or os.getenv('GALAXY_AI_API_KEY')
    _explicit_provider = raw_config.get('ai_llm_provider') or os.getenv('GALAXY_AI_LLM_PROVIDER')
    if _explicit_provider:
        _provider = _explicit_provider
    elif os.getenv('ANTHROPIC_API_KEY'):
        _provider = 'anthropic'
    elif os.getenv('OPENAI_API_KEY'):
        _provider = 'openai'
    else:
        _provider = 'anthropic'  # Default to anthropic (BioMate default)
    ai_config_dict['llm_provider'] = _provider
    _default_model = 'claude-sonnet-4-6' if _provider == 'anthropic' else 'gpt-4'
    _configured_model = raw_config.get('ai_llm_model', _default_model)
    # If provider is anthropic but model is a GPT model name (from schema defaults),
    # fall back to the anthropic default model.
    _openai_prefixes = ('gpt-', 'o1', 'o3', 'text-davinci')
    if _provider == 'anthropic' and isinstance(_configured_model, str) and _configured_model.startswith(_openai_prefixes):
        _configured_model = _default_model
    ai_config_dict['llm_model'] = _configured_model
    ai_config_dict['llm_api_key'] = _api_key
    ai_config_dict['llm_base_url'] = raw_config.get('ai_llm_base_url')
    
    # Tool Discovery Configuration
    ai_config_dict['max_tools_per_task'] = int(raw_config.get('ai_max_tools_per_task', 5))
    ai_config_dict['similarity_threshold'] = float(raw_config.get('ai_similarity_threshold', 0.7))
    ai_config_dict['enable_tool_caching'] = string_as_bool(raw_config.get('ai_enable_tool_caching', True))
    
    # Workflow Generation Configuration
    ai_config_dict['max_workflow_steps'] = int(raw_config.get('ai_max_workflow_steps', 20))
    ai_config_dict['enable_parallel_execution'] = string_as_bool(raw_config.get('ai_enable_parallel_execution', True))
    ai_config_dict['auto_parameter_inference'] = string_as_bool(raw_config.get('ai_auto_parameter_inference', True))
    
    # Intent Parser Configuration
    ai_config_dict['intent_confidence_threshold'] = float(raw_config.get('ai_intent_confidence_threshold', 0.8))
    ai_config_dict['max_decomposition_depth'] = int(raw_config.get('ai_max_decomposition_depth', 3))
    
    try:
        ai_config = AIConfig(ai_config_dict)
        ai_config.validate()
        return ai_config
    except Exception as e:
        # Log error but don't fail Galaxy startup
        import logging
        log = logging.getLogger(__name__)
        log.error(f"Failed to configure AI Assistant: {e}")
        return None


def get_ai_config_schema() -> Dict[str, Any]:
    """Get the configuration schema for AI Assistant settings."""
    
    return {
        'enable_ai_assistant': {
            'type': 'bool',
            'default': False,
            'desc': 'Enable Galaxy AI Assistant functionality'
        },
        'ai_llm_provider': {
            'type': 'str',
            'default': 'openai',
            'desc': 'LLM provider (openai, anthropic, local)'
        },
        'ai_llm_model': {
            'type': 'str',
            'default': 'gpt-4',
            'desc': 'LLM model to use'
        },
        'ai_llm_api_key': {
            'type': 'str',
            'default': None,
            'desc': 'API key for LLM provider'
        },
        'ai_llm_base_url': {
            'type': 'str',
            'default': None,
            'desc': 'Base URL for LLM API (for local or custom endpoints)'
        },
        'ai_max_tools_per_task': {
            'type': 'int',
            'default': 5,
            'desc': 'Maximum number of tools to recommend per task'
        },
        'ai_similarity_threshold': {
            'type': 'float',
            'default': 0.7,
            'desc': 'Similarity threshold for tool matching'
        },
        'ai_enable_tool_caching': {
            'type': 'bool',
            'default': True,
            'desc': 'Enable caching of tool recommendations'
        },
        'ai_max_workflow_steps': {
            'type': 'int',
            'default': 20,
            'desc': 'Maximum number of steps in generated workflows'
        },
        'ai_enable_parallel_execution': {
            'type': 'bool',
            'default': True,
            'desc': 'Enable parallel execution optimization in workflows'
        },
        'ai_auto_parameter_inference': {
            'type': 'bool',
            'default': True,
            'desc': 'Enable automatic parameter inference for tools'
        },
        'ai_intent_confidence_threshold': {
            'type': 'float',
            'default': 0.8,
            'desc': 'Confidence threshold for intent classification'
        },
        'ai_max_decomposition_depth': {
            'type': 'int',
            'default': 3,
            'desc': 'Maximum depth for task decomposition'
        }
    }