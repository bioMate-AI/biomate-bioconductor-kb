"""
Agentic Memory Module

Provides long-term memory persistence for the AI assistant including:
- User profiles and learned preferences
- Project context and knowledge
- Episodic memory (interaction outcomes)
- Procedural memory (learned workflows)
"""

from .agentic_memory import (
    AgenticMemoryService,
    UserMemoryService,
    EpisodicMemoryService,
    ProceduralMemoryService,
    agentic_memory,
    get_memory_service,
    create_tables,
)

__all__ = [
    "AgenticMemoryService",
    "UserMemoryService",
    "EpisodicMemoryService",
    "ProceduralMemoryService",
    "agentic_memory",
    "get_memory_service",
    "create_tables",
]
