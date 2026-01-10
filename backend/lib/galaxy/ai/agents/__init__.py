"""
Multi-Agent System for BioMate

A lightweight 3-agent architecture with LLM-enhanced routing:
1. EnhancedDomainRouter - Routes requests with hybrid keyword + LLM approach
2. DomainSpecialist - Domain-specific tool selection (parallel LLM)
3. WorkflowAssembler - Synthesizes and validates workflows (1 LLM)

Supporting services:
- UserPatternsAdapter - User preference personalization
- WorkflowAuditService - Audit trail for all generations
- WorkflowLearningService - Learn from corrections and outcomes
"""

from .domain_router import DomainRouter, RoutingDecision
from .enhanced_domain_router import EnhancedDomainRouter, EnhancedRoutingDecision
from .domain_specialist import DomainSpecialistPool, DomainRecommendation
from .workflow_assembler import WorkflowAssembler, AssembledWorkflow
from .agent_orchestrator import AgentOrchestrator, OrchestrationResult, create_agent_orchestrator
from .user_patterns_adapter import UserPatternsAdapter

__all__ = [
    # Routers
    'DomainRouter',
    'RoutingDecision',
    'EnhancedDomainRouter',
    'EnhancedRoutingDecision',
    # Specialists
    'DomainSpecialistPool',
    'DomainRecommendation',
    # Assembler
    'WorkflowAssembler',
    'AssembledWorkflow',
    # Orchestrator
    'AgentOrchestrator',
    'OrchestrationResult',
    'create_agent_orchestrator',
    # Adapters
    'UserPatternsAdapter',
]
