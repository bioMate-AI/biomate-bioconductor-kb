"""
RAG-enabled AI Assistant Initialization Helper

This module provides helper functions to initialize the AI Assistant with RAG capabilities.
"""

import os
from .ai_assistant import AIAssistant
from .config import DEFAULT_AI_CONFIG

# Default crawler data path
CRAWLER_DATA_PATH = "/Users/renyuankai/work/pywork/normalWork/galaxy_爬虫/galaxy_crawler/galaxy_workflows_crawler/data"

def create_rag_enabled_assistant(config=None, galaxy_app=None, crawler_data_path=None):
    """Create an AI Assistant with RAG workflow generation enabled."""
    
    if crawler_data_path is None:
        crawler_data_path = CRAWLER_DATA_PATH
    
    if not os.path.exists(crawler_data_path):
        print(f"Warning: Crawler data path not found: {crawler_data_path}")
        print("RAG workflow generator will be disabled")
        crawler_data_path = None
    
    return AIAssistant(
        config=config or DEFAULT_AI_CONFIG,
        galaxy_app=galaxy_app,
        crawler_data_path=crawler_data_path
    )

def get_rag_stats(assistant):
    """Get RAG system statistics."""
    if hasattr(assistant, 'rag_recommender') and assistant.rag_recommender:
        workflow_count = len(assistant.rag_recommender.workflows)
        return {
            "status": "available",
            "workflow_count": workflow_count,
            "rag_engine": "SimpleRAGEngine"
        }
    else:
        return {"error": "RAG recommender not available"}
