"""
Galaxy AI Assistant

Main orchestrator that combines all AI components to provide intelligent research assistance.
"""

import hashlib
import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime
from pathlib import Path
import sqlite3
import re

from .types import (
    UserRequest, AIResponse, Task, Tool, ToolRecommendation,
    WorkflowTemplate, WorkflowStep, IntentType, TaskType
)
from .config import AIConfig, DEFAULT_AI_CONFIG
from .intent_parser import IntentParser
from .task_decomposer import TaskDecomposer
from .tool_recommender import ToolRecommender
from .tool_discovery import ToolIndexer, ToolDiscoveryEngine
from .enhanced_workflow_generator import EnhancedWorkflowGenerator
from .workflow_templates import WorkflowTemplateLibrary
from .workflow_optimizer import WorkflowOptimizer, WorkflowValidator, OptimizationStrategy
# NEW: Unified workflow generation components
from .unified_workflow_search import UnifiedWorkflowSearch, get_workflow_search
from .unified_tool_search import create_unified_search
from .galaxy_workflow_generator import GalaxyWorkflowGenerator
from .workflow_dataset_selector import WorkflowDatasetSelector
from .biomni_dataset_rag import BioMNIDatasetRAG
from .benchmark_knowledge import BenchmarkKnowledgeDB
from .tool_knowledge_provider import ToolKnowledgeProvider
import json
import logging

# Import new agents (Added 2025-12-30)
try:
    from .agents.unified_intent_router import UnifiedIntentRouter, UserIntent, create_intent_router
    from .agents.research_agent import ResearchAgent, create_research_agent
    from .agents.skill_loader import SkillLoader, create_skill_loader
    INTENT_ROUTER_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Intent router components not available: {e}")
    INTENT_ROUTER_AVAILABLE = False
    UnifiedIntentRouter = None
    UserIntent = None
    ResearchAgent = None
    SkillLoader = None

# Import agentic memory and literature clients (Added 2025-12-30)
try:
    from .memory import AgenticMemoryService, get_memory_service
    from .agents.literature_clients import UnifiedLiteratureClient, create_literature_client
    MEMORY_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Memory/literature components not available: {e}")
    MEMORY_AVAILABLE = False
    AgenticMemoryService = None
    UnifiedLiteratureClient = None

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Module-level bounded cache for multi-task LLM classification results.
# Keyed by MD5 of the lowercased query; evicts oldest entry when full.
# ---------------------------------------------------------------------------
_MULTI_TASK_CACHE: dict = {}
_MULTI_TASK_CACHE_MAX = 128

# Fastest/cheapest model per provider for lightweight classification calls.
_FAST_CLASSIFICATION_MODELS: dict = {
    'anthropic': 'claude-haiku-3-5',
    'openai': 'gpt-3.5-turbo',
    'gemini': 'gemini-1.5-flash',
    'google': 'gemini-1.5-flash',
    'deepseek': 'deepseek-chat',
    'zhipu': 'glm-4-flash',
    # ollama / local: keep configured model (already fast locally)
}


