"""
AI Assistant Configuration for Galaxy

Configuration schema and validation for the Galaxy AI Assistant.
"""

import os
from typing import Dict, Any, Optional
from galaxy.util import string_as_bool
from ..ai.config import AIConfig


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
    
    # LLM Configuration
    ai_config_dict['llm_provider'] = raw_config.get('ai_llm_provider', 'openai')
    ai_config_dict['llm_model'] = raw_config.get('ai_llm_model', 'gpt-4')
    # Try ai_llm_api_key from config, then ANTHROPIC_API_KEY, then GALAXY_AI_API_KEY
    ai_config_dict['llm_api_key'] = raw_config.get('ai_llm_api_key') or os.getenv('ANTHROPIC_API_KEY') or os.getenv('GALAXY_AI_API_KEY')
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