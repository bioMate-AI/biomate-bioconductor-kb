"""
Galaxy AI Assistant

Main orchestrator that combines all AI components to provide intelligent research assistance.
"""

import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime

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



class AIAssistant:
    """Main Galaxy AI Assistant that orchestrates the entire AI pipeline."""
    
    def __init__(self, config: Optional[AIConfig] = None, galaxy_app=None):
        self.config = config or DEFAULT_AI_CONFIG
        self.config.validate()

        self.galaxy_app = galaxy_app

        # ONLY initialize components needed for generate_workflow_unified()
        self.workflow_search = get_workflow_search()  # UnifiedWorkflowSearch with 951+ workflows
        self._tool_search = None  # Lazy-loaded UnifiedToolSearch
        self.constrained_generator = GalaxyWorkflowGenerator(config=self.config)
        self.dataset_selector = WorkflowDatasetSelector()

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
                {"title": c.title, "doi": c.doi, "year": c.year}
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
        uploaded_datasets: Optional[List[str]] = None
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
        uploaded_datasets: Optional[List[str]] = None
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

    def generate_workflow_unified(self, user_intent: str, uploaded_datasets: Optional[List[str]] = None) -> Dict[str, Any]:
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

        try:
            # Step 1: Search existing workflows (951+ indexed workflows)
            log.info("[UnifiedWorkflowGeneration] Step 1: Searching workflows...")
            search_results = self.workflow_search.search(user_intent, limit=5, include_workflow_json=True)

            if not search_results:
                log.info("[UnifiedWorkflowGeneration] No workflows found, will generate from scratch")
                score = 0.0
                match_type = "no_match"
            else:
                # WorkflowMatch is a dataclass, access via attributes
                best_match = search_results[0]
                score = best_match.score
                match_type = best_match.match_type  # high_confidence, medium_confidence, low_confidence
                log.info(f"[UnifiedWorkflowGeneration] Best match: {best_match.name} (score: {score:.2f}, match: {match_type})")

            workflow_ga = None
            source = None
            datasets_assigned = False
            generated_parameters = []  # Initialize for all paths

            # Step 2: Decide strategy based on template match confidence
            # Use match_type from workflow search (high/medium/low_confidence)
            # Thresholds: high_confidence >= 8.0, medium_confidence >= 4.0
            if match_type == "high_confidence":
                # High confidence - reuse existing workflow
                log.info("[UnifiedWorkflowGeneration] High confidence match - reusing workflow")
                best_match = search_results[0]
                source = 'template_reuse'

                # Check if this is a Nextflow workflow
                if best_match.format == 'nextflow':
                    log.info(f"[UnifiedWorkflowGeneration] Matched Nextflow workflow: {best_match.filename}")

                    # Build scientific rationale + parameter hints from Bioconductor KB.
                    # Pass best_match.tools (the workflow's tools_used list) for
                    # dynamic lookup; pattern dict supplements for R packages not listed.
                    scientific_rationale = self._build_scientific_rationale(
                        best_match.filename, best_match.name,
                        workflow_tools=best_match.tools,
                    )
                    if scientific_rationale:
                        log.info(
                            f"[UnifiedWorkflowGeneration] Scientific rationale built for "
                            f"{scientific_rationale.get('tools_used', [])}"
                        )

                    # Return Nextflow workflow format for direct execution
                    return {
                        'success': True,
                        'nextflow_path': best_match.filename,
                        'workflow_name': best_match.name,
                        'workflow_type': 'nextflow',  # Critical: tells frontend to use Nextflow execution
                        'source': 'template_reuse',
                        'confidence': int(score),
                        'template_match_score': int(score),
                        'message': f"Reused existing Nextflow workflow: {best_match.name}",
                        'note': f'Found Nextflow workflow with {best_match.step_count} step(s)',
                        'execution_engine': 'nextflow',
                        'format': 'nextflow',
                        # Scientific rationale from Bioconductor knowledge base
                        'scientific_rationale': scientific_rationale,
                        # Include workflow metadata for UI display
                        # scientific_rationale is also embedded here so the frontend
                        # can access it via data.workflow?.workflow_ga?.scientific_rationale
                        'workflow_ga': {
                            'name': best_match.name,
                            'description': best_match.description,
                            'annotation': best_match.description,
                            'tags': best_match.tags,
                            'format': 'nextflow',
                            'nextflow_path': best_match.filename,
                            'workflow_type': 'nextflow',
                            'steps': {},  # Nextflow steps are in the .nf file, not here
                            'scientific_rationale': scientific_rationale,
                        },
                        'datasets_assigned': False,  # Nextflow handles inputs via parameters
                        'generated_parameters': [],
                        'validation': {'is_valid': True, 'issues': [], 'warnings': [], 'suggestions': []},
                        'tool_installation': {'success': True, 'message': 'Nextflow workflow', 'failed_tools': []}
                    }

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

                # Assign datasets via WorkflowDatasetSelector
                log.info("[UnifiedWorkflowGeneration] Assigning datasets...")
                dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
                    workflow={'steps': workflow_steps},
                    user_intent=user_intent
                )

                # Build Galaxy .ga JSON with datasets
                workflow_ga = self._build_workflow_ga_from_template(workflow_json, dataset_assignments)
                datasets_assigned = True

                message = f"Reused existing workflow: {best_match.name}"

            elif match_type == "medium_confidence":
                # Medium confidence - adapt template using enhanced generator
                log.info("[UnifiedWorkflowGeneration] Medium confidence - adapting template")
                source = 'template_adapt'

                # Use enhanced generator (multi-strategy)
                user_request_obj = UserRequest(
                    request_id=str(uuid.uuid4()),
                    request_text=user_intent,
                    user_id="system",
                    timestamp=datetime.now()
                )

                workflow_result = self.workflow_generator.generate_workflow(user_request_obj)

                if workflow_result.get('success'):
                    workflow_data = workflow_result.get('workflow', {})
                    workflow_steps = workflow_data.get('steps', [])

                    # Add dataset assignment (enhanced generator doesn't do this)
                    log.info("[UnifiedWorkflowGeneration] Assigning datasets to adapted workflow...")
                    dataset_assignments = self.dataset_selector.select_datasets_for_workflow(
                        workflow={'steps': workflow_steps},
                        user_intent=user_intent
                    )

                    workflow_ga = self._build_workflow_ga_from_generated(workflow_data, dataset_assignments)
                    datasets_assigned = True
                    message = f"Adapted workflow template with {len(workflow_steps)} steps"
                else:
                    raise Exception(f"Enhanced generator failed: {workflow_result.get('error')}")

            else:
                # Low confidence - generate from scratch with tool constraint
                log.info("[UnifiedWorkflowGeneration] Low confidence - generating from scratch with tool constraint")
                source = 'tool_constrained'

                # Use constrained generator (prevents hallucinated tools)
                result = self.constrained_generator.generate_workflow(
                    user_intent=user_intent,
                    max_tools_search=30
                )

                if result['success']:
                    workflow_ga = result['workflow_ga']
                    datasets_assigned = True  # Constrained generator includes dataset assignment
                    generated_parameters = result.get('generated_parameters', [])  # Get LLM-generated parameters
                    message = f"Generated new workflow with {len(result['workflow_structure']['steps'])} steps (tool-constrained)"
                else:
                    raise Exception(f"Constrained generator failed: {result['error']}")

            # Step 3: Validate and install tools for ALL paths
            log.info("[UnifiedWorkflowGeneration] Step 3: Validating and installing tools...")
            tool_install_result = self._validate_and_install_tools(workflow_ga)

            if not tool_install_result['success']:
                log.warning(f"[UnifiedWorkflowGeneration] Tool installation had issues: {tool_install_result['message']}")
            else:
                log.info(f"[UnifiedWorkflowGeneration] Tool installation successful: {tool_install_result['message']}")

            # Return success response
            return {
                'success': True,
                'workflow_ga': workflow_ga,
                'source': source,
                'confidence': score if score > 0 else 0.3,  # Default low confidence for scratch generation
                'message': message,
                'datasets_assigned': datasets_assigned,
                'template_match_score': score,
                'generated_parameters': generated_parameters,  # Include LLM-generated parameters with confidence scores
                'tool_installation': tool_install_result,  # Include tool installation results
                'execution_engine': 'galaxy' if source == 'template_reuse' else 'nextflow',  # Explicit execution engine
                'workflow_tags': workflow_ga.get('tags', [])  # Workflow tags for frontend detection
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
                    hint = {
                        "param": param_name,
                        "recommended": str(rec.recommended_value),
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