class AIAssistant:
    """Main Galaxy AI Assistant that orchestrates the entire AI pipeline."""
    
    def __init__(self, config: Optional[AIConfig] = None, galaxy_app=None):
        self.config = config or DEFAULT_AI_CONFIG
        self.config.validate()

        self.galaxy_app = galaxy_app

        # ONLY initialize components needed for generate_workflow_unified()
        self.workflow_search = get_workflow_search()  # UnifiedWorkflowSearch with 951+ workflows
        # N5: inject fast-LLM client into search for Pass-0 catalog browse (lazy — done after
        # _fast_llm_client is built on first call, so we register it here with a placeholder
        # and update after first use.  Actual injection happens in fast_llm_classify.)
        # NOTE: injection happens lazily on first fast_llm_classify call (see _inject_search_llm).
        self._tool_search = None  # Lazy-loaded UnifiedToolSearch
        self.constrained_generator = GalaxyWorkflowGenerator(config=self.config)
        self.dataset_selector = WorkflowDatasetSelector()
        self._nextflow_composer = None  # Lazy-loaded NextflowComposer

        # Lazy-load other components only when needed
        self._workflow_generator = None  # EnhancedWorkflowGenerator - lazy loaded
        self._intent_parser = None
        self._task_decomposer = None
        self._tool_recommender = None
        self._template_library = None
        self._workflow_optimizer = None
        self._workflow_validator = None
        self._tool_indexer = None
        self._tool_discovery = None
        self._dataset_rag = None
        self._agent_orchestrator = None  # Multi-agent system
        self._benchmark_db = None  # Benchmark knowledge for tool recommendations
        self._intent_router = None  # UnifiedIntentRouter for intent classification
        self._research_agent = None  # ResearchAgent for literature-backed Q&A
        self._skill_loader = None  # SkillLoader for claude-scientific-skills
        self._agentic_memory = None  # AgenticMemoryService for long-term memory
        self._literature_client = None  # UnifiedLiteratureClient for citation retrieval
        self._fast_llm_client = None   # Cheap/fast LLMClient for classification tasks

        # LangGraph pipeline — built lazily on first use; shared across requests.
        # Enabled when BIOMATE_USE_LANGGRAPH=true (default: off, safe rollout).
        self._langgraph_pipeline = None  # CompiledStateGraph | None

        # Enable LangSmith tracing if API key is configured (no-op if not set)
        try:
            from galaxy.config.ai_config import configure_langsmith
            configure_langsmith()
        except Exception:
            pass

        log.info("AIAssistant initialized (lightweight mode)")
        log.info(f"  - Workflow search: UnifiedWorkflowSearch (database-backed)")

        # Cache for frequently used data
        self._tool_cache = {}
        self._workflow_cache = {}
        self._tools_indexed = False  # Lazy loading flag for tool indexing

    def _normalize_tool_id(self, tool_id: str) -> str:
        """
        Normalize tool ID to match Galaxy's loaded tool format.

        The AI database stores tool IDs with slashes (biomni/database/query_uniprot)
        but Galaxy loads tools with underscores (biomni_database_query_uniprot).

        Args:
            tool_id: Tool ID from AI database (may use slashes or underscores)

        Returns:
            Normalized tool ID using underscores
        """
        if tool_id.startswith('biomni/'):
            # Convert biomni/X/Y to biomni_X_Y
            return tool_id.replace('/', '_')
        return tool_id

    # Lazy-loaded properties
    @property
    def workflow_generator(self):
        """Lazy-load EnhancedWorkflowGenerator."""
        if self._workflow_generator is None:
            self._workflow_generator = EnhancedWorkflowGenerator(self.config, self.galaxy_app)
            log.info("EnhancedWorkflowGenerator loaded on-demand")
        return self._workflow_generator

    @property
    def intent_parser(self):
        """Lazy-load IntentParser."""
        if self._intent_parser is None:
            self._intent_parser = IntentParser(self.config)
            log.info("IntentParser loaded on-demand")
        return self._intent_parser

    @property
    def task_decomposer(self):
        """Lazy-load TaskDecomposer."""
        if self._task_decomposer is None:
            self._task_decomposer = TaskDecomposer(self.config)
            log.info("TaskDecomposer loaded on-demand")
        return self._task_decomposer

    @property
    def nextflow_composer(self):
        """Lazy-load NextflowComposer for Nextflow-native workflow generation."""
        if self._nextflow_composer is None:
            from .nextflow_composer import NextflowComposer
            self._nextflow_composer = NextflowComposer(config=self.config)
            log.info("NextflowComposer loaded on-demand")
        return self._nextflow_composer

    @property
    def tool_recommender(self):
        """Lazy-load ToolRecommender."""
        if self._tool_recommender is None:
            self._tool_recommender = ToolRecommender(self.config)
            log.info("ToolRecommender loaded on-demand")
        return self._tool_recommender

    @property
    def template_library(self):
        """Lazy-load WorkflowTemplateLibrary."""
        if self._template_library is None:
            self._template_library = WorkflowTemplateLibrary()
            log.info("WorkflowTemplateLibrary loaded on-demand")
        return self._template_library

    @property
    def workflow_optimizer(self):
        """Lazy-load WorkflowOptimizer."""
        if self._workflow_optimizer is None:
            self._workflow_optimizer = WorkflowOptimizer(self.config)
            log.info("WorkflowOptimizer loaded on-demand")
        return self._workflow_optimizer

    @property
    def workflow_validator(self):
        """Lazy-load WorkflowValidator."""
        if self._workflow_validator is None:
            self._workflow_validator = WorkflowValidator(self.config)
            log.info("WorkflowValidator loaded on-demand")
        return self._workflow_validator

    @property
    def tool_indexer(self):
        """Lazy-load ToolIndexer."""
        if self._tool_indexer is None:
            self._tool_indexer = ToolIndexer(self.config)
            log.info("ToolIndexer loaded on-demand")
        return self._tool_indexer

    @property
    def tool_discovery(self):
        """Lazy-load ToolDiscoveryEngine."""
        if self._tool_discovery is None:
            self._tool_discovery = ToolDiscoveryEngine(self.config, self.tool_indexer)
            log.info("ToolDiscoveryEngine loaded on-demand")
        return self._tool_discovery

    @property
    def dataset_rag(self):
        """Lazy-load BioMNIDatasetRAG."""
        if self._dataset_rag is None:
            self._dataset_rag = BioMNIDatasetRAG()
            log.info("BioMNIDatasetRAG loaded on-demand")
        return self._dataset_rag

    @property
    def benchmark_db(self):
        """Lazy-load BenchmarkKnowledgeDB for tool recommendations."""
        if self._benchmark_db is None:
            self._benchmark_db = BenchmarkKnowledgeDB(enable_semantic=True)
            log.info("BenchmarkKnowledgeDB loaded on-demand")
        return self._benchmark_db

    @property
    def intent_router(self):
        """Lazy-load UnifiedIntentRouter for intent classification."""
        if self._intent_router is None and INTENT_ROUTER_AVAILABLE:
            self._intent_router = create_intent_router()
            log.info("UnifiedIntentRouter loaded on-demand")
        return self._intent_router

    @property
    def skill_loader(self):
        """Lazy-load SkillLoader for claude-scientific-skills."""
        if self._skill_loader is None and INTENT_ROUTER_AVAILABLE:
            self._skill_loader = create_skill_loader()
            log.info("SkillLoader loaded on-demand")
        return self._skill_loader

    @property
    def research_agent(self):
        """Lazy-load ResearchAgent for literature-backed Q&A."""
        if self._research_agent is None and INTENT_ROUTER_AVAILABLE:
            self._research_agent = create_research_agent(
                skill_loader=self.skill_loader,
                benchmark_db=self.benchmark_db,
                literature_client=self.literature_client
            )
            log.info("ResearchAgent loaded on-demand")
        return self._research_agent

    @property
    def agentic_memory(self):
        """Lazy-load AgenticMemoryService for long-term memory persistence."""
        if self._agentic_memory is None and MEMORY_AVAILABLE:
            self._agentic_memory = get_memory_service()
            log.info("AgenticMemoryService loaded on-demand")
        return self._agentic_memory

    @property
    def literature_client(self):
        """Lazy-load UnifiedLiteratureClient for literature search."""
        if self._literature_client is None and MEMORY_AVAILABLE:
            self._literature_client = create_literature_client()
            log.info("UnifiedLiteratureClient loaded on-demand")
        return self._literature_client

    # =========================================================================
    # UNIFIED INTENT ROUTING API (Added 2025-12-30)
    # =========================================================================

    def classify_intent(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Classify the intent of a user query.

        Routes to appropriate handler:
        - workflow_generation → AgentOrchestrator
        - research_question → ResearchAgent
        - result_comparison → ResearchAgent + BenchmarkKnowledge
        - tool_search → UnifiedToolSearch
        - benchmark_query → BenchmarkKnowledgeDB (direct)

        Args:
            query: User's query text
            context: Optional context (previous messages, domain, etc.)

        Returns:
            Dict with:
            - intent: Primary intent type
            - confidence: Classification confidence
            - handler: Recommended handler
            - requires_workflow: Whether workflow generation is needed
            - requires_literature: Whether literature search is needed
            - requires_benchmark: Whether benchmark data is needed
            - entities: Extracted entities (tools, analysis types, etc.)
        """
        if not INTENT_ROUTER_AVAILABLE or not self.intent_router:
            # Fallback to simple keyword detection
            return self._simple_intent_classify(query)

        classification = self.intent_router.classify(query, context)

        return {
            "intent": classification.primary_intent.value,
            "confidence": classification.confidence,
            "handler": self.intent_router.get_handler_for_intent(classification.primary_intent),
            "secondary_intents": [i.value for i in classification.secondary_intents],
            "requires_workflow": classification.requires_workflow,
            "requires_literature": classification.requires_literature,
            "requires_benchmark": classification.requires_benchmark,
            "entities": classification.extracted_entities,
            "routing_method": classification.routing_method
        }

    def _simple_intent_classify(self, query: str) -> Dict[str, Any]:
        """Simple keyword-based intent classification as fallback."""
        query_lower = query.lower()

        # Simple rules
        if any(w in query_lower for w in ['workflow', 'pipeline', 'run analysis', 'process']):
            intent = 'workflow_generation'
            handler = 'agent_orchestrator'
        elif any(w in query_lower for w in ['compare', 'vs', 'better', 'best']):
            intent = 'result_comparison'
            handler = 'research_agent'
        elif any(w in query_lower for w in ['benchmark', 'performance']):
            intent = 'benchmark_query'
            handler = 'benchmark_knowledge'
        elif any(w in query_lower for w in ['find tool', 'search tool', 'available tools']):
            intent = 'tool_search'
            handler = 'unified_tool_search'
        else:
            intent = 'research_question'
            handler = 'research_agent'

        return {
            "intent": intent,
            "confidence": 0.6,
            "handler": handler,
            "secondary_intents": [],
            "requires_workflow": intent == 'workflow_generation',
            "requires_literature": intent in ['research_question', 'result_comparison'],
            "requires_benchmark": intent in ['result_comparison', 'benchmark_query'],
            "entities": {},
            "routing_method": "simple_fallback"
        }

    async def route_and_handle(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Route a query to the appropriate handler and execute.

        This is the main entry point for the unified AI assistant that
        automatically determines intent and routes to the right component.

        Args:
            query: User's query text
            context: Optional context

        Returns:
            Response from the appropriate handler
        """
        # Step 0: Multi-task detection — surface clarification as plain text reply
        _ctx = context or {}
        _uid = _ctx.get('userId', '') or _ctx.get('user_id', '')
        _sid = _ctx.get('sessionId', '') or _ctx.get('session_id', '')
        if self._looks_like_multi_task(query, user_id=_uid, session_id=_sid):
            return await self._handle_multi_task_clarification(query, _ctx)

        # Step 1: Classify intent
        classification = self.classify_intent(query, context)

        # Step 2: Route to handler
        handler = classification.get('handler', 'research_agent')
        intent = classification.get('intent', 'research_question')

        try:
            if handler == 'agent_orchestrator':
                # Workflow generation
                return await self._handle_workflow_generation(query, context)

            elif handler == 'research_agent':
                # Research questions, comparisons, conclusions
                return await self._handle_research_query(query, classification, context)

            elif handler == 'benchmark_knowledge':
                # Direct benchmark queries
                return self._handle_benchmark_query(query)

            elif handler == 'unified_tool_search':
                # Tool search
                return self._handle_tool_search(query, context)

            else:
                # Default to research agent
                return await self._handle_research_query(query, classification, context)

        except Exception as e:
            log.error(f"Error handling query: {e}")
            return {
                "success": False,
                "error": str(e),
                "intent": intent,
                "handler": handler
            }

    async def _handle_workflow_generation(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Handle workflow generation requests."""
        # Use the existing generate_workflow_unified method
        datasets = context.get('datasets', []) if context else []
        result = self.generate_workflow_unified(query, available_datasets=datasets)
        return {
            "success": result.get('success', False),
            "handler": "agent_orchestrator",
            "workflow": result.get('workflow_ga'),
            "source": result.get('source'),
            "confidence": result.get('confidence'),
            "message": result.get('message')
        }

    # ------------------------------------------------------------------
    # Multi-task detection (Phase D)
    # ------------------------------------------------------------------

    def _looks_like_multi_task(self, query: str, user_id: str = "", session_id: str = "") -> bool:
        """
        Use a fast LLM call to decide whether the query is requesting multiple
        distinct workflow tasks.  Results are cached (up to _MULTI_TASK_CACHE_MAX
        entries) so repeated queries never re-invoke the LLM.

        Falls back to False (single-task path) on any LLM error so that the
        system degrades gracefully rather than blocking the user.
        """
        cache_key = hashlib.md5(query.lower().strip().encode()).hexdigest()
        if cache_key in _MULTI_TASK_CACHE:
            cached = _MULTI_TASK_CACHE[cache_key]
            log.debug(f"[MultiTask] Cache hit ({cached['reason']!r}): is_multi={cached['is_multi_task']}")
            return cached['is_multi_task']

        try:
            result = self._classify_multi_task_llm(query, user_id=user_id, session_id=session_id)
            # Evict oldest entry when the cache is full
            if len(_MULTI_TASK_CACHE) >= _MULTI_TASK_CACHE_MAX:
                oldest_key = next(iter(_MULTI_TASK_CACHE))
                del _MULTI_TASK_CACHE[oldest_key]
            _MULTI_TASK_CACHE[cache_key] = result
            log.info(
                "[MultiTask] Classified as %s-task (count=%d): %s",
                "multi" if result['is_multi_task'] else "single",
                result['task_count'],
                result['reason'],
            )
            return result['is_multi_task']
        except Exception as exc:
            log.warning("[MultiTask] LLM classification failed (%s), defaulting to single-task", exc)
            return False

    def _classify_multi_task_llm(self, query: str, user_id: str = "", session_id: str = "") -> dict:
        """
        Single fast LLM call that returns a classification dict:
            {'is_multi_task': bool, 'task_count': int, 'reason': str}
        Raises on any LLM or JSON parse error (caller handles the fallback).
        """
        prompt = (
            "You are a query classifier for a bioinformatics workflow system.\n\n"
            "Determine whether the following user query requests MULTIPLE distinct "
            "computational workflow steps that should be executed as separate tasks, "
            "or a SINGLE workflow request.\n\n"
            "A MULTI-TASK query explicitly chains several distinct analyses "
            "(e.g., 'run QC, then alignment, then variant calling' — 3 tasks).\n"
            "A SINGLE-TASK query asks for one thing, even if complex "
            "(e.g., 'run differential expression on my RNA-seq data' — 1 task).\n\n"
            "Respond with JSON only, no explanation outside the JSON:\n"
            '{"is_multi_task": true|false, "task_count": <integer>, "reason": "<one sentence>"}\n\n'
            f"Query: {query}"
        )
        response_text = self._call_llm_fast(prompt, user_id=user_id, session_id=session_id)

        # Strip markdown code fences if the model wrapped the JSON
        clean = response_text.strip()
        if clean.startswith("```"):
            parts = clean.split("```")
            clean = parts[1] if len(parts) > 1 else clean
            if clean.startswith("json"):
                clean = clean[4:]
        clean = clean.strip()

        parsed = json.loads(clean)
        return {
            'is_multi_task': bool(parsed.get('is_multi_task', False)),
            'task_count': int(parsed.get('task_count', 1)),
            'reason': str(parsed.get('reason', '')),
        }

    def _call_llm_fast(self, prompt: str, user_id: str = "", session_id: str = "") -> str:
        """
        Synchronous single LLM call using the cheapest/fastest model available
        for the configured provider.  The client is lazy-initialised and reused
        across calls (no new HTTP connection overhead per classification).

        user_id and session_id are forwarded to the billing hook inside LLMClient
        so classification calls are correctly attributed to the requesting user.
        """
        if self._fast_llm_client is None:
            from .llm_client import LLMClient
            client = LLMClient(self.config)
            provider = self.config.llm_provider.lower()
            fast_model = _FAST_CLASSIFICATION_MODELS.get(provider)
            if fast_model:
                # Override only the model; keep all auth/endpoint settings unchanged
                client.model = fast_model
            self._fast_llm_client = client
            # N5: wire fast-LLM into the workflow search singleton for Pass-0 browse.
            # Done exactly once here — when the client is first created.
            try:
                self.workflow_search.set_llm_client(self._fast_llm_client)
            except Exception:
                pass

        # Update billing attribution on every call so events reach the right user
        if user_id:
            self._fast_llm_client.user_id = user_id
        if session_id:
            self._fast_llm_client.session_id = session_id

        return self._fast_llm_client.generate(prompt, max_tokens=128, temperature=0.0)

    async def _handle_multi_task_clarification(self, query: str, context: dict) -> dict:
        """
        For multi-task queries: decompose into tasks, check what's missing,
        and return either a clarification question OR proceed to generation.
        Clarification surfaces as a normal text response — no special UI needed.
        """
        import uuid as uuid_mod
        pipeline_id = str(uuid_mod.uuid4())

        try:
            from .task_decomposer import TaskDecomposer
            from .types import UserRequest, IntentType

            decomposer = self.task_decomposer
            user_request = UserRequest(
                user_id=context.get('userId', 'anon'),
                request_text=query,
                context=context,
            )

            # Parse intent and decompose
            parsed_intent = decomposer.parse_intent(query)
            tasks = decomposer.decompose_request(user_request, parsed_intent)

            if not tasks:
                return await self._handle_workflow_generation(query, context)

            # Check for missing required context
            missing = self._find_missing_context(tasks, context)

            if missing:
                questions_text = '\n'.join(f'{i+1}. {q}' for i, q in enumerate(missing))
                clarification_message = (
                    f"Before I prepare your {len(tasks)}-step workflow, I have a few questions:\n\n"
                    f"{questions_text}\n\n"
                    f"Once you answer, I'll get started right away."
                )
                return {
                    'message': clarification_message,
                    'success': True,
                    'needs_clarification': True,
                    'pipeline_id': pipeline_id,
                    'pending_tasks': [
                        {'id': t.id, 'description': t.description, 'status': 'waiting_for_input'}
                        for t in tasks
                    ],
                }

            # No missing context — fall back to single-task generation for now.
            # Full parallel dispatch (LangGraph + Celery) is Phase 1 of the main plan.
            log.info(f"[MultiTask] {len(tasks)} tasks detected, generating sequentially for now")
            return await self._handle_workflow_generation(query, context)

        except Exception as e:
            log.warning(f"[MultiTask] Decomposition failed ({e}), falling back to single-task")
            return await self._handle_workflow_generation(query, context)

    def _find_missing_context(self, tasks: list, context: dict) -> list:
        """Return list of clarification questions for missing required parameters."""
        missing = []
        ctx = context or {}

        has_organism = any(
            k in ctx for k in ('organism', 'species', 'genome', 'reference')
        ) or any(
            k in str(ctx.get('accumulatedFacts', ''))
            for k in ('organism', 'species', 'homo sapiens', 'mus musculus', 'human', 'mouse')
        )

        needs_seq = any(
            any(kw in t.description.lower() for kw in ('rna', 'seq', 'fastq', 'align', 'mapping', 'qc'))
            for t in tasks
        )

        if needs_seq and not has_organism:
            missing.append("What organism are you working with? (e.g., Homo sapiens, Mus musculus)")

        if needs_seq and 'read_type' not in ctx and 'paired' not in str(ctx.get('accumulatedFacts', '')):
            missing.append("Are your reads paired-end or single-end?")

        return missing

    async def _handle_research_query(
        self,
        query: str,
        classification: Dict[str, Any],
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Handle research questions using ResearchAgent."""
        if not self.research_agent:
            # Fallback to benchmark query
            return self._handle_benchmark_query(query)

        response = self.research_agent.answer_question_sync(
            question=query,
            context=context,
            include_citations=True,
            include_benchmark_evidence=classification.get('requires_benchmark', True)
        )

        return {
            "success": not response.error,
            "handler": "research_agent",
            "answer": response.answer,
            "citations": [
                {
                    "title": c.title,
                    "authors": c.authors,
                    "year": c.year,
                    "journal": c.journal,
                    "doi": c.doi,
                    "pmid": c.pmid,
                    "url": getattr(c, 'url', None),
                    "source": getattr(c, 'source', None),
                    "citation_count": getattr(c, 'citation_count', 0),
                }
                for c in response.citations
            ],
            "benchmark_evidence": response.benchmark_evidence,
            "confidence": response.confidence,
            "follow_up_questions": response.follow_up_questions
        }

    def _handle_benchmark_query(self, query: str) -> Dict[str, Any]:
        """Handle direct benchmark queries."""
        result = self.query_benchmark(query, top_k=5)
        return {
            "success": True,
            "handler": "benchmark_knowledge",
            "best_tool": result.get('best_tool'),
            "evidence": result.get('evidence'),
            "results": result.get('results', [])
        }

    def _handle_tool_search(
        self,
        query: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Handle tool search requests."""
        # Lazy-load tool search
        if self._tool_search is None:
            self._tool_search = create_unified_search()

        tools = self._tool_search.search(query, limit=10)
        return {
            "success": True,
            "handler": "unified_tool_search",
            "tools": tools,
            "count": len(tools)
        }

    # =========================================================================
    # AGENTIC MEMORY API (For Session Context and Learning)
    # =========================================================================

    def initialize_session(
        self,
        user_id: str,
        project_id: Optional[str] = None,
        session_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Initialize session context using agentic memory.

        Retrieves user preferences, project context, and learned patterns
        to personalize the AI assistant's behavior for this session.

        Args:
            user_id: User identifier
            project_id: Optional project identifier
            session_id: Optional session ID (generated if not provided)

        Returns:
            Dict with:
            - session_id: Session identifier
            - user_preferences: User's learned preferences
            - project_context: Project-specific context
            - recent_episodes: Recent relevant interactions
            - learned_workflows: Reusable workflow patterns
        """
        if not MEMORY_AVAILABLE or not self.agentic_memory:
            return {
                'session_id': session_id or str(uuid.uuid4()),
                'user_preferences': {},
                'project_context': {},
                'recent_episodes': [],
                'learned_workflows': []
            }

        try:
            # Initialize session context from memory service
            context = self.agentic_memory.initialize_session_context(
                user_id=user_id,
                project_id=project_id
            )

            # Add session_id
            context['session_id'] = session_id or str(uuid.uuid4())

            log.info(f"Session initialized for user {user_id}, project {project_id}")
            return context

        except Exception as e:
            log.warning(f"Failed to initialize session context: {e}")
            return {
                'session_id': session_id or str(uuid.uuid4()),
                'user_preferences': {},
                'project_context': {},
                'recent_episodes': [],
                'learned_workflows': []
            }

    def record_interaction(
        self,
        project_id: str,
        session_id: str,
        user_input: str,
        agent_response: str,
        tool_calls: Optional[List[Dict]] = None,
        outcome: Optional[Dict] = None,
        metadata: Optional[Dict] = None,
        workflow_generated: bool = False,
        workflow_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Record an interaction for learning and episodic memory.

        Stores the interaction, extracts learnable patterns, and updates
        episodic memory for future context retrieval.

        Args:
            project_id: Project identifier
            session_id: Session identifier
            user_input: User's input text
            agent_response: AI's response
            tool_calls: Optional list of tool calls made
            outcome: Optional outcome information (success, error, etc.)
            metadata: Optional additional metadata
            workflow_generated: Whether a workflow was generated
            workflow_id: Optional workflow ID if generated

        Returns:
            Dict with:
            - message_id: Stored message ID
            - episode_id: Episode ID if applicable
            - patterns_learned: Any patterns extracted
        """
        if not MEMORY_AVAILABLE or not self.agentic_memory:
            return {
                'message_id': None,
                'episode_id': None,
                'patterns_learned': []
            }

        try:
            # Map to AgenticMemoryService's parameter names
            result = self.agentic_memory.record_interaction(
                project_id=project_id,
                session_id=session_id,
                user_query=user_input,  # Map user_input -> user_query
                assistant_response=agent_response,  # Map agent_response -> assistant_response
                tools_used=tool_calls,  # Map tool_calls -> tools_used
                workflow_generated=workflow_generated,
                workflow_id=workflow_id
            )

            return result

        except Exception as e:
            log.warning(f"Failed to record interaction: {e}")
            return {
                'message_id': None,
                'episode_id': None,
                'patterns_learned': []
            }

    def learn_from_outcome(
        self,
        episode_id: int,
        success: bool,
        reflection: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Learn from an episode outcome.

        Updates the episode with outcome information and extracts
        procedural patterns for future use.

        Args:
            episode_id: Episode identifier
            success: Whether the episode was successful
            reflection: Optional reflection/analysis

        Returns:
            Dict with learning results
        """
        if not MEMORY_AVAILABLE or not self.agentic_memory:
            return {'success': False, 'reason': 'Memory service not available'}

        try:
            self.agentic_memory.learn_from_outcome(
                episode_id=episode_id,
                success=success,
                reflection=reflection
            )

            return {'success': True}

        except Exception as e:
            log.warning(f"Failed to learn from outcome: {e}")
            return {'success': False, 'reason': str(e)}

    async def search_literature(
        self,
        query: str,
        max_results: int = 10,
        sources: Optional[List[str]] = None,
        recent_years: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Search scientific literature using the UnifiedLiteratureClient.

        Args:
            query: Search query
            max_results: Maximum results to return
            sources: Optional list of sources ("pubmed", "arxiv", "semantic_scholar")
            recent_years: Limit to papers from recent N years

        Returns:
            List of citation dictionaries
        """
        if not MEMORY_AVAILABLE or not self.literature_client:
            return []

        try:
            citations = await self.literature_client.search_bioinformatics(
                query=query,
                max_results=max_results,
                recent_years=recent_years
            )

            return [c.to_dict() for c in citations]

        except Exception as e:
            log.warning(f"Literature search failed: {e}")
            return []

    def search_literature_sync(
        self,
        query: str,
        max_results: int = 10,
        sources: Optional[List[str]] = None,
        recent_years: int = 5
    ) -> List[Dict[str, Any]]:
        """Synchronous wrapper for search_literature.

        Properly handles event loop creation to avoid "Event loop is closed" errors.
        Works correctly in Python 3.10+ where get_event_loop() behavior changed.
        """
        import asyncio
        import concurrent.futures

        async_coro = self.search_literature(
            query=query,
            max_results=max_results,
            sources=sources,
            recent_years=recent_years
        )

        # Check if we're already inside an async context
        try:
            loop = asyncio.get_running_loop()
            # We're inside an async context - run in a separate thread
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(asyncio.run, async_coro)
                return future.result()
        except RuntimeError:
            # No running event loop - safe to use asyncio.run()
            return asyncio.run(async_coro)

    # =========================================================================
    # BENCHMARK KNOWLEDGE API (For ResearchAgent and Workflow Generation)
    # =========================================================================

    def query_benchmark(
        self,
        query: str,
        top_k: int = 5,
        include_evidence: bool = True
    ) -> Dict[str, Any]:
        """
        Query benchmark knowledge with natural language.

        USE CASE: ResearchAgent answering "What's the best tool for X?"

        Args:
            query: Natural language query (e.g., "best RNA-seq aligner")
            top_k: Number of results
            include_evidence: Whether to include citation evidence

        Returns:
            Dict with:
            - results: List of benchmark matches with rankings
            - best_tool: Top recommended tool (if applicable)
            - evidence: Human-readable evidence with citations

        Example:
            >>> ai.query_benchmark("What's the best tool for variant calling?")
            {'best_tool': 'DeepVariant', 'evidence': 'Based on GIAB benchmark...'}
        """
        results = self.benchmark_db.query_semantic(query, top_k=top_k)

        if not results:
            return {
                'success': False,
                'message': 'No benchmark data found for this query',
                'results': []
            }

        # Find best tool recommendation
        best_tool = None
        evidence_text = None

        for r in results:
            if r.get('type') == 'task' and r.get('best_tool'):
                best_tool = r['best_tool']
                evidence_text = r.get('evidence', '')
                break
            elif r.get('type') == 'rule' and r.get('recommended_tools'):
                best_tool = r['recommended_tools'][0] if r['recommended_tools'] else None
                evidence_text = r.get('reason', '')
                break

        return {
            'success': True,
            'best_tool': best_tool,
            'evidence': evidence_text,
            'results': results,
            'source': 'benchmark_knowledge'
        }

    def get_benchmark_evidence_for_tool(
        self,
        tool_name: str,
        task_id: str = None
    ) -> Optional[Dict[str, Any]]:
        """
        Get benchmark evidence for a specific tool.

        USE CASE: Show users why a tool was recommended.

        Args:
            tool_name: Tool name (benchmark name or Galaxy ID)
            task_id: Optional specific task

        Returns:
            Dict with benchmark evidence including citations
        """
        # First try as benchmark tool name
        evidence = self.benchmark_db.get_tool_evidence_for_galaxy_id(tool_name)
        if evidence:
            return evidence

        # Try direct performance lookup
        results = self.benchmark_db.get_tool_performance(tool_name)
        if results:
            best = min(results, key=lambda x: x.get('rank', 999))
            return {
                'tool_name': tool_name,
                'task': best['task_name'],
                'rank': best['rank'],
                'metric': best['metric'],
                'score': best['score'],
                'benchmark_paper': best['benchmark_paper'],
                'doi': best['doi'],
                'evidence_text': self.benchmark_db.generate_evidence_text(tool_name, task_id)
            }

        return None

    def get_benchmark_informed_tool_selection(
        self,
        task_description: str,
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Get tool recommendation based on benchmarks for workflow generation.

        USE CASE: Workflow generator selecting best tool for a step.

        Args:
            task_description: What the workflow step needs to do
            context: Optional context (data_size, compute constraints, etc.)

        Returns:
            Dict with:
            - recommended_tool: Best tool name
            - galaxy_tool_id: Galaxy tool ID (if mapping exists)
            - alternatives: Other good options
            - evidence: Why this tool is recommended
            - confidence: How confident the recommendation is

        Example:
            >>> ai.get_benchmark_informed_tool_selection(
            ...     "align RNA-seq reads to reference genome",
            ...     context={'memory_limited': True}
            ... )
            {'recommended_tool': 'HISAT2', 'galaxy_tool_id': 'hisat2', ...}
        """
        # Query benchmarks
        results = self.benchmark_db.query_semantic(task_description, top_k=3)

        if not results:
            return {
                'success': False,
                'message': 'No benchmark data for this task type'
            }

        # Check context for decision rules
        if context:
            # Check for memory constraints
            if context.get('memory_limited'):
                rules = self.benchmark_db.get_recommendation_for_condition('compute', 'limited_memory')
                if rules:
                    rule = rules[0]
                    tool_name = rule['recommended_tools'][0] if rule['recommended_tools'] else None
                    return {
                        'success': True,
                        'recommended_tool': tool_name,
                        'galaxy_tool_id': self.benchmark_db.get_galaxy_tool_id(tool_name) if tool_name else None,
                        'alternatives': rule['recommended_tools'][1:] if len(rule['recommended_tools']) > 1 else [],
                        'evidence': rule['reason'],
                        'confidence': 0.9,
                        'source': 'decision_rule'
                    }

            # Check for speed priority
            if context.get('speed_priority'):
                rules = self.benchmark_db.get_recommendation_for_condition('compute', 'speed_priority')
                if rules:
                    rule = rules[0]
                    tool_name = rule['recommended_tools'][0] if rule['recommended_tools'] else None
                    return {
                        'success': True,
                        'recommended_tool': tool_name,
                        'galaxy_tool_id': self.benchmark_db.get_galaxy_tool_id(tool_name) if tool_name else None,
                        'alternatives': rule['recommended_tools'][1:] if len(rule['recommended_tools']) > 1 else [],
                        'evidence': rule['reason'],
                        'confidence': 0.85,
                        'source': 'decision_rule'
                    }

        # Get best tool from task rankings
        for r in results:
            if r.get('type') == 'task' and r.get('rankings'):
                rankings = r['rankings']
                best = rankings[0] if rankings else None
                if best:
                    tool_name = best['tool_name']
                    return {
                        'success': True,
                        'recommended_tool': tool_name,
                        'galaxy_tool_id': self.benchmark_db.get_galaxy_tool_id(tool_name),
                        'alternatives': [r['tool_name'] for r in rankings[1:3]] if len(rankings) > 1 else [],
                        'evidence': self.benchmark_db.generate_evidence_text(tool_name, r.get('task_id')),
                        'confidence': r.get('similarity', 0.7),
                        'source': 'benchmark_ranking'
                    }

        return {
            'success': False,
            'message': 'Could not determine best tool from benchmarks'
        }

    def compare_tools_for_task(
        self,
        tool_a: str,
        tool_b: str,
        task_id: str = None
    ) -> Dict[str, Any]:
        """
        Compare two tools based on benchmark data.

        USE CASE: Help users decide between tools.

        Args:
            tool_a: First tool name
            tool_b: Second tool name
            task_id: Optional specific task

        Returns:
            Comparison with winner and evidence
        """
        comparison = self.benchmark_db.compare_tools(tool_a, tool_b, task_id)
        evidence = self.benchmark_db.generate_comparison_evidence(tool_a, tool_b, task_id)

        return {
            'tool_a': tool_a,
            'tool_b': tool_b,
            'winner': comparison['summary']['overall_winner'],
            'comparisons': comparison['comparisons'],
            'summary': comparison['summary'],
            'evidence_text': evidence
        }

    @property
    def agent_orchestrator(self):
        """Lazy-load AgentOrchestrator for multi-agent workflow generation with auditing."""
        if self._agent_orchestrator is None:
            from .agents import create_agent_orchestrator
            from .llm_client import LLMClient

            llm_client = LLMClient(self.config)

            # Use factory function which initializes all services
            self._agent_orchestrator = create_agent_orchestrator(
                llm_client=llm_client,
                config=self.config,
                enable_audit=True,
                enable_learning=True,
                use_enhanced_routing=True
            )
            log.info("AgentOrchestrator loaded on-demand with LLM routing, auditing, and learning")
        return self._agent_orchestrator

    def generate_workflow_multi_agent(
        self,
        user_intent: str,
        user_id: Optional[str] = None,
        user_context: Optional[Dict[str, Any]] = None,
        session_id: Optional[str] = None,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """
        Generate workflow using multi-agent system with LLM-enhanced routing.

        This is an alternative to generate_workflow_unified() that uses:
        1. EnhancedDomainRouter - Routes with hybrid keyword + LLM approach
        2. DomainSpecialists - Parallel domain-specific recommendations
        3. WorkflowAssembler - Synthesizes and validates workflow

        Features:
        - LLM-enhanced routing for ambiguous queries
        - User pattern personalization
        - Full audit trail for all generations
        - Learning from corrections and outcomes

        Args:
            user_intent: Natural language description of workflow goal
            user_id: Optional user ID for personalization
            user_context: Optional pre-loaded user context
            session_id: Optional session ID for audit tracking
            uploaded_datasets: Optional list of user-uploaded dataset IDs

        Returns:
            Dictionary containing:
            - success: bool
            - workflow_ga: Galaxy .ga JSON (if successful)
            - source: 'multi_agent'
            - confidence: float (0-1)
            - message: str
            - timing: Dict of timing info
            - domain_sources: List of domains consulted
            - request_id: str (for corrections/audit)
            - audit_id: int (for tracking)
            - routing_method: str ('keyword', 'llm', or 'hybrid')
        """
        log.info(f"[MultiAgentWorkflowGeneration] Starting for intent: {user_intent}")

        try:
            # Run multi-agent orchestration with auditing
            result = self.agent_orchestrator.generate_workflow(
                query=user_intent,
                user_id=user_id,
                user_context=user_context,
                session_id=session_id,
                parallel=True
            )

            if not result.success:
                return {
                    'success': False,
                    'error': result.error,
                    'source': 'multi_agent',
                    'timing': result.timing,
                    'request_id': result.request_id,
                    'audit_id': result.audit_id
                }

            workflow = result.workflow

            # Convert assembled workflow to Galaxy .ga format
            workflow_ga = self._build_workflow_ga_from_multi_agent(
                workflow,
                user_intent,
                uploaded_datasets
            )

            # Collect citations
            citations = [
                {
                    'tool_id': c.tool_id,
                    'tool_name': c.tool_name,
                    'doi': c.doi,
                    'pmid': c.pmid,
                    'title': c.title
                }
                for c in workflow.citations
            ]

            # Get routing method from result
            routing_method = getattr(result.routing, 'routing_method', 'keyword')

            return {
                'success': True,
                'workflow_ga': workflow_ga,
                'source': 'multi_agent',
                'confidence': workflow.confidence,
                'message': f"Generated workflow with {len(workflow.workflow_steps)} steps "
                          f"using domains: {', '.join(workflow.domain_sources)}",
                'timing': result.timing,
                'domain_sources': workflow.domain_sources,
                'citations': citations,
                'validation': {
                    'is_valid': workflow.validation.is_valid if workflow.validation else True,
                    'issues': workflow.validation.issues if workflow.validation else [],
                    'warnings': workflow.validation.warnings if workflow.validation else [],
                    'suggestions': workflow.validation.suggestions if workflow.validation else []
                },
                # Audit and learning fields
                'request_id': result.request_id,
                'audit_id': result.audit_id,
                'routing_method': routing_method
            }

        except Exception as e:
            log.error(f"[MultiAgentWorkflowGeneration] Failed: {e}", exc_info=True)
            return {
                'success': False,
                'error': str(e),
                'source': 'multi_agent'
            }

    def record_workflow_correction(
        self,
        request_id: str,
        user_id: str,
        correction_type: str,
        original_value: Any,
        corrected_value: Any,
        reason: str = None
    ) -> Dict[str, Any]:
        """
        Record a user correction for learning.

        Args:
            request_id: Request ID from generate_workflow_multi_agent
            user_id: User who made the correction
            correction_type: Type ('domain', 'tool_selection', 'parameters')
            original_value: Original suggested value
            corrected_value: User's corrected value
            reason: Optional reason for correction

        Returns:
            Dict with correction and learning results
        """
        return self.agent_orchestrator.record_correction(
            request_id=request_id,
            user_id=user_id,
            correction_type=correction_type,
            original_value=original_value,
            corrected_value=corrected_value,
            reason=reason
        )

    def record_workflow_outcome(
        self,
        request_id: str,
        user_id: str,
        success: bool,
        user_kept: bool = True,
        rating: int = None
    ) -> Dict[str, Any]:
        """
        Record workflow execution outcome for learning.

        Args:
            request_id: Request ID from generate_workflow_multi_agent
            user_id: User ID
            success: Whether workflow executed successfully
            user_kept: Whether user kept/used the workflow
            rating: User rating (1-5) if provided

        Returns:
            Dict with learning results
        """
        return self.agent_orchestrator.record_workflow_outcome(
            request_id=request_id,
            user_id=user_id,
            success=success,
            user_kept=user_kept,
            rating=rating
        )

    def get_workflow_audit_history(
        self,
        user_id: str,
        limit: int = 50
    ) -> List[Dict]:
        """
        Get user's workflow generation history.

        Args:
            user_id: User ID
            limit: Max records to return

        Returns:
            List of audit records
        """
        return self.agent_orchestrator.get_audit_history(user_id, limit)

    def get_workflow_audit_statistics(self, user_id: str = None) -> Dict[str, Any]:
        """
        Get workflow generation statistics.

        Args:
            user_id: Optional user ID to filter

        Returns:
            Audit statistics
        """
        return self.agent_orchestrator.get_audit_statistics(user_id)

    def _build_workflow_ga_from_multi_agent(
        self,
        workflow,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """Build Galaxy .ga workflow JSON from multi-agent assembled workflow."""
        steps = {}

        for i, step in enumerate(workflow.workflow_steps):
            tool_id = self._normalize_tool_id(step.tool_id)

            # Try to get tool parameters from tool attributes if available
            tool_params = getattr(step, 'parameters', None) or {}
            if isinstance(tool_params, str):
                import json
                try:
                    tool_params = json.loads(tool_params) if tool_params else {}
                except:
                    tool_params = {}

            # Get inputs from step if available
            step_inputs = getattr(step, 'inputs', None) or []
            if isinstance(step_inputs, str):
                import json
                try:
                    step_inputs = json.loads(step_inputs) if step_inputs else []
                except:
                    step_inputs = []

            steps[str(i)] = {
                "id": i,
                "type": "tool",
                "tool_id": tool_id,
                "name": step.tool_name,
                "annotation": step.description,
                "tool_state": tool_params,
                "inputs": step_inputs,
                "outputs": [],
                "position": {"left": 100 + i * 200, "top": 100}
            }

        workflow_ga = {
            "a_galaxy_workflow": "true",
            "format-version": "0.1",
            "name": f"Multi-Agent Workflow: {user_intent[:50]}",
            "annotation": f"Generated by multi-agent system. Domains: {', '.join(workflow.domain_sources)}",
            "tags": ["multi-agent", "ai-generated"] + workflow.domain_sources,
            "steps": steps
        }

        log.info(f"[_build_workflow_ga_from_multi_agent] Built workflow with {len(steps)} steps")
        return workflow_ga

    def process_request(self, user_request: UserRequest) -> AIResponse:
        """Process a complete user research request and generate AI response."""

        # Lazy load tool indexing only when process_request is called
        if not self._tools_indexed and self.galaxy_app:
            log.info("Lazy loading Galaxy tools for process_request...")
            self._index_galaxy_tools()
            self._tools_indexed = True

        request_id = str(uuid.uuid4())
        warnings = []

        try:
            # Step 1: Parse user intent
            parsed_intent = self.intent_parser.parse_request(user_request)
            
            # Step 2: Decompose into tasks
            tasks = self.task_decomposer.decompose_request(user_request, parsed_intent)
            
            # Step 3: Get tool recommendations for each task
            tool_recommendations = {}
            for task in tasks:
                recommendations = self.tool_recommender.recommend_tools(task)
                tool_recommendations[task.id] = recommendations
            
            # Step 4: Generate workflow template using enhanced generator
            try:
                # First get workflow recommendations
                workflow_recommendations = self.workflow_generator.get_workflow_recommendations(user_request)
                
                if workflow_recommendations:
                    warnings.append(f"Found {len(workflow_recommendations)} workflow options")
                    
                    # Generate actual workflow template from the best recommendation
                    best_recommendation = workflow_recommendations[0]
                    try:
                        workflow_result = self.workflow_generator.generate_workflow(user_request)
                        workflow_template = self._convert_workflow_result_to_template(workflow_result, user_request)
                        is_valid = True
                        execution_plan = f"Generated workflow: {workflow_template.name if workflow_template else 'Unknown'} (confidence: {workflow_result.get('confidence', 0):.0%})"
                    except Exception as gen_error:
                        warnings.append(f"Workflow generation failed: {str(gen_error)}")
                        workflow_template = None
                        is_valid = False
                        execution_plan = f"Found {len(workflow_recommendations)} workflow options but failed to generate template"
                else:
                    workflow_template = None
                    is_valid = False
                    execution_plan = None
                    warnings.append("No suitable workflow recommendations found")
                    
            except Exception as e:
                workflow_template = None
                is_valid = False
                execution_plan = None
                warnings.append(f"Error generating workflow: {str(e)}")
            
            # Calculate overall confidence
            task_confidences = [task.confidence for task in tasks if task.confidence > 0]
            tool_confidences = [
                rec.confidence for recs in tool_recommendations.values() 
                for rec in recs if rec.confidence > 0
            ]
            
            all_confidences = task_confidences + tool_confidences
            overall_confidence = sum(all_confidences) / len(all_confidences) if all_confidences else 0.0
            
            # Flatten tool recommendations for response
            all_recommendations = []
            for recs in tool_recommendations.values():
                all_recommendations.extend(recs)
            
            # Create AI response - add workflow_recommendations as custom field
            ai_response = AIResponse(
                request_id=request_id,
                parsed_intent=parsed_intent['intent'],
                decomposed_tasks=tasks,
                tool_recommendations=all_recommendations,
                workflow_template=workflow_template if is_valid else None,
                confidence=overall_confidence,
                execution_plan=execution_plan,
                warnings=warnings
            )
            
            # Add workflow recommendations as custom attribute
            if 'workflow_recommendations' in locals() and workflow_recommendations:
                ai_response.workflow_recommendations = workflow_recommendations
            else:
                ai_response.workflow_recommendations = []
            
            return ai_response
            
        except Exception as e:
            # Return error response
            return AIResponse(
                request_id=request_id,
                parsed_intent=IntentType.UNKNOWN,
                decomposed_tasks=[],
                tool_recommendations=[],
                workflow_template=None,
                confidence=0.0,
                execution_plan=None,
                warnings=[f"Error processing request: {str(e)}"]
            )
    
    def suggest_similar_workflows(self, user_request: UserRequest) -> List[WorkflowTemplate]:
        """Suggest similar existing workflows based on user request."""

        # Parse intent to understand what user wants
        parsed_intent = self.intent_parser.parse_request(user_request)

        # In a real implementation, this would query a workflow database
        # For now, return empty list
        return []

    def _validate_and_install_tools(self, workflow_ga: Dict) -> Dict[str, Any]:
        """
        Validate and install missing tools for a workflow.

        Args:
            workflow_ga: Galaxy workflow .ga JSON

        Returns:
            Dict with installation results:
            - success: bool
            - message: str
            - failed_tools: List[str]
        """
        if not hasattr(self, 'tool_installer') or self.tool_installer is None:
            try:
                from .tool_auto_installer import ToolAutoInstaller

                # Get Galaxy root from app config
                if self.galaxy_app and hasattr(self.galaxy_app, 'config'):
                    galaxy_root = str(getattr(self.galaxy_app.config, 'root', '/home/yzhang/biomate/backend'))
                    http_port = getattr(self.galaxy_app.config, 'http_port', 8081)
                    galaxy_api_url = f"http://localhost:{http_port}"

                    # Try to get API key from config
                    galaxy_api_key = getattr(self.galaxy_app.config, 'bootstrap_admin_api_key', None)
                    if not galaxy_api_key:
                        # Fallback to known key
                        galaxy_api_key = "a7e9f73a7c25300e222d27c84efb10f6"

                    log.info(f"Initializing ToolAutoInstaller for workflow validation (URL: {galaxy_api_url})")

                    self.tool_installer = ToolAutoInstaller(
                        galaxy_root=galaxy_root,
                        galaxy_api_url=galaxy_api_url,
                        galaxy_api_key=galaxy_api_key
                    )
                    log.info("Tool auto-installer initialized for workflow validation")
                else:
                    log.warning("Could not initialize tool installer: galaxy_app not available")
                    return {'success': False, 'message': 'Galaxy app not available', 'failed_tools': []}

            except Exception as e:
                log.error(f"Failed to initialize tool installer: {e}")
                return {'success': False, 'message': f'Installer init failed: {str(e)}', 'failed_tools': []}

        try:
            log.info("[ToolValidation] Validating and installing workflow tools...")
            success, msg, failed = self.tool_installer.auto_install_workflow_tools(workflow_ga)

            log.info(f"[ToolValidation] Result: success={success}, message={msg}, failed={len(failed)}")

            return {
                'success': success,
                'message': msg,
                'failed_tools': failed
            }
        except Exception as e:
            log.error(f"Tool installation error: {e}", exc_info=True)
            return {'success': False, 'message': f'Installation error: {str(e)}', 'failed_tools': []}

    @staticmethod
    def _infer_qc_profile(domain: str, tags: list, name: str) -> Optional[str]:
        """
        Infer the most specific named QC profile from workflow domain, tags, and name.

        Returns None for most workflows — the backend auto-detects from domain.
        Only returns a profile name when the workflow is a *specialised sub-type*
        that needs thresholds different from the generic domain defaults.
        """
        d = (domain or "").lower()
        n = (name or "").lower()
        t_str = " ".join(str(t).lower() for t in (tags or []))
        all_text = f"{d} {n} {t_str}"

        # --- Cryo-EM ---
        if "cryo_em" in d or "cryo-em" in d or "cryoem" in d:
            if any(k in all_text for k in ("phase_plate", "phase plate", "volta", "vpp")):
                return "cryoem_spa_phase_plate"
            if any(k in all_text for k in ("high_resolution", "high resolution", ">2a", ">2å")):
                return "cryoem_spa_high_resolution"
            return None  # auto-detect picks cryoem_spa_standard

        # --- Proteomics sub-types ---
        if "proteomics" in d or "proteomics" in all_text:
            if any(k in all_text for k in ("phospho", "phosphoproteomics")):
                return "proteomics_phospho"
            if any(k in all_text for k in ("plasma", "biomarker", "serum", "biomarker")):
                return "proteomics_plasma_biomarker"
            if any(k in all_text for k in ("pulldown", "chemoproteomics", "abpp", "enrichment")):
                return "proteomics_chemoproteomics"
            return None  # auto-detect picks proteomics_standard

        # --- Pharmacogenomics ---
        if any(k in all_text for k in ("pgx", "pharmacogenomics", "pharmacogenomic", "cpic")):
            if any(k in all_text for k in ("clinical", "patient", "tier 1", "tier1")):
                return "pgx_clinical"
            return "pgx_research"

        # --- Drug discovery & pharmacology compound sub-types (merged domain) ---
        if any(k in d for k in ("drug_discovery", "drug", "compound", "pharmacol", "admet", "pharmacokin")):
            if any(k in all_text for k in ("natural product", "natural_product", "fragment")):
                return "compound_natural_product"
            if any(k in all_text for k in ("peptidomimetic", "peptide mimetic")):
                return "compound_peptidomimetic"
            if any(k in all_text for k in ("druglike", "drug-like", "ro5", "lipinski", "hts")):
                return "compound_druglike"
            return None

        # --- RNA-seq specialisations ---
        if any(k in d for k in ("rnaseq", "rna_seq", "rna-seq", "transcriptomics")):
            if "encode4" in all_text or ("encode" in all_text and "atac" not in all_text):
                return "rnaseq_encode4"
            if any(k in all_text for k in ("low_input", "low input", "low-input")):
                return "rnaseq_low_input"
            if any(k in all_text for k in ("novel organism", "novel_organism", "non-model")):
                return "rnaseq_novel_organism"
            return None

        # --- Metagenomics sub-environments ---
        if "metagenom" in d:
            if any(k in all_text for k in ("clinical", "hospital", "infection")):
                return "metagenomics_clinical"
            if any(k in all_text for k in ("soil", "sediment", "rhizosphere")):
                return "metagenomics_soil"
            if any(k in all_text for k in ("marine", "ocean", "aquatic")):
                return "metagenomics_marine"
            return None

        # For everything else, let the backend auto-detect from workflow_domain
        return None

    def _is_executable_nextflow_match(self, match: Any) -> bool:
        """
        Return True only for directly runnable Nextflow workflows.

        We exclude nf-core subworkflows (library components) because they are not
        standalone entry workflows and fail with "No entry workflow specified".
        """
        if getattr(match, 'format', '') != 'nextflow':
            return False

        filename = (getattr(match, 'filename', '') or '').lower()
        name = (getattr(match, 'name', '') or '').lower()
        tags = [str(t).lower() for t in (getattr(match, 'tags', []) or [])]

        # Exclude known non-entry nf-core subworkflow library paths.
        if filename.startswith('nfcore/subworkflows/'):
            return False
        if '/nf-core-modules/subworkflows/' in filename:
            return False
        if '/nfcore/subworkflows/' in filename:
            return False
        if 'subworkflow' in name:
            return False
        if any('subworkflow' in t for t in tags):
            return False

        # Prefer canonical runnable entry scripts.
        if filename.endswith('/main.nf'):
            return True
        if filename.endswith('.nf') and ('/workflows/' in filename or 'biomni_nf/' in filename):
            return True
        return False

    def _nextflow_workflow_key(self, filename: str) -> Optional[str]:
        """
        Normalize path to "domain/workflow" key used by passed_workflows.txt.
        """
        path = (filename or "").strip().lower()
        if not path:
            return None

        # Pattern: biomni_nf/<domain>/<workflow>/main.nf
        if path.startswith("biomni_nf/"):
            parts = [p for p in path.split("/") if p]
            if len(parts) >= 3:
                return f"{parts[1]}/{parts[2]}"

        # Pattern: .../subworkflows/<domain>/<workflow>/main.nf
        marker = "/subworkflows/"
        if marker in path:
            tail = path.split(marker, 1)[1]
            parts = [p for p in tail.split("/") if p]
            if len(parts) >= 2:
                return f"{parts[0]}/{parts[1]}"

        return None

    def _load_runnable_nextflow_keys(self) -> set[str]:
        """
        Load pre-validated runnable workflow keys for complete tests.
        """
        backend_root = Path(__file__).resolve().parents[3]
        passed_file = backend_root / "biomni_workflows" / "nextflow_nfcore" / "test_results" / "passed_workflows.txt"
        if not passed_file.exists():
            return set()
        try:
            lines = [ln.strip().lower() for ln in passed_file.read_text(errors="replace").splitlines()]
            return {ln for ln in lines if ln and "/" in ln}
        except OSError:
            return set()

    def _is_runnable_nextflow_match(self, match: Any) -> bool:
        """
        Check if workflow is in pre-validated runnable set when available.
        """
        keys = self._load_runnable_nextflow_keys()
        if not keys:
            return True
        key = self._nextflow_workflow_key(getattr(match, "filename", "") or "")
        return bool(key and key in keys)

    def _pick_best_executable_nextflow_match(self, matches: List[Any]) -> Optional[Any]:
        """Pick highest-scoring executable Nextflow workflow, preferring runnable tested ones."""
        for match in matches or []:
            if self._is_executable_nextflow_match(match) and self._is_runnable_nextflow_match(match):
                return match
        for match in matches or []:
            if self._is_executable_nextflow_match(match):
                return match
        return None

    def _parse_memory_gb(self, value: Any) -> Optional[float]:
        """Parse memory declarations like '16GB' or numeric values into GB."""
        if value is None:
            return None
        if isinstance(value, (int, float)):
            try:
                return float(value)
            except (TypeError, ValueError):
                return None
        text = str(value).strip().lower()
        if not text:
            return None
        match = re.search(r"(\d+(?:\.\d+)?)", text)
        if not match:
            return None
        try:
            return float(match.group(1))
        except (TypeError, ValueError):
            return None

    def _collect_workflow_hardware_requirements(self, workflow_tools: List[str]) -> Optional[Dict[str, Any]]:
        """
        Aggregate hardware/runtime hints for workflow tools from galaxy_ai_tools.db.

        Returns a compact summary used by frontend/Nextflow execution gating.
        """
        tools = [str(t).strip() for t in (workflow_tools or []) if str(t).strip()]
        if not tools:
            return None

        db_path = Path(__file__).resolve().parents[3] / "database" / "galaxy_ai_tools.db"
        if not db_path.exists():
            return None

        gpu_required = False
        max_memory_gb = 0.0
        tool_runtime_hints: List[Dict[str, Any]] = []
        seen_tool_ids: set[str] = set()

        conn = None
        try:
            conn = sqlite3.connect(str(db_path))
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            for tool_ref in tools:
                candidates = [tool_ref]
                if "/" in tool_ref:
                    candidates.append(tool_ref.split("/")[-1])
                pattern = f"%{tool_ref}%"

                row = None
                for cand in candidates:
                    cursor.execute(
                        """
                        SELECT tool_id, name, execution_info
                        FROM tools
                        WHERE LOWER(tool_id) = LOWER(?)
                           OR LOWER(name) = LOWER(?)
                        LIMIT 1
                        """,
                        (cand, cand),
                    )
                    row = cursor.fetchone()
                    if row:
                        break

                if not row:
                    cursor.execute(
                        """
                        SELECT tool_id, name, execution_info
                        FROM tools
                        WHERE LOWER(tool_id) LIKE LOWER(?)
                           OR LOWER(name) LIKE LOWER(?)
                        ORDER BY CASE
                          WHEN LOWER(tool_id) LIKE LOWER(?) THEN 0
                          ELSE 1
                        END
                        LIMIT 1
                        """,
                        (pattern, pattern, pattern),
                    )
                    row = cursor.fetchone()

                if not row:
                    continue

                tool_id = str(row["tool_id"] or "").strip()
                if not tool_id or tool_id in seen_tool_ids:
                    continue
                seen_tool_ids.add(tool_id)

                raw_info = row["execution_info"]
                if not raw_info:
                    continue
                try:
                    exec_info = json.loads(raw_info) if isinstance(raw_info, str) else raw_info
                except Exception:
                    continue
                if not isinstance(exec_info, dict):
                    continue

                requires_gpu = bool(exec_info.get("gpu", False))
                memory_gb = self._parse_memory_gb(exec_info.get("memory"))
                if requires_gpu:
                    gpu_required = True
                if memory_gb is not None:
                    max_memory_gb = max(max_memory_gb, memory_gb)

                tool_runtime_hints.append(
                    {
                        "tool_id": tool_id,
                        "tool_name": row["name"] or tool_id,
                        "gpu": requires_gpu,
                        "memory_gb": memory_gb,
                        "container_image": exec_info.get("image"),
                        "runtime_type": exec_info.get("type"),
                    }
                )
        except Exception as exc:
            log.warning(f"[HardwareRequirements] Failed to read tool runtime hints: {exc}")
            return None
        finally:
            try:
                if conn is not None:
                    conn.close()
            except Exception:
                pass

        if not tool_runtime_hints:
            return None

        return {
            "gpu_required": gpu_required,
            "min_memory_gb": round(max_memory_gb, 2) if max_memory_gb > 0 else None,
            "tools_analyzed": len(tool_runtime_hints),
            "tool_runtime_hints": tool_runtime_hints[:12],
            "source": "ai_tool_db.execution_info",
        }

    def _build_intent_trials(self, user_intent: str, key_terms: Optional[List[str]] = None) -> List[str]:
        """
        Build search trials from user intent.

        Trial 1: original intent (always used).
        Trial 2: intent augmented with LLM-extracted key_terms — only added when
                 key_terms are present and meaningfully extend the original text.
                 This replaces the previous hardcoded domain-keyword enrichments.
        """
        trials: List[str] = [user_intent]
        if key_terms:
            extra = " ".join(t for t in key_terms if t.lower() not in user_intent.lower())
            if extra.strip():
                trials.append(f"{user_intent} {extra}")
        return trials

    # -------------------------------------------------------------------------
    # Nextflow parameter extraction helpers
    # -------------------------------------------------------------------------

    _NEXTFLOW_INTERNAL_PARAMS = {
        'mock_mode', 'outdir', 'sample_id', 'platform', 'library', 'genome',
        'max_cpus', 'max_memory', 'max_time', 'publish_dir_mode', 'monochrome_logs',
        'enable_conda', 'singularity_pull_docker_container', 'validationSkipDuplicateCheck',
        'tracedir', 'awsbatch', 'awsqueue', 'awsregion', 'input', 'output',
    }

    def _find_nf_file(self, filename: str) -> Optional[Any]:
        """Resolve DB-stored filename to absolute .nf path using same walk-up as executor."""
        from pathlib import Path as _Path
        this_file = _Path(__file__).resolve()
        backend_root = this_file.parent
        for ancestor in list(this_file.parents):
            if (ancestor / "biomni_workflows").is_dir():
                backend_root = ancestor
                break
        candidates = [
            backend_root / "biomni_workflows" / "nextflow_nfcore" / filename,
            backend_root / "biomni_workflows" / filename,
            backend_root / filename,
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    # Groups in nextflow_schema.json that are infrastructure / admin — skip them
    # so users only see scientifically relevant parameters.
    _SCHEMA_SKIP_GROUPS: frozenset = frozenset([
        'institutional config options',
        'generic options',
        'max job request options',
        'awsbatch job resources',
    ])

    # Parameter names that represent input data files — these get type="file" so the
    # frontend renders a dataset browser instead of a plain text box.
    _INPUT_FILE_PARAM_NAMES: frozenset = frozenset([
        'input', 'reads', 'reads1', 'reads2', 'fastq', 'fastq1', 'fastq2',
        'bam', 'genome', 'fasta', 'genome_fasta', 'reference', 'reference_genome',
        'gtf', 'gff', 'bed', 'vcf', 'csv', 'samplesheet', 'sample_sheet',
        'design', 'multiqc_config', 'star_index', 'hisat2_index', 'bwa_index',
        'bowtie2_index', 'transcript_fasta', 'additional_fasta', 'transcript',
        'probeset', 'annotation', 'blacklist', 'bait_intervals', 'target_intervals',
    ])

    def _detect_param_type(self, name: str, default_val: str) -> str:
        """Heuristic type detection for a single Nextflow parameter."""
        low = name.lower()
        if low in self._INPUT_FILE_PARAM_NAMES or low.endswith('_file') or low.endswith('_path'):
            return 'file'
        if default_val in ('true', 'false', 'True', 'False'):
            return 'boolean'
        if default_val and (
            default_val.startswith('/') or
            default_val.startswith('s3://') or
            default_val.startswith('gs://') or
            '.' in default_val.split('/')[-1]
        ):
            return 'file'
        try:
            int(default_val); return 'integer'
        except (ValueError, TypeError):
            pass
        try:
            float(default_val); return 'float'
        except (ValueError, TypeError):
            pass
        return 'string'

    def _parse_nextflow_params(self, filename: str) -> dict:
        """Parse params.* lines from .nf file. Returns {"required": [...], "optional": [...]}."""
        import re as _re
        nf_path = self._find_nf_file(filename)
        if not nf_path:
            return {"required": [], "optional": []}
        try:
            text = nf_path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            return {"required": [], "optional": []}
        required, optional = [], []
        for m in _re.finditer(r"^\s*params\.(\w+)\s*=\s*(.+)$", text, _re.MULTILINE):
            name = m.group(1)
            # Strip inline comment (// ...) from value
            raw = _re.sub(r'\s*//.*$', '', m.group(2)).strip()
            val_raw = raw
            if name in self._NEXTFLOW_INTERNAL_PARAMS:
                continue
            label = name.replace("_", " ").title()
            description = f"Workflow parameter: {label}"
            is_required = (val_raw == "null")
            default_str = None if is_required else val_raw.strip("'\"")
            param_type = self._detect_param_type(name, default_str or "")
            # Convert boolean string defaults to actual Python bools so the JSON
            # serialisation sends true/false (not the strings "true"/"false"),
            # enabling the frontend Switch component to work correctly.
            if param_type == 'boolean' and default_str in ('true', 'True'):
                default_str = True
            elif param_type == 'boolean' and default_str in ('false', 'False'):
                default_str = False
            entry = {
                "name": name,
                "label": label,
                "description": description,
                "type": param_type,
                "default": default_str,
            }
            if is_required:
                required.append(entry)
            else:
                optional.append(entry)
        return {"required": required, "optional": optional}

    def _schema_type_to_param_type(self, name: str, param_def: dict) -> str:
        """Map a JSON Schema property definition to BioMate's parameter type vocabulary."""
        if 'enum' in param_def:
            return 'select'
        fmt = param_def.get('format', '')
        if fmt == 'file-path' or param_def.get('mimetype'):
            return 'file'
        if fmt in ('directory-path', 'path'):
            # Output directories are plain strings — not browsable datasets
            return 'string'
        json_type = param_def.get('type', 'string')
        if json_type == 'boolean':
            return 'boolean'
        if json_type in ('integer', 'number'):
            return 'number'
        # Heuristic for unformatted strings that look like file inputs
        low = name.lower()
        if low in self._INPUT_FILE_PARAM_NAMES or low.endswith('_file') or low.endswith('_path'):
            return 'file'
        return 'string'

    def _parse_nextflow_schema(self, filename: str) -> Optional[dict]:
        """Parse nextflow_schema.json (nf-core JSON Schema) for authoritative parameter metadata.

        Returns {"required": [...], "optional": [...]} with richer fields than the .nf parser,
        or None when no schema file is found (custom workflows fall back to _parse_nextflow_params).

        Each entry includes: name, label, description, type, default, required, group,
        and optionally: options (select), minimum, maximum, pattern.
        """
        import json as _json
        nf_path = self._find_nf_file(filename)
        if not nf_path:
            return None
        schema_path = nf_path.parent / 'nextflow_schema.json'
        if not schema_path.exists():
            return None
        try:
            schema = _json.loads(schema_path.read_text(encoding='utf-8'))
        except Exception:
            return None

        defs = schema.get('$defs') or schema.get('definitions') or {}
        required_params = []
        optional_params = []

        for group_def in defs.values():
            if not isinstance(group_def, dict):
                continue
            group_title = group_def.get('title', '')
            if group_title.lower() in self._SCHEMA_SKIP_GROUPS:
                continue
            group_required = set(group_def.get('required', []))
            properties = group_def.get('properties', {})

            for param_name, param_def in properties.items():
                if not isinstance(param_def, dict):
                    continue
                if param_def.get('hidden', False):
                    continue

                ptype = self._schema_type_to_param_type(param_name, param_def)
                default = param_def.get('default', None)
                # JSON Schema booleans are already Python bools; strings need no conversion
                # since nf-core schemas emit native JSON true/false for boolean defaults.

                description = param_def.get('description', '') or ''
                help_text = param_def.get('help_text', '')
                # Keep description short for UI; put help_text in description if no description
                full_description = description or help_text

                entry: dict = {
                    'name': param_name,
                    'label': param_name.replace('_', ' ').title(),
                    'description': full_description,
                    'type': ptype,
                    'default': default,
                    'group': group_title,
                    'required': param_name in group_required,
                }

                if 'enum' in param_def:
                    entry['options'] = [{'label': str(v), 'value': v} for v in param_def['enum']]
                if 'minimum' in param_def:
                    entry['minimum'] = param_def['minimum']
                if 'maximum' in param_def:
                    entry['maximum'] = param_def['maximum']
                if 'pattern' in param_def:
                    entry['pattern'] = param_def['pattern']

                if param_name in group_required:
                    required_params.append(entry)
                else:
                    optional_params.append(entry)

        if not required_params and not optional_params:
            return None  # schema was empty or all groups skipped — fall back
        return {'required': required_params, 'optional': optional_params}

    def _get_workflow_params(self, filename: str) -> dict:
        """Get parameter metadata for a workflow.

        Tries nextflow_schema.json (nf-core) first for authoritative types, groups, enums,
        and min/max constraints. Falls back to parsing params.* from the .nf file when no
        schema is found (custom drug-discovery workflows).
        """
        schema_params = self._parse_nextflow_schema(filename)
        if schema_params is not None:
            return schema_params
        return self._parse_nextflow_params(filename)

    _SRA_ACCESSION_RE = re.compile(r'\b([SED]RR\d{6,9}|GSE\d{4,9}|GSM\d{4,9}|E-MTAB-\d{4,9}|PXD\d{4,9})\b', re.IGNORECASE)
    _GENOME_BUILD_RE = re.compile(
        r'\b(hg38|hg19|GRCh38|GRCh37|mm10|mm39|GRCm38|GRCm39|T2T-CHM13|dm6|ce11|danRer11|sacCer3)\b',
        re.IGNORECASE,
    )
    # igenomes-style system defaults for common reference genome builds.
    # Pre-filled when user mentions a genome build — unblocks the Run button
    # without requiring the user to supply full S3/local paths.  The executor
    # resolves these via the igenomes config or fails gracefully in mock mode.
    _IGENOMES_REFERENCE: dict = {
        'hg38':   's3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg38/Sequence/WholeGenomeFasta/genome.fa',
        'grch38': 's3://ngi-igenomes/igenomes/Homo_sapiens/Ensembl/GRCh38/Sequence/WholeGenomeFasta/genome.fa',
        'hg19':   's3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg19/Sequence/WholeGenomeFasta/genome.fa',
        'grch37': 's3://ngi-igenomes/igenomes/Homo_sapiens/Ensembl/GRCh37/Sequence/WholeGenomeFasta/genome.fa',
        'mm10':   's3://ngi-igenomes/igenomes/Mus_musculus/UCSC/mm10/Sequence/WholeGenomeFasta/genome.fa',
        'mm39':   's3://ngi-igenomes/igenomes/Mus_musculus/Ensembl/GRCm39/Sequence/WholeGenomeFasta/genome.fa',
    }
    _IGENOMES_KNOWN_SITES: dict = {
        'hg38':   's3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg38/Annotation/GATKBundle/dbsnp_146.hg38.vcf.gz',
        'grch38': 's3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg38/Annotation/GATKBundle/dbsnp_146.hg38.vcf.gz',
        'hg19':   's3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg19/Annotation/GATKBundle/dbsnp_138.hg19.vcf.gz',
        'grch37': 's3://ngi-igenomes/igenomes/Homo_sapiens/UCSC/hg19/Annotation/GATKBundle/dbsnp_138.hg19.vcf.gz',
        'mm10':   's3://ngi-igenomes/igenomes/Mus_musculus/UCSC/mm10/Annotation/GATKBundle/mgp_v3_snps_rsIDdbSNPv137.vcf.gz',
    }

    def _extract_sra_accession(self, user_intent: str) -> Optional[str]:
        """Return the first SRA/GEO/ArrayExpress/PRIDE accession found in the user's message."""
        m = self._SRA_ACCESSION_RE.search(user_intent)
        return m.group(1).upper() if m else None

    def _extract_genome_build(self, user_intent: str) -> Optional[str]:
        """Return the first recognised genome build mentioned in the user's message, normalised to lowercase."""
        m = self._GENOME_BUILD_RE.search(user_intent)
        if not m:
            return None
        raw = m.group(1)
        # Normalise aliases: GRCh38→hg38, GRCh37→hg19, GRCm38→mm10, GRCm39→mm39
        alias_map = {'grch38': 'hg38', 'grch37': 'hg19', 'grcm38': 'mm10', 'grcm39': 'mm39'}
        return alias_map.get(raw.lower(), raw.lower())

    def _inject_sra_into_params(self, req_params: list, opt_params: list, accession: str) -> tuple:
        """If user provided an SRA accession, set it as the default for the 'reads' required param.
        Keeps 'reads' in required_params (correct semantics) but pre-fills default so the Run
        button is not blocked — the viewer's hasUnfilledRequired check uses p.value which
        is initialized from p.default.  The param is flagged with sra_accession=True so the
        UI can show a badge 'pre-filled from your query'.
        Returns (new_req_params, new_opt_params) with the accession injected."""
        new_req = []
        for p in req_params:
            if p['name'] in ('reads', 'input', 'fastq', 'sample', 'reads1', 'reads2'):
                # Keep in required but pre-fill default from the user-supplied accession
                new_req.append({**p, 'default': accession, 'sra_accession': True})
            else:
                new_req.append(p)
        return new_req, list(opt_params)

    _MAX_SPOTS_RE = re.compile(r'\bmax_spots\s*[=:]\s*(\d+)', re.IGNORECASE)

    def _extract_max_spots(self, user_intent: str) -> Optional[int]:
        """Return max_spots value if user explicitly specified it (e.g. 'max_spots=500000')."""
        m = self._MAX_SPOTS_RE.search(user_intent)
        return int(m.group(1)) if m else None

    def _inject_max_spots_into_params(self, opt_params: list, max_spots: int) -> list:
        """Set max_spots in optional params (add it if not present)."""
        for p in opt_params:
            if p['name'] == 'max_spots':
                return [{**p, 'default': max_spots} if p['name'] == 'max_spots' else p
                        for p in opt_params]
        # Not in opt_params yet — append it
        return list(opt_params) + [{
            'name': 'max_spots', 'default': max_spots, 'required': False,
            'description': 'Limit SRA spots downloaded (0 = unlimited)',
        }]

    def _inject_genome_into_params(self, req_params: list, opt_params: list, genome_build: str) -> tuple:
        """Pre-fill reference, known_sites, and genome params when user mentioned a genome build.
        Uses igenomes-compatible S3 paths so the Run button is not blocked by empty required fields.
        The executor resolves the paths; in mock/dev mode the workflow fails gracefully."""
        _REFERENCE_NAMES = frozenset(['reference', 'genome_fasta', 'fasta', 'reference_fasta',
                                      'ref_genome', 'reference_genome', 'ref', 'genome_file'])
        _KNOWN_SITES_NAMES = frozenset(['known_sites', 'known_variants', 'dbsnp', 'known_indels',
                                        'known_vcf', 'bqsr_known_sites', 'mills', 'dbsnp_vcf'])
        _GENOME_NAMES = frozenset(['genome', 'genome_build', 'genome_id', 'assembly'])

        ref_path = self._IGENOMES_REFERENCE.get(genome_build)
        ks_path = self._IGENOMES_KNOWN_SITES.get(genome_build)

        def _patch(p: dict) -> dict:
            n = p['name']
            if n in _REFERENCE_NAMES and not p.get('default') and ref_path:
                return {**p, 'default': ref_path, 'genome_auto': True}
            if n in _KNOWN_SITES_NAMES and not p.get('default') and ks_path:
                return {**p, 'default': ks_path, 'genome_auto': True}
            if n in _GENOME_NAMES and not p.get('default'):
                return {**p, 'default': genome_build, 'genome_auto': True}
            return p

        return [_patch(p) for p in req_params], [_patch(p) for p in opt_params]

    def _build_prereq_validation(self, required_params: list) -> Optional[dict]:
        """Build prerequisitesValidation payload consumed by prereq-normalizer.ts.
        Excludes params that have a pre-filled default (e.g. SRR accession injected) from
        missingParameters — those are provided by the user and do not block the Run button."""
        # Only params without a pre-filled default are truly missing
        truly_missing = [p for p in required_params if not p.get('default')]
        if not truly_missing:
            return None
        return {
            "requirements": {
                "parameters": [
                    {"stepId": "workflow", "paramName": p["name"], "optional": False, "defaultValue": None}
                    for p in truly_missing
                ]
            },
            "analysis": {
                "missingInputs": [],
                "missingParameters": [{"stepId": "workflow", "paramName": p["name"]} for p in truly_missing],
                "inputMappings": [],
            },
        }

    # ------------------------------------------------------------------
    # Parameter pre-filling — layer 2 AI knowledge
    # ------------------------------------------------------------------

    def _apply_parameter_hints(
        self,
        req: list,
        opt: list,
        hints: list,
    ) -> tuple:
        """Merge tool_knowledge parameter_hints into the param lists.

        Matches hints by param name (exact or lowercase comparison).
        Sets autoFilled=True and adds rationale to matched params so the
        frontend KnowledgeBadge and editability indicators are shown.
        Returns (new_req, new_opt).
        """
        if not hints:
            return req, opt

        hint_map: dict = {}
        for h in hints:
            pname = h.get("param", "")
            if pname:
                hint_map[pname.lower()] = h

        def _apply_hints_to_list(params: list) -> list:
            out = []
            for p in params:
                key = p.get("name", "").lower()
                h = hint_map.get(key)
                if h and h.get("recommended"):
                    p = dict(p)
                    p["autoFilled"] = True
                    p["rationale"] = h.get("rationale", "")
                    # Only override value when no default already exists
                    if not p.get("default"):
                        p["default"] = h["recommended"]
                out.append(p)
            return out

        return _apply_hints_to_list(req), _apply_hints_to_list(opt)

    _PARAM_SUGGEST_SYSTEM = """You are a scientific parameter advisor for a bioinformatics platform.

Given a workflow name, a list of its configurable parameters (with type and description), and a user's natural-language query, suggest pre-filled values for parameters that can be inferred from the user's context.

Rules:
- ONLY suggest values for parameters where the user's query makes the value unambiguous.
- For select parameters, the value MUST be one of the listed enum values.
- For boolean parameters, value must be true or false (unquoted).
- Do NOT guess file paths — never suggest a value for file-type parameters.
- Do NOT repeat the workflow's existing default value unless the user explicitly confirms it.
- Limit to at most 5 suggestions. Prefer scientifically impactful parameters.
- Return JSON array of objects: [{"name": "param_name", "value": <value>, "rationale": "one-sentence why"}]
- Return [] if nothing can be confidently inferred.

Examples of good inference:
- User says "37°C" → temperature = 310 (Kelvin conversion, with rationale)
- User says "XP precision" or "lead optimisation docking" → docking_precision = "XP"
- User says "scaffold decoration of coumarin" → mode = "scaffold_decoration", seed_smiles = "c1ccc2c(c1)ccc(=O)o2"
- User says "de novo design" → mode = "de_novo"
- User says "SARS-CoV-2 Mpro" → reactive_residue = "CYS:145" for covalent docking
- User says "oral drug" → route = "oral"
- User says "GPU available" or "use GPU" → gpu = true"""

    def _infer_params_from_intent_llm(
        self,
        user_intent: str,
        workflow_name: str,
        req: list,
        opt: list,
    ) -> list:
        """Use Haiku to suggest parameter pre-fills from the user's natural language query.

        Returns a list of {name, value, rationale} dicts for matched params.
        Silently returns [] on any failure (non-blocking).
        """
        import os as _os
        import json as _json

        api_key = _os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return []

        try:
            import anthropic as _anthropic
            client = _anthropic.Anthropic(api_key=api_key)
        except Exception:
            return []

        # Build a compact param catalogue for the prompt
        all_params = req + opt
        # Skip file params — LLM should not fill paths
        inferable = [p for p in all_params if p.get("type") not in ("file",)]
        if not inferable:
            return []

        param_lines = []
        for p in inferable:
            name = p["name"]
            ptype = p.get("type", "string")
            desc = p.get("description", "")[:120]
            enum_vals = [str(o["value"]) for o in p.get("options", [])] if p.get("options") else None
            if enum_vals:
                param_lines.append(f'- {name} (select: {"|".join(enum_vals)}): {desc}')
            else:
                param_lines.append(f'- {name} ({ptype}): {desc}')

        params_text = "\n".join(param_lines)
        user_msg = (
            f"Workflow: {workflow_name}\n\n"
            f"Available parameters:\n{params_text}\n\n"
            f"User query: {user_intent[:400]}"
        )

        try:
            response = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=512,
                system=self._PARAM_SUGGEST_SYSTEM,
                messages=[{"role": "user", "content": user_msg}],
            )
            text = response.content[0].text.strip()
            # Extract JSON array from response
            start = text.find("[")
            end = text.rfind("]") + 1
            if start < 0 or end <= start:
                return []
            suggestions = _json.loads(text[start:end])
            if not isinstance(suggestions, list):
                return []
            # Validate: name must exist in inferable params, value must not be empty
            valid_names = {p["name"] for p in inferable}
            return [
                s for s in suggestions
                if isinstance(s, dict)
                and s.get("name") in valid_names
                and s.get("value") is not None
                and str(s.get("value", "")).strip() != ""
            ]
        except Exception as exc:
            log.debug("[ParamSuggest] LLM inference failed: %s", exc)
            return []

    def _apply_llm_suggestions(
        self,
        req: list,
        opt: list,
        suggestions: list,
    ) -> tuple:
        """Merge LLM intent-inferred suggestions into param lists.

        If the suggestion is for a required param, moves it to having a pre-filled
        default so the Run button is not blocked. Sets autoFilled=True + rationale.
        """
        if not suggestions:
            return req, opt

        sugg_map = {s["name"]: s for s in suggestions if s.get("name")}

        def _apply(params: list) -> list:
            out = []
            for p in params:
                s = sugg_map.get(p.get("name", ""))
                if s:
                    p = dict(p)
                    p["autoFilled"] = True
                    p["rationale"] = s.get("rationale", "AI-recommended based on your query.")
                    # Pre-fill default so the Run button is not blocked for required params
                    if p.get("default") is None:
                        p["default"] = s["value"]
                    # Also set as the working value
                    p["value"] = s["value"]
                out.append(p)
            return out

        return _apply(req), _apply(opt)

    # ------------------------------------------------------------------
    # LangGraph pipeline — observability wrapper around generate_workflow_unified
    # ------------------------------------------------------------------

    def _get_or_build_pipeline(self):
        """Build (or return cached) the BioMate LangGraph CompiledStateGraph.

        The graph wraps ``generate_workflow_unified`` in a single node so that:
        - LangSmith traces every generation call automatically (when key is set).
        - MemorySaver checkpoints the result keyed by ``session_id``, enabling
          state recovery if the backend restarts mid-generation on a long job.

        Returns None and logs a warning if the import fails.
        """
        if self._langgraph_pipeline is not None:
            return self._langgraph_pipeline
        try:
            from .langgraph_pipeline import build_biomate_pipeline
            self._langgraph_pipeline = build_biomate_pipeline(ai_assistant=self)
            log.info("[AIAssistant] LangGraph pipeline built and cached")
        except Exception as exc:
            log.warning("[AIAssistant] Could not build LangGraph pipeline: %s", exc)
            self._langgraph_pipeline = None
        return self._langgraph_pipeline

    def run_via_pipeline(
        self,
        user_intent: str,
        session_id: str,
        user_id: Optional[str] = None,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """Invoke ``generate_workflow_unified`` through the LangGraph StateGraph.

        Falls back to ``generate_workflow_unified`` directly if the pipeline
        cannot be built or if invocation fails.

        The pipeline:
        1. ``classify_intent`` — intent type + clarification flag
        2. ``check_clarification`` — routes to clarify or continue
        3. ``search_workflows`` — populates ``workflow_candidates`` in state
        4. ``generate_workflow`` — calls ``generate_workflow_unified()``
        5. ``dispatch_execution`` — records execution_run_id (stub)

        ``final_response`` in the terminal state is the full result dict
        from ``generate_workflow_unified``, unchanged.
        """
        import os
        pipeline = self._get_or_build_pipeline()
        if pipeline is None:
            log.warning("[run_via_pipeline] pipeline unavailable, falling back")
            return self.generate_workflow_unified(user_intent, uploaded_datasets, user_id)

        initial_state = {
            "query": user_intent,
            "session_id": session_id,
            "user_id": user_id or "",
            "intent": None,
            "confidence": None,
            "clarification_needed": False,
            "workflow_candidates": [],
            "selected_workflow": None,
            "parameters": None,
            "execution_run_id": None,
            "autofix_attempts": 0,
            "error": None,
            "final_response": None,
        }
        config = {"configurable": {"thread_id": session_id}}
        try:
            terminal_state = pipeline.invoke(initial_state, config=config)
            result = terminal_state.get("final_response")
            if result and isinstance(result, dict):
                log.info("[run_via_pipeline] pipeline completed, source=%s", result.get("source"))
                return result
            # Clarification requested — return a structured response the
            # endpoint can handle (success=False, message carries the question).
            if terminal_state.get("clarification_needed"):
                return {
                    "success": False,
                    "message": (
                        terminal_state.get("final_response", {}).get("message")
                        or "Please clarify your request."
                    ),
                    "source": "clarification",
                }
            log.warning("[run_via_pipeline] terminal state has no final_response, falling back")
            return self.generate_workflow_unified(user_intent, uploaded_datasets, user_id)
        except Exception as exc:
            log.warning("[run_via_pipeline] pipeline invocation failed: %s — falling back", exc)
            return self.generate_workflow_unified(user_intent, uploaded_datasets, user_id)

    def _return_nextflow_match(
        self,
        match: Any,
        score: float,
        user_intent: str,
        source: str,
        needs_user_feedback: bool,
        search_results: List[Any],
        selected_trial: str,
        trials: List[str],
    ) -> Dict[str, Any]:
        """Shared return path for high- and medium-confidence Nextflow template matches."""
        scientific_rationale = self._build_scientific_rationale(
            match.filename, match.name, workflow_tools=match.tools
        )
        hardware_requirements = self._collect_workflow_hardware_requirements(match.tools)
        qc_profile = self._infer_qc_profile(match.domain, match.tags, match.name)
        nf_params = self._get_workflow_params(match.filename)
        req = nf_params['required']
        opt = nf_params['optional']
        sra = self._extract_sra_accession(user_intent)
        if sra:
            req, opt = self._inject_sra_into_params(req, opt, sra)
        genome = self._extract_genome_build(user_intent)
        if genome:
            req, opt = self._inject_genome_into_params(req, opt, genome)
        max_spots = self._extract_max_spots(user_intent)
        if max_spots:
            opt = self._inject_max_spots_into_params(opt, max_spots)
        # Layer 2: apply DB-driven tool_knowledge hints
        hints = (scientific_rationale or {}).get('parameter_hints', [])
        req, opt = self._apply_parameter_hints(req, opt, hints)
        # Layer 2: apply LLM intent-inferred suggestions (non-blocking)
        llm_suggestions = self._infer_params_from_intent_llm(user_intent, match.name, req, opt)
        req, opt = self._apply_llm_suggestions(req, opt, llm_suggestions)
        warnings = [] if not needs_user_feedback else [
            'Medium confidence match — please verify tool selection is appropriate'
        ]
        return {
            'success': True,
            'nextflow_path': match.filename,
            'workflow_name': match.name,
            'workflow_type': 'nextflow',
            'source': source,
            'confidence': int(score),
            'template_match_score': int(score),
            'needs_user_feedback': needs_user_feedback,
            **(({'feedback_prompt': (
                f"I found a workflow that partially matches your request: '{match.name}'. "
                f"Please confirm it meets your needs or provide corrections."
            )}) if needs_user_feedback else {}),
            'message': f"{'Found' if not needs_user_feedback else 'Best available'} workflow: {match.name}",
            'note': f'Found workflow with {match.step_count} step(s)',
            'execution_engine': 'nextflow',
            'format': 'nextflow',
            'hardware_requirements': hardware_requirements,
            **({'qc_profile': qc_profile} if qc_profile else {}),
            'scientific_rationale': scientific_rationale,
            'workflow_ga': {
                'name': match.name,
                'description': match.description,
                'annotation': match.description,
                'tags': match.tags,
                'format': 'nextflow',
                'nextflow_path': match.filename,
                'workflow_type': 'nextflow',
                'steps': {},
                'scientific_rationale': scientific_rationale,
                'hardware_requirements': hardware_requirements,
                'required_params': req,
                'optional_params': opt,
            },
            'datasets_assigned': False,
            'required_params': req,
            'optional_params': opt,
            'generated_parameters': req + opt,
            **({'prerequisitesValidation': self._build_prereq_validation(req)} if req else {}),
            'validation': {'is_valid': True, 'issues': [], 'warnings': warnings, 'suggestions': []},
            'tool_installation': {'success': True, 'message': 'Nextflow workflow', 'failed_tools': []},
            'selected_trial': selected_trial,
            'trial_count': len(trials),
            'candidate_workflows': [
                {'name': m.name, 'domain': m.domain, 'source': m.source, 'score': m.score, 'format': m.format}
                for m in (search_results or [])[:3]
            ],
        }

    def generate_workflow_unified(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
        user_id: Optional[str] = None,
        key_terms: Optional[List[str]] = None,
        preferred_domains: Optional[List[str]] = None,
        penalized_domains: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Unified workflow generation with search-first approach.

        This implements the complete architecture from UNIFIED_ARCHITECTURE_SUMMARY.md:
        1. Search existing workflows (UnifiedWorkflowSearch with 951+ indexed workflows)
        2. If high confidence (>0.8): Reuse workflow + update datasets
        3. If medium confidence (0.5-0.8): Use EnhancedWorkflowGenerator (adapt template)
        4. If low confidence (<0.5): Use GalaxyWorkflowGenerator (tool-constrained from scratch)
        5. Always assign datasets via WorkflowDatasetSelector

        Args:
            user_intent: Natural language description of workflow goal
            uploaded_datasets: Optional list of user-uploaded dataset IDs
            user_id: Optional user ID for LTM correction injection

        Returns:
            Dictionary containing:
            - success: bool
            - workflow_ga: Galaxy .ga JSON (if successful)
            - source: 'template_reuse' | 'template_adapt' | 'tool_constrained'
            - confidence: float (0-1)
            - message: str
            - datasets_assigned: bool
        """
        log.info(f"[UnifiedWorkflowGeneration] Starting for intent: {user_intent}")

        # C1b — Inject recent user corrections into the intent for personalized search/generation
        if MEMORY_AVAILABLE and self.agentic_memory and user_id:
            try:
                corrections = self.agentic_memory.get_recent_corrections(user_id, limit=5)
                if corrections:
                    correction_text = "This user previously corrected:\n" + "\n".join(
                        f"- Suggested: {c['original_suggestion']} → User chose: {c['user_correction']}"
                        for c in corrections
                    )
                    user_intent = f"{user_intent}\n\n[Memory context] {correction_text}"
                    log.info(
                        "[UnifiedWorkflowGeneration] Injected %d correction(s) from LTM for user %s",
                        len(corrections),
                        user_id,
                    )
            except Exception as _ltm_err:
                log.warning("[UnifiedWorkflowGeneration] LTM correction fetch failed: %s", _ltm_err)

        try:
            # Initialise variables that may be set only in specific code paths
            # so the final return dict can always reference them safely.
            dataset_match_result: Dict[str, Any] = {}

            # Step 0: Chain lookup — preferred path for multi-step research projects.
            # The search uses embedding similarity (threshold 0.42) + LLM scope check.
            # If the LLM is uncertain it sets clarification_needed and returns a question.
            try:
                chain_results = self.workflow_search.search_chains(user_intent, min_score=0.35, limit=3)
                if chain_results:
                    top_chain = chain_results[0]
                    # LLM requested clarification — surface the question; do NOT launch chain.
                    if getattr(top_chain, 'clarification_needed', False):
                        q = top_chain.clarification_question or (
                            f"To select the right pipeline, could you clarify: "
                            f"are you looking for the full {top_chain.display_name} workflow "
                            f"({len(top_chain.steps)} steps), or a simpler single-step analysis?"
                        )
                        log.info("[UnifiedWorkflowGeneration] Chain clarification needed: %s", q)
                        return {
                            'success': False,
                            'workflow_type': 'clarification',
                            'source': 'chain_lookup',
                            'confidence': 5,
                            'message': q,
                            'clarification_question': q,
                            'candidate_chain': top_chain.name,
                        }
                    log.info("[UnifiedWorkflowGeneration] Chain match: %s (%d steps)", top_chain.name, len(top_chain.steps))
                    return {
                        'success': True,
                        'workflow_type': 'chain',
                        'chain_name': top_chain.name,
                        'chain_display_name': top_chain.display_name,
                        'chain_domain': top_chain.domain,
                        'chain_description': top_chain.description,
                        'chain_steps': top_chain.steps,
                        'chain_connections': top_chain.connections,
                        'required_inputs': top_chain.required_inputs,
                        'expected_outputs': top_chain.expected_outputs,
                        'source': 'chain_lookup',
                        'confidence': 9,
                        'message': f"Found curated pipeline: **{top_chain.display_name}** ({len(top_chain.steps)} steps). {top_chain.description}",
                        'note': f"Pre-validated {len(top_chain.steps)}-step pipeline with explicit data-flow connections.",
                        'execution_engine': 'chain',
                        'format': 'chain',
                        'all_chains': [c.to_dict() for c in chain_results],
                    }
            except Exception as chain_exc:
                log.warning("[UnifiedWorkflowGeneration] Chain lookup failed: %s", chain_exc)

            # Step 1: Iterative search trials until confidence is high.
            log.info("[UnifiedWorkflowGeneration] Step 1: Searching workflows iteratively...")
            trials = self._build_intent_trials(user_intent, key_terms=key_terms)
            selected_trial = user_intent
            search_results: List[Any] = []
            best_match = None
            score = 0.0
            match_type = "no_match"
            executable_nextflow_match = None

            for trial in trials:
                trial_results = self.workflow_search.search(
                    trial, limit=5, include_workflow_json=True,
                    preferred_domains=preferred_domains or None,
                    penalized_domains=penalized_domains or None,
                    key_terms=key_terms or None,
                )
                if not trial_results:
                    continue
                trial_best = trial_results[0]
                if best_match is None or trial_best.score > score:
                    selected_trial = trial
                    search_results = trial_results
                    best_match = trial_best
                    score = trial_best.score
                    match_type = trial_best.match_type
                    executable_nextflow_match = self._pick_best_executable_nextflow_match(trial_results)
                if trial_best.match_type == "high_confidence":
                    selected_trial = trial
                    search_results = trial_results
                    best_match = trial_best
                    score = trial_best.score
                    match_type = trial_best.match_type
                    executable_nextflow_match = self._pick_best_executable_nextflow_match(trial_results)
                    break

            if not search_results:
                log.info("[UnifiedWorkflowGeneration] No workflows found after iterative trials, will generate from scratch")
                score = 0.0
                match_type = "no_match"
            else:
                log.info(
                    f"[UnifiedWorkflowGeneration] Selected trial='{selected_trial}' | "
                    f"best={best_match.name if best_match else 'N/A'} (score={score:.2f}, match={match_type})"
                )

            workflow_ga = None
            source = None
            datasets_assigned = False
            generated_parameters = []  # Initialize for all paths

            # Step 2: Decide strategy based on template match confidence
            # match_type is set by UnifiedWorkflowSearch._classify_match():
            #   high_confidence  : score >= 12.0  → reuse workflow as-is
            #   medium_confidence: score >= 6.0   → adapt template or compose via NextflowComposer
            #   low_confidence / no_match         → compose from scratch via NextflowComposer
            if match_type == "high_confidence":
                # High confidence - reuse existing workflow
                log.info("[UnifiedWorkflowGeneration] High confidence match - reusing workflow")
                best_match = search_results[0]
                source = 'template_reuse'

                # Check if this is a Nextflow workflow
                if best_match.format == 'nextflow':
                    if not self._is_executable_nextflow_match(best_match):
                        if executable_nextflow_match:
                            log.warning(
                                "[UnifiedWorkflowGeneration] Top Nextflow match is non-executable "
                                f"subworkflow ({best_match.filename}); using executable candidate "
                                f"{executable_nextflow_match.filename}"
                            )
                            best_match = executable_nextflow_match
                            score = best_match.score
                        else:
                            log.warning(
                                "[UnifiedWorkflowGeneration] No executable Nextflow workflow found in top results; "
                                "falling back to best non-Nextflow template match if available"
                            )
                            fallback_match = next(
                                (m for m in search_results if getattr(m, 'format', '') != 'nextflow'),
                                None
                            )
                            if fallback_match:
                                best_match = fallback_match
                                score = best_match.score
                                log.warning(
                                    "[UnifiedWorkflowGeneration] Using fallback template match: "
                                    f"{best_match.name} ({best_match.format})"
                                )

                if match_type == "high_confidence" and best_match and best_match.format == 'nextflow':
                    log.info(f"[UnifiedWorkflowGeneration] High-confidence Nextflow match: {best_match.filename}")
                    return self._return_nextflow_match(
                        match=best_match, score=score, user_intent=user_intent,
                        source='template_reuse', needs_user_feedback=False,
                        search_results=search_results, selected_trial=selected_trial, trials=trials,
                    )

                # Parse workflow JSON if available (Galaxy format)
                workflow_json = {}
                if best_match.workflow_json:
                    try:
                        workflow_json = json.loads(best_match.workflow_json) if isinstance(best_match.workflow_json, str) else best_match.workflow_json
                    except:
                        workflow_json = {}

                # Extract workflow steps from Galaxy .ga format
                workflow_steps = []
                if 'steps' in workflow_json:
                    for step_id, step_data in workflow_json['steps'].items():
                        if step_data.get('tool_id'):
                            workflow_steps.append({
                                'step': int(step_id),
                                'tool_id': step_data.get('tool_id'),
                                'name': step_data.get('name', ''),
                                'description': step_data.get('annotation', '')
                            })

                # WorkflowDatasetSelector is ready but requires actual Galaxy history dataset
                # IDs (from getHistoryDatasets), not BioMNI catalog IDs which is what
                # uploaded_datasets currently contains. Wire this when the history dataset
                # source is connected to this call path.
                dataset_match_result: Dict[str, Any] = {}

                # Build Galaxy .ga JSON (dataset connections established at execution time)
                workflow_ga = self._build_workflow_ga_from_template(workflow_json, {})
                datasets_assigned = False

                message = f"Reused existing workflow: {best_match.name}"

            elif match_type == "medium_confidence":
                # Medium confidence — best_match exists (score 6–11).
                # If the match is already a Nextflow workflow, return it directly
                # (same code path as high_confidence, but flagged for user review).
                # Only fall back to the legacy Galaxy generator for galaxy_ga matches.
                log.info("[UnifiedWorkflowGeneration] Medium confidence match")
                source = 'template_adapt'

                nf_formats = {'nextflow', 'bioconductor_nf'}
                if best_match and getattr(best_match, 'format', '') in nf_formats:
                    log.info(f"[UnifiedWorkflowGeneration] Medium-confidence Nextflow match: {best_match.filename}")
                    return self._return_nextflow_match(
                        match=best_match, score=score, user_intent=user_intent,
                        source='template_adapt', needs_user_feedback=True,
                        search_results=search_results, selected_trial=selected_trial, trials=trials,
                    )

                # Galaxy .ga format medium-confidence match — compose Nextflow via NextflowComposer
                # using best_match as a structural reference (same path as low-confidence but with
                # a reference guide, ensuring Nextflow output instead of Galaxy .ga).
                log.info(
                    "[UnifiedWorkflowGeneration] Medium confidence Galaxy match — "
                    "composing Nextflow workflow with template as structural reference"
                )
                source = 'nextflow_composed'
                composed = self.nextflow_composer.compose_workflow(
                    user_intent=user_intent,
                    reference_match=best_match,
                    max_tools=25,
                    key_terms=key_terms,
                )
                if composed['success']:
                    cache_note = " (cache hit)" if composed.get("cache_hit") else ""
                    log.info(
                        f"[UnifiedWorkflowGeneration] Composed Nextflow{cache_note}: "
                        f"{composed['composable_count']} NF-WRAPPER + {composed['adhoc_count']} generated"
                    )
                    validation = composed.get('validation', {})
                    _nf_params_mc = self._get_workflow_params(composed['nextflow_path'])
                    _req_mc = _nf_params_mc['required']
                    _opt_mc = _nf_params_mc['optional']
                    _sra_mc = self._extract_sra_accession(user_intent)
                    if _sra_mc:
                        _req_mc, _opt_mc = self._inject_sra_into_params(_req_mc, _opt_mc, _sra_mc)
                    _genome_mc = self._extract_genome_build(user_intent)
                    if _genome_mc:
                        _req_mc, _opt_mc = self._inject_genome_into_params(_req_mc, _opt_mc, _genome_mc)
                    return {
                        'success': True,
                        'nextflow_path': composed['nextflow_path'],
                        'workflow_name': composed['workflow_name'],
                        'workflow_type': 'nextflow',
                        'source': composed['source'],
                        'cache_hit': composed.get('cache_hit', False),
                        'confidence': int(score),
                        'template_match_score': int(score),
                        'needs_user_feedback': True,
                        'feedback_prompt': (
                            f"I used a Galaxy reference template ('{best_match.name}', score {int(score)}/12) "
                            "as a structural guide and composed a Nextflow workflow. "
                            "Please review the tool selection before running."
                        ),
                        'message': composed['message'],
                        'workflow_ga': {
                            'name': composed['workflow_name'],
                            'description': user_intent,
                            'format': 'nextflow',
                            'nextflow_path': composed['nextflow_path'],
                            'workflow_type': 'nextflow',
                            'steps': {},
                            'required_params': _req_mc,
                            'optional_params': _opt_mc,
                        },
                        'datasets_assigned': False,
                        'required_params': _req_mc,
                        'optional_params': _opt_mc,
                        'generated_parameters': _req_mc + _opt_mc,
                        **({'prerequisitesValidation': self._build_prereq_validation(_req_mc)} if _req_mc else {}),
                        'validation': {
                            'is_valid': validation.get('is_valid', True),
                            'warnings': validation.get('warnings', []),
                            'issues': validation.get('issues', []),
                            'suggestions': validation.get('suggestions', []),
                        },
                        'tool_installation': {'success': True, 'message': 'Nextflow workflow', 'failed_tools': []},
                        'selected_trial': selected_trial,
                        'trial_count': len(trials),
                        'candidate_workflows': [
                            {'name': m.name, 'domain': m.domain, 'source': m.source,
                             'score': m.score, 'format': m.format}
                            for m in (search_results or [])[:3]
                        ],
                    }
                else:
                    raise Exception(f"NextflowComposer failed on medium-confidence Galaxy match: {composed.get('error')}")

            else:
                # Low confidence / no match — compose a Nextflow workflow from tool search.
                # Uses NextflowComposer which:
                #   1. Searches the full tools table (12 k+ entries: Galaxy ToolShed,
                #      nf-core modules, Bioconductor, BioMate data lake)
                #   2. Enriches each tool with best_practice_functions, wrapper_path,
                #      scientific_context — so the LLM understands step sequences
                #   3. Emits include{} directives for the 3 k+ tools with existing .nf
                #      wrappers and generates minimal process blocks for the rest
                #   4. Writes a runnable DSL2 main.nf to nextflow_generated/ and
                #      returns its path for Nextflow execution
                log.info("[UnifiedWorkflowGeneration] Low/no confidence — composing Nextflow workflow from tools")
                source = 'nextflow_composed'

                composed = self.nextflow_composer.compose_workflow(
                    user_intent=user_intent,
                    reference_match=best_match,   # may be None for no_match
                    max_tools=30,
                    key_terms=key_terms,
                )

                if composed['success']:
                    log.info(
                        f"[UnifiedWorkflowGeneration] Nextflow composed: "
                        f"{composed['composable_count']} include{{}} + "
                        f"{composed['adhoc_count']} generated processes"
                    )
                    validation = composed.get('validation', {})
                    _nf_params_lc = self._get_workflow_params(composed['nextflow_path'])
                    _req_lc = _nf_params_lc['required']
                    _opt_lc = _nf_params_lc['optional']
                    _sra_lc = self._extract_sra_accession(user_intent)
                    if _sra_lc:
                        _req_lc, _opt_lc = self._inject_sra_into_params(_req_lc, _opt_lc, _sra_lc)
                    _genome_lc = self._extract_genome_build(user_intent)
                    if _genome_lc:
                        _req_lc, _opt_lc = self._inject_genome_into_params(_req_lc, _opt_lc, _genome_lc)
                    return {
                        'success': True,
                        'nextflow_path': composed['nextflow_path'],
                        'workflow_name': composed['workflow_name'],
                        'workflow_type': 'nextflow',
                        'source': 'nextflow_composed',
                        'confidence': int(score) if score > 0 else 2,
                        'template_match_score': int(score) if score > 0 else 0,
                        'needs_user_feedback': True,
                        'feedback_prompt': (
                            "I composed a Nextflow workflow by searching the tool library and "
                            "chaining relevant tools. Please review the tool selection and "
                            "step order before running."
                        ),
                        'message': composed['message'],
                        'note': (
                            f"Composed from {composed['composable_count']} existing .nf modules "
                            f"+ {composed['adhoc_count']} generated process blocks"
                        ),
                        'execution_engine': 'nextflow',
                        'format': 'nextflow',
                        'workflow_ga': {
                            'name': composed['workflow_name'],
                            'description': f"Composed Nextflow workflow for: {user_intent}",
                            'format': 'nextflow',
                            'nextflow_path': composed['nextflow_path'],
                            'workflow_type': 'nextflow',
                            'steps': {},
                            'tools_used': composed['tools_used'],
                            'required_params': _req_lc,
                            'optional_params': _opt_lc,
                        },
                        'datasets_assigned': False,
                        'required_params': _req_lc,
                        'optional_params': _opt_lc,
                        'generated_parameters': _req_lc + _opt_lc,
                        **({'prerequisitesValidation': self._build_prereq_validation(_req_lc)} if _req_lc else {}),
                        'tools_used': composed['tools_used'],
                        # Nextflow validation: checks include{} paths resolve on disk.
                        # Tool availability is handled by container images, not installation.
                        'validation': validation,
                        'tool_installation': {
                            'success': True,
                            'message': 'Nextflow workflow — tools provided via container images',
                            'failed_tools': [],
                        },
                        'selected_trial': selected_trial,
                        'trial_count': len(trials),
                        'candidate_workflows': [
                            {'name': m.name, 'domain': m.domain, 'source': m.source,
                             'score': m.score, 'format': m.format}
                            for m in (search_results or [])[:3]
                        ],
                    }
                else:
                    raise Exception(
                        f"[UnifiedWorkflowGeneration] NextflowComposer failed: {composed.get('error', 'unknown error')}"
                    )

            # Step 3: Galaxy ToolShed tool validation (Galaxy .ga fallback path only)
            # NOTE: All Nextflow paths (high/medium confidence NF, nextflow_composed)
            # return EARLY before this point. This step is intentionally Galaxy-only:
            # it checks whether Galaxy ToolShed tools are installed in the local Galaxy
            # instance. Nextflow tool availability is handled by container images.
            log.info("[UnifiedWorkflowGeneration] Step 3: Galaxy tool validation (fallback path only)...")
            tool_install_result = self._validate_and_install_tools(workflow_ga)

            if not tool_install_result['success']:
                log.warning(f"[UnifiedWorkflowGeneration] Galaxy tool validation had issues: {tool_install_result['message']}")
            else:
                log.info(f"[UnifiedWorkflowGeneration] Galaxy tool validation successful: {tool_install_result['message']}")

            # Return success response
            needs_user_feedback = match_type != "high_confidence"
            candidate_workflows = [
                {
                    'name': m.name,
                    'domain': m.domain,
                    'source': m.source,
                    'score': m.score,
                    'format': m.format,
                }
                for m in (search_results or [])[:3]
            ]

            return {
                'success': True,
                'workflow_ga': workflow_ga,
                'source': source,
                'confidence': score if score > 0 else 0.3,  # Default low confidence for scratch generation
                'message': message,
                'datasets_assigned': datasets_assigned,
                'dataset_match_result': dataset_match_result,
                'template_match_score': score,
                'generated_parameters': generated_parameters,  # Include LLM-generated parameters with confidence scores
                'tool_installation': tool_install_result,  # Include tool installation results
                'execution_engine': 'galaxy' if source == 'template_reuse' else 'nextflow',  # Explicit execution engine
                'workflow_tags': workflow_ga.get('tags', []),  # Workflow tags for frontend detection
                'needs_user_feedback': needs_user_feedback,
                'feedback_prompt': (
                    "I found a best-available workflow, but confidence is not high enough. "
                    "Please confirm the domain/tool fit or provide corrections before execution."
                    if needs_user_feedback else None
                ),
                'selected_trial': selected_trial,
                'trial_count': len(trials),
                'candidate_workflows': candidate_workflows,
            }

        except Exception as e:
            log.error(f"[UnifiedWorkflowGeneration] Error: {str(e)}", exc_info=True)
            return {
                'success': False,
                'error': str(e),
                'message': f"Workflow generation failed: {str(e)}"
            }

    def _build_workflow_ga_from_template(self, template: Dict, dataset_assignments: Dict) -> Dict:
        """
        Build Galaxy .ga workflow JSON from template with dataset assignments.

        Args:
            template: Workflow JSON dictionary from UnifiedWorkflowSearch
            dataset_assignments: Dataset assignments from WorkflowDatasetSelector

        Returns:
            Galaxy .ga workflow JSON
        """
        # Extract template structure
        workflow_name = template.get('name', 'Generated Workflow')
        workflow_desc = template.get('description', '') or template.get('annotation', '')

        # Galaxy .ga format uses 'steps' key (dict), not 'workflow_steps' (list)
        # Handle both formats for compatibility
        raw_steps = template.get('steps', {})
        if isinstance(raw_steps, dict):
            # Galaxy .ga format: {'0': {...}, '1': {...}, ...}
            workflow_steps = [
                {**step_data, 'step_id': step_id}
                for step_id, step_data in sorted(raw_steps.items(), key=lambda x: int(x[0]))
                if step_data.get('tool_id')  # Skip input steps without tool_id
            ]
        else:
            # Legacy list format
            workflow_steps = raw_steps if raw_steps else template.get('workflow_steps', [])

        # Build .ga format
        ga_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': workflow_desc,
            'format-version': '0.1',
            'name': workflow_name,
            'tags': template.get('tags', []) + ['galaxy-reuse', 'ai-generated'],
            'steps': {}
        }

        # Convert template steps to Galaxy .ga format
        for i, step in enumerate(workflow_steps):
            step_id = str(i)
            # Normalize tool ID from AI database format (slashes) to Galaxy format (underscores)
            tool_id = self._normalize_tool_id(step.get('tool_id', 'unknown'))

            # Preserve existing tool_state if available from template, otherwise use empty dict
            existing_tool_state = step.get('tool_state', {})
            if isinstance(existing_tool_state, str):
                # Parse string JSON to dict
                import json
                try:
                    existing_tool_state = json.loads(existing_tool_state) if existing_tool_state else {}
                except:
                    existing_tool_state = {}

            ga_workflow['steps'][step_id] = {
                'id': i,
                'tool_id': tool_id,
                'type': step.get('type', 'tool'),
                'name': step.get('name', ''),
                'annotation': step.get('annotation', '') or step.get('description', ''),
                'tool_state': existing_tool_state,
                'inputs': step.get('inputs', []),
                'outputs': step.get('outputs', []),
                'position': step.get('position', {'left': 100 + i * 200, 'top': 100})
            }

            # Add dataset assignments for this step
            step_datasets = self._get_datasets_for_step(i, dataset_assignments)
            if step_datasets:
                ga_workflow['steps'][step_id]['inputs'].extend(step_datasets)

        log.info(f"[_build_workflow_ga_from_template] Built workflow with {len(ga_workflow['steps'])} steps")
        return ga_workflow

    def _build_workflow_ga_from_generated(self, workflow_data: Dict, dataset_assignments: Dict) -> Dict:
        """
        Build Galaxy .ga workflow JSON from enhanced generator output with dataset assignments.
        """
        # Similar to _build_workflow_ga_from_template
        # This is a simplified version - real implementation would be more complex
        workflow_name = workflow_data.get('name', 'Generated Workflow')
        workflow_desc = workflow_data.get('description', '')
        steps = workflow_data.get('steps', [])

        ga_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': workflow_desc,
            'format-version': '0.1',
            'name': workflow_name,
            'tags': workflow_data.get('tags', []) + ['nextflow', 'ai-generated'],
            'steps': {}
        }

        for i, step in enumerate(steps):
            step_id = str(i)
            ga_workflow['steps'][step_id] = step

            # Add dataset assignments
            step_datasets = self._get_datasets_for_step(i, dataset_assignments)
            if step_datasets:
                if 'inputs' not in ga_workflow['steps'][step_id]:
                    ga_workflow['steps'][step_id]['inputs'] = []
                ga_workflow['steps'][step_id]['inputs'].extend(step_datasets)

        return ga_workflow

    def _get_datasets_for_step(self, step_index: int, dataset_assignments: Dict) -> List[Dict]:
        """Extract dataset assignments for a specific step."""
        datasets = []
        workflow_steps = dataset_assignments.get('workflow_steps', [])

        for step_data in workflow_steps:
            if step_data.get('step') == step_index + 1:  # Steps are 1-indexed in assignments
                for dataset_info in step_data.get('datasets', []):
                    datasets.append({
                        'name': dataset_info.get('name', 'reference_db'),
                        'src': 'ldda',
                        'path': dataset_info.get('path', '')
                    })

        return datasets

    def explain_workflow(self, workflow_template: WorkflowTemplate) -> str:
        """Generate a human-readable explanation of a workflow."""
        
        explanation_parts = [
            f"Workflow: {workflow_template.name}",
            f"Description: {workflow_template.description}",
            "",
            "Steps:"
        ]
        
        for i, step in enumerate(workflow_template.steps, 1):
            tool_name = step.tool_id.replace('_', ' ').title()
            annotation = step.annotation or f"Execute {tool_name}"
            explanation_parts.append(f"{i}. {annotation}")
        
        explanation_parts.extend([
            "",
            f"Estimated runtime: {self._estimate_workflow_runtime(workflow_template)} minutes",
            f"Required inputs: {len(workflow_template.inputs)}",
            f"Expected outputs: {len(workflow_template.outputs)}"
        ])
        
        return "\n".join(explanation_parts)
    
    def get_tool_alternatives(self, tool_id: str, task_context: Optional[Task] = None) -> List[ToolRecommendation]:
        """Get alternative tools for a specific tool."""
        
        if task_context:
            # Use task context to find similar tools
            return self.tool_recommender.recommend_tools(task_context)
        else:
            # Find tools with similar functionality
            # This would query the tool discovery system
            return []
    
    def estimate_workflow_cost(self, workflow_template: WorkflowTemplate) -> Dict[str, Any]:
        """Estimate computational cost for workflow execution."""
        
        optimizer = WorkflowOptimizer(self.config)
        parallel_groups = optimizer._identify_parallel_groups(
            optimizer._build_dependency_graph(workflow_template.steps)
        )
        
        total_runtime = optimizer._estimate_total_runtime(workflow_template.steps, parallel_groups)
        peak_resources = optimizer._estimate_peak_resources(workflow_template.steps, parallel_groups)
        
        # Simple cost calculation (in a real system, this would use actual pricing)
        compute_cost = peak_resources.cores * total_runtime * 0.01  # $0.01 per core-minute
        storage_cost = peak_resources.disk_gb * 0.001  # $0.001 per GB
        
        return {
            'estimated_runtime_minutes': total_runtime,
            'peak_cores': peak_resources.cores,
            'peak_memory_gb': peak_resources.memory_gb,
            'peak_disk_gb': peak_resources.disk_gb,
            'estimated_compute_cost_usd': round(compute_cost, 2),
            'estimated_storage_cost_usd': round(storage_cost, 2),
            'total_estimated_cost_usd': round(compute_cost + storage_cost, 2)
        }
    
    def optimize_for_resources(
        self,
        workflow_template: WorkflowTemplate,
        max_cores: Optional[int] = None,
        max_memory_gb: Optional[float] = None
    ) -> WorkflowTemplate:
        """Optimize workflow to fit within resource constraints."""
        
        # Use resource-optimized strategy
        optimization_result = self.workflow_optimizer.optimize_workflow(
            workflow_template, OptimizationStrategy.MINIMIZE_RESOURCES
        )
        
        # Create new workflow template with optimized steps
        optimized_workflow = WorkflowTemplate(
            name=f"{workflow_template.name} (Resource Optimized)",
            description=f"{workflow_template.description}\n\nOptimized for resource efficiency.",
            steps=optimization_result.optimized_steps,
            inputs=workflow_template.inputs,
            outputs=workflow_template.outputs,
            tags=workflow_template.tags + ['resource-optimized'],
            created_at=datetime.now()
        )
        
        return optimized_workflow
    
    def _build_scientific_rationale(
        self,
        workflow_filename: str,
        workflow_name: str,
        workflow_tools: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Build a scientific rationale block for a matched Nextflow workflow.

        For each tool in workflow_tools (the workflow's tools_used list), looks up
        tool_knowledge in the BioMate DB.  Only includes tools that have actual
        use_cases recorded — this naturally filters out tools with no KB coverage
        (aligners not yet enriched, biomni custom processes, etc.).

        Returns a dict with:
          - tools_used: canonical tool names found in tool_knowledge with use_cases
          - when_to_use: up to 3 use-case strings
          - do_not_use_when: up to 3 limitation strings
          - data_requirements: data_requirements dict from scientific_context
          - key_assumptions: up to 2 assumption strings
          - common_pitfalls: up to 2 {error, cause, fix} dicts
          - parameter_hints: up to 8 {param, recommended, rationale, tool} dicts
        """
        try:
            provider = ToolKnowledgeProvider()
            db_path = provider.db_path
        except Exception as e:
            log.warning(f"[ScientificRationale] Could not init ToolKnowledgeProvider: {e}")
            return {}

        import sqlite3 as _sqlite3

        # For each tool the workflow declares, look it up in tool_knowledge.
        # Only accept results that have actual use_cases — this filters out tools
        # with no meaningful KB coverage (e.g. custom biomni processes).
        seen_lower: set = set()
        core_tools: List[str] = []

        for raw_name in (workflow_tools or []):
            knowledge = provider.get_tool_knowledge(raw_name)
            if (knowledge
                    and knowledge.use_cases
                    and knowledge.tool_name.lower() not in seen_lower):
                core_tools.append(knowledge.tool_name)
                seen_lower.add(knowledge.tool_name.lower())

        if not core_tools:
            return {}

        rationale: Dict[str, Any] = {
            "tools_used": [],
            "when_to_use": [],
            "do_not_use_when": [],
            "data_requirements": {},
            "key_assumptions": [],
            "common_pitfalls": [],
            "parameter_hints": [],
        }

        for tool_name in core_tools:
            # ── tool_knowledge table ──────────────────────────────────────
            knowledge = provider.get_tool_knowledge(tool_name)
            if knowledge:
                rationale["tools_used"].append(knowledge.tool_name)

                for uc in (knowledge.use_cases or [])[:3]:
                    if uc not in rationale["when_to_use"]:
                        rationale["when_to_use"].append(uc)

                for lim in (knowledge.limitations or [])[:3]:
                    if lim not in rationale["do_not_use_when"]:
                        rationale["do_not_use_when"].append(lim)

                for param_name, rec in list((knowledge.recommended_parameters or {}).items())[:6]:
                    # Extract scalar value — recommended_value may be a dict like
                    # {'default': 'MPNN'} when stored from Nextflow param definitions.
                    rv = rec.recommended_value
                    if isinstance(rv, dict):
                        rv = rv.get("default", rv.get("value", next(iter(rv.values()), "")))
                    recommended_str = str(rv) if rv is not None else ""
                    hint = {
                        "param": param_name,
                        "recommended": recommended_str,
                        "rationale": rec.description or "",
                        "tool": tool_name,
                    }
                    rationale["parameter_hints"].append(hint)

            # ── tools.scientific_context ──────────────────────────────────
            try:
                conn = _sqlite3.connect(db_path)
                row = conn.execute(
                    "SELECT scientific_context FROM tools WHERE lower(name)=? LIMIT 1",
                    (tool_name.lower(),)
                ).fetchone()
                conn.close()

                if row and row[0]:
                    sc = json.loads(row[0]) if isinstance(row[0], str) else row[0]

                    # data_requirements — take first non-empty one
                    if not rationale["data_requirements"]:
                        dr = sc.get("data_requirements") or {}
                        if dr:
                            rationale["data_requirements"] = dr

                    # scientific_assumptions — up to 2
                    for item in (sc.get("scientific_assumptions") or []):
                        text = item.get("assumption", item) if isinstance(item, dict) else str(item)
                        if text and text not in rationale["key_assumptions"]:
                            rationale["key_assumptions"].append(text)
                        if len(rationale["key_assumptions"]) >= 2:
                            break

                    # common_errors — up to 2
                    for item in (sc.get("common_errors") or []):
                        if isinstance(item, dict) and item.get("error"):
                            entry = {
                                "error": str(item.get("error", ""))[:120],
                                "cause": str(item.get("cause", ""))[:120],
                                "fix":   str(item.get("fix",   ""))[:120],
                            }
                            rationale["common_pitfalls"].append(entry)
                        if len(rationale["common_pitfalls"]) >= 2:
                            break

            except Exception as e:
                log.debug(f"[ScientificRationale] scientific_context lookup failed for {tool_name}: {e}")

        # Trim lists to keep the response lean
        rationale["when_to_use"]     = rationale["when_to_use"][:3]
        rationale["do_not_use_when"] = rationale["do_not_use_when"][:3]
        rationale["key_assumptions"] = rationale["key_assumptions"][:2]
        rationale["common_pitfalls"] = rationale["common_pitfalls"][:2]
        rationale["parameter_hints"] = rationale["parameter_hints"][:8]

        # Final sanitization — ensure ALL string fields are plain scalars, never dicts.
        # This prevents raw Python dict representations leaking into the UI.
        def _to_scalar(v: object) -> str:
            if isinstance(v, dict):
                return v.get("default", v.get("value", str(next(iter(v.values()), ""))))  # type: ignore[arg-type]
            return str(v) if v is not None else ""

        rationale["when_to_use"]     = [_to_scalar(x) for x in rationale["when_to_use"]]
        rationale["do_not_use_when"] = [_to_scalar(x) for x in rationale["do_not_use_when"]]
        rationale["key_assumptions"] = [_to_scalar(x) for x in rationale["key_assumptions"]]
        for hint in rationale["parameter_hints"]:
            hint["param"]       = _to_scalar(hint.get("param", ""))
            hint["recommended"] = _to_scalar(hint.get("recommended", ""))
            hint["rationale"]   = _to_scalar(hint.get("rationale", ""))
        for pitfall in rationale["common_pitfalls"]:
            for field in ("error", "cause", "fix"):
                pitfall[field] = _to_scalar(pitfall.get(field, ""))

        return rationale

    def _index_galaxy_tools(self):
        """Index available Galaxy tools for discovery."""
        
        if not self.galaxy_app:
            return
        
        try:
            # Get tools from Galaxy toolbox
            toolbox = getattr(self.galaxy_app, 'toolbox', None)
            if not toolbox:
                return
            
            for tool_id, tool in toolbox.tools():
                # Convert Galaxy tool to our Tool format
                galaxy_tool = self._convert_galaxy_tool(tool)
                if galaxy_tool:
                    self.tool_indexer.index_tool(galaxy_tool)
                    
        except Exception as e:
            print(f"Error indexing Galaxy tools: {e}")
    
    def _convert_galaxy_tool(self, galaxy_tool) -> Optional[Tool]:
        """Convert a Galaxy tool to our Tool format."""
        
        try:
            # Extract tool information
            tool_id = galaxy_tool.id
            name = galaxy_tool.name or tool_id
            version = getattr(galaxy_tool, 'version', 'unknown')
            description = getattr(galaxy_tool, 'description', '')
            
            # Extract inputs and outputs
            inputs = []
            outputs = []
            
            # This would need to be adapted based on Galaxy's actual tool structure
            # For now, create minimal tool representation
            
            return Tool(
                id=tool_id,
                name=name,
                version=version,
                description=description,
                inputs=inputs,
                outputs=outputs,
                requirements=[],
                edam_operations=[],
                edam_topics=[],
                citations=[]
            )
            
        except Exception as e:
            print(f"Error converting Galaxy tool {galaxy_tool.id}: {e}")
            return None
    
    def _create_execution_plan(self, optimization_result) -> str:
        """Create a human-readable execution plan."""
        
        plan_parts = [
            "Workflow Execution Plan:",
            f"- Total steps: {len(optimization_result.optimized_steps)}",
            f"- Parallel groups: {len(optimization_result.parallel_groups)}",
            f"- Estimated runtime: {optimization_result.estimated_total_runtime} minutes",
            f"- Peak resources: {optimization_result.estimated_peak_resources.cores} cores, "
            f"{optimization_result.estimated_peak_resources.memory_gb}GB memory",
            "",
            "Execution sequence:"
        ]
        
        for i, group in enumerate(optimization_result.parallel_groups, 1):
            if len(group) == 1:
                step_id = group[0]
                step = next(s for s in optimization_result.optimized_steps if s.step_id == step_id)
                plan_parts.append(f"{i}. Execute {step.tool_id}")
            else:
                plan_parts.append(f"{i}. Execute in parallel:")
                for step_id in group:
                    step = next(s for s in optimization_result.optimized_steps if s.step_id == step_id)
                    plan_parts.append(f"   - {step.tool_id}")
        
        if optimization_result.optimization_notes:
            plan_parts.extend(["", "Optimization notes:"])
            for note in optimization_result.optimization_notes:
                plan_parts.append(f"- {note}")
        
        return "\n".join(plan_parts)
    
    def _estimate_workflow_runtime(self, workflow_template: WorkflowTemplate) -> int:
        """Estimate total workflow runtime."""
        
        optimizer = WorkflowOptimizer(self.config)
        parallel_groups = optimizer._identify_parallel_groups(
            optimizer._build_dependency_graph(workflow_template.steps)
        )
        
        return optimizer._estimate_total_runtime(workflow_template.steps, parallel_groups)
    
    def _convert_workflow_result_to_template(self, workflow_result: Dict[str, Any], user_request: UserRequest) -> Optional[WorkflowTemplate]:
        """Convert workflow generation result to WorkflowTemplate object."""
        
        try:
            workflow_data = workflow_result.get('workflow', {})
            
            if not workflow_data:
                return None
            
            # Create WorkflowTemplate from the generated workflow
            
            # Convert steps if they exist
            steps = []
            if 'steps' in workflow_data:
                for step_data in workflow_data['steps']:
                    if isinstance(step_data, dict):
                        # Handle both old and new step formats
                        step_id = step_data.get('id', step_data.get('step_number', len(steps) + 1))
                        # Normalize tool ID from AI database format (slashes) to Galaxy format (underscores)
                        tool_id = self._normalize_tool_id(step_data.get('tool_id', 'unknown'))

                        step = WorkflowStep(
                            step_id=step_id,
                            tool_id=tool_id,
                            tool_version=step_data.get('tool_version', 'latest'),
                            input_connections=step_data.get('input_connections', {}),
                            parameters=step_data.get('parameters', {}),
                            annotation=step_data.get('annotation', step_data.get('description', f'Step {step_id}')),
                            position=step_data.get('position', {'left': 200 + len(steps) * 300, 'top': 200})
                        )
                        steps.append(step)
            
            workflow_template = WorkflowTemplate(
                name=workflow_data.get('name', f'Generated Workflow for {user_request.request_text[:50]}'),
                description=workflow_data.get('description', f'AI-generated workflow for: {user_request.request_text}'),
                steps=steps,
                inputs=workflow_data.get('inputs', []),
                outputs=workflow_data.get('outputs', []),
                tags=workflow_data.get('tags', ['ai-generated']),
                created_at=datetime.now()
            )
            
            return workflow_template
            
        except Exception as e:
            print(f"Error converting workflow result to template: {e}")
            return None
    
    def get_status(self) -> Dict[str, Any]:
        """Get AI assistant status and statistics."""
        
        return {
            'config': self.config.to_dict(),
            'components': {
                'intent_parser': 'ready',
                'task_decomposer': 'ready',
                'tool_recommender': 'ready',
                'workflow_generator': 'ready',
                'workflow_optimizer': 'ready',
                'tool_discovery': 'ready'
            },
            'cache_stats': {
                'tools_cached': len(self._tool_cache),
                'workflows_cached': len(self._workflow_cache)
            },
            'ready': True
        }