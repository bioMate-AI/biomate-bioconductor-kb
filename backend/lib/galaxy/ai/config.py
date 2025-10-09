"""
AI Assistant Configuration

Configuration settings for the Galaxy AI Assistant module.
"""

from typing import Dict, Any, Optional
import os


class AIConfig:
    """Configuration for AI Assistant components."""
    
    def __init__(self, config_dict: Optional[Dict[str, Any]] = None):
        self.config = config_dict or {}
        
        # LLM Configuration
        self.llm_provider = self.config.get('llm_provider', 'openai')
        self.llm_model = self.config.get('llm_model', 'gpt-4')
        self.llm_api_key = self.config.get('llm_api_key', os.getenv('GALAXY_AI_API_KEY'))
        self.llm_base_url = self.config.get('llm_base_url', None)
        
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
        if not self.llm_api_key:
            raise ValueError("LLM API key is required")
        
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
            'max_tools_per_task': self.max_tools_per_task,
            'similarity_threshold': self.similarity_threshold,
            'enable_tool_caching': self.enable_tool_caching,
            'max_workflow_steps': self.max_workflow_steps,
            'enable_parallel_execution': self.enable_parallel_execution,
            'auto_parameter_inference': self.auto_parameter_inference,
            'intent_confidence_threshold': self.intent_confidence_threshold,
            'max_decomposition_depth': self.max_decomposition_depth,
        }


# Default configuration
DEFAULT_AI_CONFIG = AIConfig({
    'llm_provider': 'openai',
    'llm_model': 'gpt-4',
    'max_tools_per_task': 5,
    'similarity_threshold': 0.7,
    'enable_tool_caching': True,
    'max_workflow_steps': 20,
    'enable_parallel_execution': True,
    'auto_parameter_inference': True,
    'intent_confidence_threshold': 0.8,
    'max_decomposition_depth': 3,
})