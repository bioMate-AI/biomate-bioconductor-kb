"""
Galaxy AI Assistant

Main orchestrator that combines all AI components to provide intelligent research assistance.
"""


# Python 3.9 compat: PEP 604 union syntax in annotations below requires this.
from __future__ import annotations
import hashlib
import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime
from pathlib import Path
from galaxy.ai.nf_param_requirement import null_param_is_required as _null_required
import sqlite3
import re
from .workflow_relevance import relevant_candidates, workflow_relevance_verdict

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
from .unified_workflow_search import (
    UnifiedWorkflowSearch as _BaseUnifiedWorkflowSearch,
    get_workflow_search,
)
# Wired workflow search: applies workflow_intent priority + inject when
# BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1 (+ optional INJECT=1). Bit-identical
# to base when flags unset. Validated +9.0pp top-1 on n=155 routing benchmark.
try:
    from galaxy.ai.retrievers.wired_workflow_search import (
        WiredWorkflowSearch as UnifiedWorkflowSearch,
    )
except Exception as _wire_exc:  # noqa: BLE001
    import logging as _wire_log
    _wire_log.getLogger(__name__).warning(
        "WiredWorkflowSearch unavailable, falling back to base "
        "UnifiedWorkflowSearch (BIOMATE_WORKFLOW_INTENT_* flags will have "
        "no effect): %s", _wire_exc,
    )
    UnifiedWorkflowSearch = _BaseUnifiedWorkflowSearch
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
# GEO data-modality detection — the DATA-FIRST routing signal, lifted to module
# scope so BOTH the chat path (AIAssistant._detect_geo_platform) and the
# execute-gate (via the /api/ai_assistant/geo_platform endpoint) share ONE
# implementation. See docs/20261102_UNIFIED_PUBLIC_ID_ROUTING_DESIGN.md.
# ---------------------------------------------------------------------------
_GEO_PLATFORM_CACHE: Dict[str, Optional[str]] = {}


def detect_geo_platform(gse_id: str, cache: Optional[Dict[str, Optional[str]]] = None) -> Optional[str]:
    """Read GEO's own Series metadata to determine data modality.

    Returns 'microarray' | 'scrna' | 'bulk_rnaseq' | None (unknown / lookup failed).
    One HTTP GET to GEO's SOFT text endpoint; `!Series_type` is authoritative for
    array-vs-sequencing, and title/summary/design disambiguate scRNA from bulk.
    Any failure returns None so the caller can fall back — never raises into routing.
    Results are cached per accession for the process lifetime (shared module cache
    when `cache` is omitted).
    """
    if cache is None:
        cache = _GEO_PLATFORM_CACHE
    if gse_id in cache:
        return cache[gse_id]
    result: Optional[str] = None
    try:
        import urllib.request as _u
        url = (f"https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc={gse_id}"
               "&targ=self&form=text&view=quick")
        with _u.urlopen(url, timeout=4) as _r:
            text = _r.read().decode('utf-8', 'replace')
        types, meta = [], []
        for ln in text.splitlines():
            low = ln.lower()
            if low.startswith('!series_type'):
                types.append(low.split('=', 1)[-1].strip())
            elif (low.startswith('!series_title') or low.startswith('!series_summary')
                  or low.startswith('!series_overall_design')):
                meta.append(low.split('=', 1)[-1].strip())
        blob = ' '.join(meta)
        has_array = any('array' in t for t in types)
        has_seq = any('sequencing' in t for t in types)
        sc = any(k in blob for k in [
            'single cell', 'single-cell', 'scrna', 'sc-rna', '10x', 'droplet',
            'drop-seq', 'chromium', 'single nucleus', 'single-nucleus', 'snrna',
        ])
        if has_array and not has_seq:
            result = 'microarray'
        elif has_seq and not has_array:
            result = 'scrna' if sc else 'bulk_rnaseq'
        else:
            result = None  # mixed / no type line → unknown, let caller fall back
        log.info("[GeoFastPath] GEO %s metadata: types=%s → platform=%s", gse_id, types, result)
    except Exception as _e:
        log.info("[GeoFastPath] GEO platform lookup for %s failed (%s) — caller falls back", gse_id, _e)
        result = None
    cache[gse_id] = result
    return result


# ---------------------------------------------------------------------------
# Module-level bounded cache for multi-task LLM classification results.
# Keyed by MD5 of the lowercased query; evicts oldest entry when full.
# ---------------------------------------------------------------------------
_MULTI_TASK_CACHE: dict = {}
_MULTI_TASK_CACHE_MAX = 128

# Fastest/cheapest model per provider for lightweight classification calls.
_FAST_CLASSIFICATION_MODELS: dict = {
    'anthropic': 'claude-haiku-4-5',
    'gemini': 'gemini-3.8-flash',
    'google': 'gemini-3.8-flash',
    'openai': 'gpt-3.5-turbo',
    'deepseek': 'deepseek-chat',
    'zhipu': 'glm-4-flash',
    # ollama / local: keep configured model (already fast locally)
}


# Tokens that commonly appear as named alternative methods in DE / consensus
# workflows. When a query mentions ≥2 of these alongside an alternative-marker
# word (or, vs, compare, etc.), the disambiguation gate fires regardless of
# the BGE retrieval score — see _detect_alt_method_enumeration().
_ALT_METHOD_TOKENS: tuple = (
    'deseq2', 'edger', 'limma', 'dss', 'ebseq', 'baysseq', 'baycseq',
    'noiseq', 'sleuth', 'mast', 'monocle',
)
def _detect_alt_method_enumeration(user_intent: str):
    """Return (methods_mentioned, is_enumeration).

    A query "enumerates alternatives" when it names ≥2 known DE / consensus
    method tokens AND includes an alternative-marker word (or, vs, compare,
    alternatives, either, both, and). Used by the disambiguation gate in
    UnifiedWorkflowGeneration to force candidate selection even when BGE
    retrieval returns a single high-confidence winner.
    """
    import re as _re_local
    if not user_intent:
        return [], False
    q = user_intent.lower()
    methods = [t for t in _ALT_METHOD_TOKENS if t in q]
    if len(methods) < 2:
        return methods, False
    has_marker = bool(_re_local.search(
        r'\b(or|vs\.?|versus|compare|comparison|alternatives?|either|both|and)\b',
        q,
    ))
    return methods, has_marker


def _eager_load_steps(nextflow_path: str) -> dict:
    """Eagerly parse steps from a .nf file so workflow_ga ships with real step data.

    Uses a deferred import to avoid the circular import:
    webapps/galaxy/api/ai_assistant → galaxy.ai.ai_assistant (this module).
    Falls back silently to {} so callers always get a dict.
    """
    try:
        from galaxy.webapps.galaxy.api.ai_assistant import _parse_nextflow_steps  # noqa: PLC0415
        return _parse_nextflow_steps(nextflow_path)
    except Exception:
        return {}


def _composed_workflow_name(data: Dict) -> str:
    """A composed workflow's display name: its own name, else the first clause of its description
    (<=60 chars), never the literal placeholder "Generated Workflow" — a GSE157703 scRNA request
    showed a card titled "Generated Workflow" (external-user replay, dev 2026-11-04)."""
    import re as _re_nm
    name = str((data or {}).get('name') or '').strip()
    if name and name.lower() != 'generated workflow':
        return name
    desc = str((data or {}).get('description') or (data or {}).get('annotation') or '').strip()
    clause = _re_nm.split(r'(?<=[.;:])\s|\s[—–-]\s', desc)[0].strip().rstrip('.;:') if desc else ''
    if clause:
        return clause if len(clause) <= 60 else clause[:57].rsplit(' ', 1)[0] + '…'
    # No description (composed from catalog steps): name it after its own steps.
    steps = (data or {}).get('steps') or []
    if isinstance(steps, dict):
        steps = list(steps.values())
    labels = []
    for st in steps if isinstance(steps, list) else []:
        lab = str((st or {}).get('name') or (st or {}).get('tool_id') or (st or {}).get('label') or '').strip() if isinstance(st, dict) else ''
        lab = _re_nm.sub(r'[_]+', ' ', lab).strip()
        if lab and lab.lower() not in (l.lower() for l in labels):
            labels.append(lab)
    if labels:
        joined = ' → '.join(labels[:3])
        return joined if len(joined) <= 60 else joined[:57].rsplit(' ', 1)[0] + '…'
    return 'Custom workflow'



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

        # Register reactive chain templates into the DB at startup.
        try:
            from galaxy.ai.bioc_chain_templates import register_bioc_chains
            register_bioc_chains()
        except Exception as _bioc_reg_exc:
            log.error("bioc_chain_templates startup registration failed: %s", _bioc_reg_exc)

        try:
            from galaxy.ai.cryoem_chain_templates import register_cryoem_chains
            register_cryoem_chains()
        except Exception as _cryoem_reg_exc:
            log.error("cryoem_chain_templates startup registration failed: %s", _cryoem_reg_exc)

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
        # Short-circuit: explicit routing guard prefix from eval harness or direct
        # knowledge questions — bypass all intent routing and treat as research_question.
        if query.startswith("KNOWLEDGE QUESTION"):
            return {
                "intent": "research_question",
                "confidence": 1.0,
                "handler": "research_agent",
                "secondary_intents": [],
                "requires_workflow": False,
                "requires_literature": True,
                "requires_benchmark": False,
                "entities": {},
                "routing_method": "forced_research",
            }

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

        .. warning::
            NOT WIRED TO THE LIVE PATH (as of 2026-10-12). This method (and the
            multi-task clarification + backend DAG composer it calls:
            ``_looks_like_multi_task`` / ``_handle_multi_task_clarification`` /
            ``decomposed_dag.build_dag_plan``, gated by ``BIOMATE_MULTITASK_DAG_ENABLED``)
            has NO live callers — only unit tests. The live chat/generation endpoint is
            ``generate_workflow_unified`` (``/api/ai_assistant/generate_workflow``), and
            the live multi-step composer is the Node-side
            ``galaxy-assistant.ts::processSequentialPipeline`` (reached when
            ``analyzeIntent`` flags ``isMultiIntent``/``isSequential``). Enabling
            ``BIOMATE_MULTITASK_DAG_ENABLED`` therefore changes NO live behaviour.
            This remains as a tested, validated (``galaxy.chain.dag.validate_plan``)
            candidate for a future *rigorous* composer — wire or remove deliberately.
            See docs/20261012_COMPOSER_FLAG_ENABLED_AND_WIRING_GAP.md.

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

        # Shadow-only chain composer telemetry. Default off, never raises, log-only.
        # Enable via BIOMATE_COMPOSER_SHADOW=1. See chain_composer/telemetry.py.
        try:
            from .chain_composer.telemetry import shadow_log as _composer_shadow_log
            _composer_shadow_log(query, _ctx)
        except Exception:  # pragma: no cover — must never break routing
            pass

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
        # --- Flag-gated Pattern-Router hook (default OFF). -------------------
        # When BIOMATE_PATTERN_ROUTER_ENABLED is off (the default), this reads a
        # single env var and does nothing else -- no import, no new call -- so the
        # path below is behaviorally identical to today's single-pass generation.
        # Only when enabled does it consult the (already-tested) pattern_router,
        # which itself only reaches the dormant multi-agent orchestrator for a
        # MULTI_SPECIALIST decision. Any failure falls through to the default path.
        import os as _os
        if _os.environ.get("BIOMATE_PATTERN_ROUTER_ENABLED", "").strip().lower() in (
            "1", "true", "yes", "on"
        ):
            try:
                from .pattern_router import maybe_route_workflow_generation
                _pr = maybe_route_workflow_generation(query, context, enabled=True)
                _res = _pr.get("result")
                if _pr.get("dispatched") and isinstance(_res, dict):
                    return {
                        "success": _res.get("success", True),
                        "handler": "agent_orchestrator",
                        "workflow": _res.get("workflow_ga") or _res.get("workflow"),
                        "source": _res.get("source", "pattern_router:multi_specialist"),
                        "confidence": _res.get("confidence"),
                        "message": _res.get("message"),
                        "pattern": (_pr.get("decision") or {}).get("pattern"),
                    }
            except Exception as _hook_exc:  # never break the live path
                log.warning(
                    "[PatternRouter] hook skipped (%s); using unified generation",
                    _hook_exc,
                )
        # ---------------------------------------------------------------------
        # Use the existing generate_workflow_unified method
        datasets = context.get('datasets', []) if context else []
        # Ground routing in the SHAPE of the user's attached data (data_perception).
        # Without this the chat/agent path searched on prose alone, so a SMILES library +
        # receptor .pdb (→ {molecules, structure}) never reached step 8a or the relevance
        # floor's input_compatible veto, and a bare "rank …" keyword-matched a CSV-assay
        # ranker (incident 2026-11-12). The /generate_workflow HTTP endpoint already threads
        # this via resolve_effective_input_kinds; the chat/agent path did not.
        user_input_kinds = self._perceive_user_input_kinds(context)
        result = self.generate_workflow_unified(
            query, uploaded_datasets=datasets, user_input_kinds=user_input_kinds,
        )
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

        return self._fast_llm_client.generate(prompt, max_tokens=128, temperature=0.0, use_fast_model=True)

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

            # No missing context. Reconciliation #3 (first slice): when enabled,
            # assemble the decomposed tasks into an executable DAG plan instead of
            # DISCARDING them (the old behaviour collapsed N tasks → one workflow).
            # Default OFF (BIOMATE_MULTITASK_DAG_ENABLED) → byte-for-byte the prior
            # single-task path. The assembled plan is validated against the chain
            # executor contract (galaxy.chain.dag); if any task can't be resolved,
            # build_dag_plan returns None and we fall back safely.
            import os as _os
            if _os.environ.get("BIOMATE_MULTITASK_DAG_ENABLED", "").strip().lower() in ("1", "true", "yes", "on"):
                try:
                    from .decomposed_dag import build_dag_plan, bind_shared_inputs, to_pipeline_card
                    from functools import partial as _partial
                    # Bind the user's perceived data shape onto every per-step resolution so the
                    # chain's sub-searches are data-grounded, not prose-only (incident 2026-11-12).
                    _user_kinds = self._perceive_user_input_kinds(context)
                    _dag = build_dag_plan(
                        tasks,
                        _partial(self._resolve_task_to_workflow, user_input_kinds=_user_kinds),
                        type_provider=self._workflow_io_types,
                    )
                    if _dag:
                        # Best-effort: prefill the user's input onto fan-out root steps.
                        _dag = bind_shared_inputs(_dag, self._extract_input_refs(context))
                        log.info(f"[MultiTask] assembled {len(_dag['steps'])}-step DAG plan (not discarded)")
                        # Emit the frontend's pipeline-card shape so the existing
                        # whole-plan chain card renders + submits it (no frontend change).
                        return {
                            'message': f"Prepared a {len(_dag['steps'])}-step plan with dependencies. Review and run when ready.",
                            'success': True,
                            'execution_mode': 'dag',
                            'workflow': to_pipeline_card(_dag),
                            'pipeline_id': pipeline_id,
                        }
                    log.info("[MultiTask] DAG assembly incomplete (a task did not resolve) — single-task fallback")
                except Exception as _dag_exc:
                    log.warning(f"[MultiTask] DAG assembly failed ({_dag_exc}) — single-task fallback")
            # Fall back to single-task generation (default path).
            log.info(f"[MultiTask] {len(tasks)} tasks detected, generating sequentially for now")
            return await self._handle_workflow_generation(query, context)

        except Exception as e:
            log.warning(f"[MultiTask] Decomposition failed ({e}), falling back to single-task")
            return await self._handle_workflow_generation(query, context)

    def _perceive_user_input_kinds(self, context):
        """Closed-vocabulary input kinds the user HAS, grounded in the datasets actually
        attached to this turn (data_perception.resolve_effective_input_kinds). Returns a
        list, or None when nothing can be grounded (routing then falls back to prose). NEVER
        raises — perception must not block routing. Threaded into workflow search so step 8a
        and the relevance floor's input_compatible veto can demote a workflow that cannot
        consume the user's data shape (incident 2026-11-12: {molecules, structure} ignored)."""
        try:
            from .data_perception import resolve_effective_input_kinds
            datasets = (context or {}).get('datasets') or []
            return resolve_effective_input_kinds(None, datasets)
        except Exception as exc:  # noqa: BLE001 — perception must never block routing
            log.debug(f"[Perception] input-kind inference failed: {exc}")
            return None

    def _resolve_task_to_workflow(self, task, user_input_kinds=None):
        """Best-effort per-task resolution for the decomposed DAG (reconciliation #3).

        Returns ``{'nextflow_path', 'parameters'}`` or ``None``. Conservative: the
        top workflow-search match only, and ``None`` on anything uncertain — so
        ``build_dag_plan`` safely falls back to single-task generation rather than
        emitting an unexecutable DAG. (Richer resolution + input binding is the
        next sub-slice of the logical->executable adapter.)

        ``user_input_kinds`` is the SHAPE of the user's attached data (bound by the caller
        via functools.partial). Threading it means each per-step search is grounded in the
        real data shape instead of the step description's prose alone.
        """
        try:
            desc = getattr(task, 'description', None)
            if desc is None and isinstance(task, dict):
                desc = task.get('description')
            if not desc:
                return None
            from .decomposed_dag import pick_workflow_match
            # Confidence-gated: only a medium+ match resolves; weak matches → None
            # → build_dag_plan falls back to single-task (never dispatches a guess).
            return pick_workflow_match(self.workflow_search.search(desc, user_input_kinds=user_input_kinds))
        except Exception as exc:
            log.debug(f"[MultiTask] task resolution failed: {exc}")
        return None

    def _workflow_io_types(self, nextflow_path):
        """(input_types, output_types) for a workflow — used to wire dependent-step
        handoffs in the decomposed DAG by type compatibility. Returns None on any
        failure so build_dag_plan refuses to fabricate a handoff and falls back."""
        try:
            from galaxy.webapps.galaxy.api.workflow_chain import _get_workflow_types
            return _get_workflow_types(nextflow_path)
        except Exception as exc:
            log.debug(f"[MultiTask] io-types lookup failed for {nextflow_path}: {exc}")
            return None

    def _extract_input_refs(self, context):
        """User-provided input file references (for best-effort DAG root prefill)."""
        ctx = context or {}
        refs = []
        for key in ('datasets', 'inputFiles', 'input_files', 'files'):
            val = ctx.get(key)
            if isinstance(val, list):
                refs.extend(val)
        return refs

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
            # A provider error (HTTP 429/timeout/outage) is NOT "no citations found" —
            # make it loud so it isn't mistaken for an empty-but-successful search.
            log.error(f"Literature search FAILED (provider error — DEGRADED, not 'no citations'): {e}")
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
                    galaxy_root = str(getattr(self.galaxy_app.config, 'root', '/app'))
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
            # A generic ADMET / safety-screen workflow gets the standard ADMET QC
            # profile (hERG IC50, DILI, Ames gates). Unlike cryo-EM/proteomics there
            # is NO backend domain auto-default for drug-discovery, so returning None
            # here left ADMET runs with no profile and no gate could ever fire.
            # Other drug-discovery workflows (docking, generation) have no
            # compound-safety gate and correctly stay None.
            if any(k in all_text for k in ("admet", "adme", "herg", "cardiotox",
                                           "hepatotox", "dili", "ames", "toxicit",
                                           "safety", "liabilit")):
                return "admet_standard"
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
        Also excludes workflows with executable=0 (deprecated/disabled).
        """
        if not getattr(match, 'executable', 1):
            return False
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

        # Prefer canonical runnable entry scripts — but a filename ending in
        # /main.nf is NOT sufficient: an nf-core subworkflow whose stored path
        # slips past the substring excludes above (e.g. real nf-core/rnaseq
        # FASTQ_QC_TRIM_FILTER_SETSTRANDEDNESS) is a `take:`-only named workflow
        # with no anonymous `workflow {}`. Launching it via `-entry` aborts with
        # "declares N input channels but 0 were given" (the RC-1 failure). Verify
        # on disk that the resolved file is actually standalone-runnable.
        if filename.endswith('/main.nf'):
            resolved = self._resolve_execution_nf(getattr(match, 'filename', '') or '')
            if resolved is None:
                return False  # file not on disk — can't run it
            if not self._nf_file_is_standalone_runnable(resolved):
                return False
            return True
        if filename.endswith('.nf') and ('/workflows/' in filename or 'biomni_nf/' in filename or '/bioconductor/' in filename):
            resolved = self._find_nf_file(getattr(match, 'filename', '') or '')
            return resolved is not None
        return False

    def _resolve_execution_nf(self, filename: str) -> Optional[Any]:
        """The .nf file the EXECUTOR will run for a DB filename (nextflow_executor._resolve_nextflow_path).

        _find_nf_file prefers the biomni_workflows/ display stubs (their curated user-facing params), but the
        executor runs the real downloaded nf-core pipeline when one exists (resolver order fixed 2026-08-24).
        Judging runnability on the stub flagged every nf-core pipeline as non-executable — 128 of 131 have a
        real copy on dev (2026-11-05). Falls back to _find_nf_file when the executor cannot resolve the path."""
        try:
            from galaxy.webapps.galaxy.api.nextflow_executor import _resolve_nextflow_path  # noqa: PLC0415
            return _resolve_nextflow_path(filename)
        except Exception:  # unresolvable here, or executor module unavailable (e.g. unit tests)
            return self._find_nf_file(filename)

    def _nf_file_is_standalone_runnable(self, nf_path: Any) -> bool:
        """True iff the `.nf` at `nf_path` can be launched directly.

        Runnable ⟺ it has an anonymous `workflow {` block (Nextflow's default
        entry). A file whose only entry is a named `workflow NAME { take: … }`
        cannot be launched via `-entry` — the `take:` channels are unbindable —
        so it is NOT standalone-runnable. Exception: Bioconductor subworkflows
        under `/bioconductor/` are made runnable at execution time by
        `_build_bioc_entry_wrapper`, so they stay eligible. If the file can't be
        read (e.g. resolved off-box), don't over-reject — return True."""
        p = str(nf_path)
        try:
            text = Path(p).read_text(errors='replace')
        except Exception:
            return True
        # Anonymous `workflow {` → Nextflow default entry → runnable.
        if re.search(r'(?m)^\s*workflow\s*\{', text):
            return True
        has_named = re.search(r'(?m)^\s*workflow\s+[A-Za-z_]', text) is not None
        # No workflow entry at all (a parameter stub — e.g. nfcore/rnaseq,
        # nfcore/sarek — with only params + processes) → "No entry workflow".
        if not has_named:
            return False
        # Named-only workflow with a `take:` block → unbindable via -entry, except
        # Bioconductor subworkflows which _build_bioc_entry_wrapper wraps at run time.
        if re.search(r'(?m)^\s*take\s*:', text):
            return '/bioconductor/' in p
        # Named workflow(s) without take: → runnable via `-entry <name>`.
        return True

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
        filename = (getattr(match, "filename", "") or "").lower()
        # BioMate AI-native tool workflows (biomate-ai-tools/<name>/main.nf, or stored as
        # nf-core-workflows/modules/biomate-ai-tools/<name>/main.nf) and nextflow_nfcore/
        # subworkflows biomate tools are standalone AWS-Batch-runnable entry points — the
        # runnable_keys whitelist is meant only for bioconductor subworkflows + biomni
        # custom workflows. Without these bypasses a correctly-ranked #1 biomate-ai-tools
        # match (e.g. cyclic_peptide_design, score 114) fails the preferred executable+runnable
        # loop in _pick_best_executable_nextflow_match and the router falls to a lower-scored
        # sibling (cyclic_peptide_cofold, 44). Mirrors the webapps search copy's bypass.
        if "/bioconductor/" not in filename and (
            "biomate-ai-tools/" in filename
            or (filename.startswith("nextflow_nfcore/subworkflows/"))
            or (filename.startswith("nfcore/") and "/main.nf" in filename)
        ):
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

    def _llm_verify_routing(
        self,
        query: str,
        candidates: List[Any],
        match_type: str,
    ) -> Dict[str, Any]:
        """
        Ask the LLM to verify the top-scored workflow candidate against the user query,
        produce an auditable rationale, and optionally override to a better candidate.

        Returns:
          {
            "selected_idx": int,   # 0-based index into candidates
            "rationale": str,      # why this workflow matches the query
            "audit": str,          # any red flags found (or "none")
            "flag": bool,          # True = clear mismatch, selection overridden
          }

        Falls back to {"selected_idx": 0, ...} if the LLM client is unavailable.
        Only called for non-trivial decisions (high_confidence with close competitors,
        or medium_confidence).
        """
        if not candidates or self._fast_llm_client is None:
            return {"selected_idx": 0, "rationale": "", "audit": "", "flag": False}

        top = candidates[:4]
        lines = []
        for i, c in enumerate(top):
            desc = (getattr(c, 'description', '') or '')[:250].replace('\n', ' ')
            lines.append(f"{i+1}. [{c.name}] score={c.score:.1f}\n   {desc}")
        candidates_text = "\n".join(lines)

        prompt = f"""You are auditing a bioinformatics workflow routing decision.

User query: "{query}"

Candidate workflows (ranked by retrieval score):
{candidates_text}

Steps:
1. RATIONALE — Write 1–2 sentences explaining why candidate #1 fits (or does not fit) the query.
2. AUDIT — Check for mismatches: wrong assay type (e.g. ChIP-seq picked for ATAC-seq query),
   wrong scope (annotation-only tool for a full pipeline request), wrong data type
   (single-cell pipeline for bulk RNA-seq), or clearly irrelevant domain.
   Write one sentence about any red flag, or "none".
3. SELECTION — Which candidate number (1–{len(top)}) best fits the query?
   Prefer #1 unless there is a CLEAR mismatch. Switching to #2/#3 requires a concrete reason.

Respond with a single JSON object — no other text:
{{"selected": 1, "rationale": "...", "audit": "...", "flag": false}}

"flag" must be true only when you switch away from #1 due to a clear mismatch."""

        try:
            raw = (self._fast_llm_client.generate(prompt, max_tokens=220, temperature=0.0, use_fast_model=True) or "").strip()
            # Extract JSON from response
            import re as _re
            m = _re.search(r'\{.*\}', raw, _re.DOTALL)
            if not m:
                log.debug("[_llm_verify_routing] No JSON found in LLM response: %r", raw[:200])
                return {"selected_idx": 0, "rationale": "", "audit": "", "flag": False}
            parsed = json.loads(m.group())
            sel = int(parsed.get("selected", 1)) - 1  # convert to 0-based
            sel = max(0, min(sel, len(top) - 1))
            result = {
                "selected_idx": sel,
                "rationale": str(parsed.get("rationale", "")),
                "audit": str(parsed.get("audit", "")),
                "flag": bool(parsed.get("flag", False)),
            }
            log.info(
                "[_llm_verify_routing] query=%r | match_type=%s | selected=%d (%s) | flag=%s\n"
                "  rationale: %s\n  audit: %s",
                query[:80], match_type, sel + 1, top[sel].name if sel < len(top) else "?",
                result["flag"], result["rationale"], result["audit"],
            )
            return result
        except Exception as exc:
            log.warning("[_llm_verify_routing] failed: %s", exc)
            return {"selected_idx": 0, "rationale": "", "audit": "", "flag": False}

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

    # NOTE: `genome` is NOT internal — it is the nf-core iGenomes key (GRCh38, …),
    # a user-facing scientific parameter. Hiding it broke rule-based organism→genome
    # inference and made project-rule obedience impossible for rnaseq/sarek/etc.
    # `input` stays internal: the executor builds the samplesheet (fetchngs / upload).
    _NEXTFLOW_INTERNAL_PARAMS = {
        'mock_mode', 'outdir', 'sample_id', 'platform', 'library',
        'max_cpus', 'max_memory', 'max_time', 'publish_dir_mode', 'monochrome_logs',
        'enable_conda', 'singularity_pull_docker_container', 'validationSkipDuplicateCheck',
        'tracedir', 'awsbatch', 'awsqueue', 'awsregion', 'input', 'output',
        # CryoSPARC connection — all infra-level, set by admin not users
        'cryosparc_email', 'cryosparc_host', 'cryosparc_port', 'cryosparc_project_dir', 'cryosparc_lane',
        # CryoSPARC license — injected at runtime by executor from credential vault, not user-entered
        'cryosparc_license',
        # Container image URIs — executor/infra, never clinic-facing (ECR leak 2026-11-13)
        'cs_image', 'container', 'container_image', 'pmemd_container',
        'fpsim2_container', 'foldseek_container', 'mlip_container', 'mmseqs_container',
        # Dev/testing flags — never shown to users (false = mock mode which breaks production)
        'use_cryosparc',
        # Parallelism / executor internals — auto-set by BioMate executor before launch
        'micrograph_batch_size', 'particle_batch_size', 'num_gpu_workers', 'max_parallel_jobs',
        'num_gpu', 'num_cs_workers', 'movie_batch_dirs',
        # Motion & GPU internals — auto-tuned by executor
        'motion_correction_dose_weighting', 'enable_low_memory_mode', 'gpu_memory_gb',
    }

    # Clinic hard-required primary data inputs. nextflow_schema.json often declares
    # `required: []` (differentialabundance stub) or .nf uses demo elvis
    # (movies_path ?: test_data). Without this override the panel says "no required
    # data inputs" and Confirm & Run launches empty. Keep in sync with
    # frontend/shared/workflow-data-inputs.ts CLINIC_HARD_REQUIRED_DATA_NAMES.
    _CLINIC_HARD_REQUIRED_DATA = frozenset({
        'movies_path', 'movie_dir',
        'samplesheet', 'sample_sheet',
        'matrix', 'counts', 'count_matrix',
        'reads', 'fastq', 'fastq_1', 'fastq_2', 'input_fastq',
        'input_csv', 'input_file', 'input_path',
    })

    # Params that are `= null` in .nf files but are auto-calculated or truly optional.
    # These should NOT be treated as hard required-by-user params even though their
    # default is null — they fall back gracefully inside the workflow scripts.
    _OPTIONAL_NULL_PARAMS = frozenset({
        # Cryo-EM / CryoSPARC
        'cryosparc_password',         # server-side auth — always injected by executor from env
        'gain_ref',                   # optional gain reference for gain correction
        'dose_per_frame',             # auto-estimated from total_dose / num_frames
        'particle_box_size',          # auto-calculated from particle diameter
        'particle_diameter_angstroms', # estimated from molecular_weight_kda if absent
        'molecular_weight_kda',       # used only to estimate diameter when explicit diameter absent
        # Drug discovery / MD
        'receptor_pdb',               # optional — sometimes passed via uploaded file
        'ligand_sdf',                 # optional — sometimes passed via uploaded file
        'topology_file',              # optional — used for restart/continuation runs
        'checkpoint_file',            # optional — restart only
        'restraints_file',            # optional — position restraints
        # Drug discovery / generative lead design (reinvent4_lead_design, scaffold_hopping)
        # — null defaults that are CONDITIONALLY required only for non-default
        # scoring functions. The .nf enforces them at runtime (error out iff
        # scoring_function == 'docking_gnina'/'custom_toml' and the value is
        # absent), so the common default scoring_function='qed_sa' generation
        # path must NOT be gated on them.
        'receptor',                   # optional — only required for scoring_function=docking_gnina
        'docking_ref_ligand',         # optional — only used for docking box center (docking_gnina)
        'custom_toml',                # optional — only required for scoring_function=custom_toml
        # Genomics
        'known_sites',                # optional — dbSNP for BQSR (hg38 auto-injected)
        'intervals',                  # optional — targeted sequencing intervals
        'pon',                        # optional — Panel of Normals for somatic callers
        'germline_resource',          # optional — gnomAD for mutect2
        # GEO accession fetch (geo_data_connector)
        'local_series_matrix',        # optional local override — null means auto-download from GEO by accession
    })

    def _find_nf_file(self, filename: str) -> Optional[Any]:
        """Resolve DB-stored filename to absolute .nf path.

        Search order:
        1. biomni_workflows/ stubs — fast path for custom/BioMate-specific workflows.
        2. nf-core-workflows/ — full nf-core pipelines with nextflow_schema.json.
           Preferred when the stub lacks a schema (gives authoritative param metadata).
        3. Bare backend-relative path.
        """
        if not filename:
            return None
        from pathlib import Path as _Path
        this_file = _Path(__file__).resolve()
        backend_root = this_file.parent
        for ancestor in list(this_file.parents):
            if (ancestor / "biomni_workflows").is_dir():
                backend_root = ancestor
                break

        # Normalize nfcore/<name>/... → <name>/... for nf-core-workflows lookup
        _nfcore_suffix = None
        if filename.startswith("nfcore/"):
            _nfcore_suffix = filename[len("nfcore/"):]  # e.g. "differentialabundance/main.nf"

        candidates = [
            backend_root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / filename,
            backend_root / "biomni_workflows" / "nextflow_nfcore" / filename,
            backend_root / "biomni_workflows" / "subworkflows" / filename,
            backend_root / "biomni_workflows" / filename,
            # biomate-ai-tools modules live under nf-core-workflows/modules/, not
            # biomni_workflows/. Without this the workflow_ga.required_params
            # ships empty for in_vivo_cart_codesign / glp1_modality_bakeoff /
            # modality_triage / etc, forcing the frontend's schema-grounded
            # extractor to fall back to the legacy WORKFLOW_PARAM_ALIASES table.
            backend_root / "nf-core-workflows" / "modules" / "biomate-ai-tools" / filename,
            # Some biomate-ai-tools workflows store their DB filename WITH the
            # "biomate-ai-tools/" prefix already (e.g. cyclic_peptide_design →
            # "biomate-ai-tools/cyclic_peptide_design/main.nf"), others without it.
            # The candidate above only handles the without-prefix form; for the
            # with-prefix form it doubles to .../modules/biomate-ai-tools/biomate-ai-tools/...
            # (absent) → _find_nf_file returns None → the workflow is wrongly
            # excluded from PRIMARY by _is_executable_nextflow_match and the router
            # falls through to a lower-scored sibling (observed 2026-10-29: a cyclic
            # peptide DESIGN query routed to cyclic_peptide_cofold instead). This
            # candidate resolves the with-prefix form; first-existing-wins, so it is
            # purely additive and never changes a path that already resolves.
            backend_root / "nf-core-workflows" / "modules" / filename,
        ]
        # Add nf-core-workflows/ candidates when it looks like an nf-core workflow
        if _nfcore_suffix:
            candidates += [
                backend_root / "nf-core-workflows" / _nfcore_suffix,
                backend_root / "nf-core-workflows" / _nfcore_suffix / "main.nf",
            ]
        candidates.append(backend_root / filename)

        # Prefer the candidate whose parent directory contains nextflow_schema.json
        # (authoritative nf-core metadata) over a stub that only has a bare .nf file.
        with_schema = [c for c in candidates if c.exists() and (c.parent / "nextflow_schema.json").exists()]
        without_schema = [c for c in candidates if c.exists() and c not in with_schema]
        for c in (with_schema + without_schema):
            return c

        # Domain alias fallback — same drug_discovery ↔ pharmacology map as
        # nextflow_executor._resolve_nextflow_path. Without this, a catalog row
        # whose filename still says drug_discovery/ADMET_pred resolves for
        # execution (alias) but _find_nf_file returns None → empty required_params
        # and empty-schema phantom inline_parameters (2026-11-13 Admet Pred).
        _DOMAIN_ALIASES = {
            "drug_discovery": "pharmacology",
            "pharmacology": "drug_discovery",
        }
        alias_candidates = []
        for c in candidates:
            parts = c.parts
            for i, part in enumerate(parts):
                if part in _DOMAIN_ALIASES:
                    aliased = _Path(*parts[:i]) / _DOMAIN_ALIASES[part] / _Path(*parts[i + 1:])
                    alias_candidates.append(aliased)
                    break
        with_schema_a = [c for c in alias_candidates if c.exists() and (c.parent / "nextflow_schema.json").exists()]
        without_schema_a = [c for c in alias_candidates if c.exists() and c not in with_schema_a]
        for c in (with_schema_a + without_schema_a):
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

    # User-facing names for executor-owned data inputs (the param itself is never editable).
    _EXECUTOR_DATA_INPUT_LABELS: dict = {
        'input': 'Samplesheet (sequencing reads)',
    }

    @staticmethod
    def _is_schema_data_input(name: str, param_def: dict) -> bool:
        """A schema param that carries the run's input DATA (not a setting): file-path/path
        format, a mimetype, or a pattern ending in a data-file extension."""
        if name.startswith('out') or name in ('publish_dir', 'tracedir'):
            return False  # output locations are not input data
        fmt = str(param_def.get('format', '')).lower()
        if fmt in ('file-path', 'file-path-pattern'):
            return True
        if param_def.get('mimetype') or param_def.get('schema'):
            return True
        return name in ('input', 'samplesheet', 'reads')

    _RUN_DATA_RE = re.compile(
        r'\[(?:Uploaded datasets?|Attached files?|Galaxy dataset)\s*:'
        r'|\b(?:[SED]RR\d{6,9}|[SED]RX\d{6,9}|PRJ[NED][A-Z]?\d{4,9}|GSE\d{3,9}|GSM\d{3,9}|E-[A-Z]{4}-\d{1,9}|PXD\d{4,9})\b',
        re.IGNORECASE,
    )

    # Parameter names that represent input data files — these get type="file" so the
    # frontend renders a dataset browser instead of a plain text box.
    # iGenomes key names (genome / genome_build / …) are STRING build IDs, not files —
    # keep them out of this set so schema/.nf projection types them as string/select.
    _INPUT_FILE_PARAM_NAMES: frozenset = frozenset([
        'input', 'reads', 'reads1', 'reads2', 'fastq', 'fastq1', 'fastq2',
        'bam', 'fasta', 'genome_fasta', 'reference', 'reference_genome',
        'gtf', 'gff', 'bed', 'vcf', 'csv', 'samplesheet', 'sample_sheet',
        # Differential-expression inputs are deliberately explicit here.  They are
        # files even though their names do not end in "_file" or "_path"; without
        # this they render as free text and cannot participate in dataset binding.
        'design', 'matrix', 'counts', 'count_matrix', 'metadata', 'sample_metadata',
        'coldata', 'contrasts', 'contrast', 'multiqc_config', 'star_index', 'hisat2_index', 'bwa_index',
        'bowtie2_index', 'transcript_fasta', 'additional_fasta', 'transcript',
        'probeset', 'annotation', 'blacklist', 'bait_intervals', 'target_intervals',
        # Explicit fasta-input variants — historically classified as 'string'
        # because 'input_fasta' != 'fasta' in the exact-match check.  Adding
        # them here ensures the AI skips them when no file path is in the query.
        'input_fasta', 'input_fa', 'query_fasta', 'ref_fasta', 'input_fastq',
        'query_fa', 'protein_fasta', 'nucleotide_fasta',
    ])

    # Params that hold raw biological sequence TEXT (not file paths).
    # When a user's query contains a long AA/NT string, the AI should fill
    # these params directly — not look for an S3 path.
    # Include both singular and plural forms so e.g. nf-core/proteinfold's
    # `protein_sequences` param gets auto-filled when a raw AA string is pasted.
    _SEQUENCE_PARAM_NAMES: frozenset = frozenset([
        'sequence', 'sequences',
        'protein_sequence', 'protein_sequences',
        'dna_sequence', 'dna_sequences',
        'rna_sequence', 'rna_sequences',
        'aa_sequence', 'aa_sequences',
        'nt_sequence', 'nt_sequences',
        'peptide_sequence', 'peptide_sequences',
        'query_sequence', 'query_sequences',
        'target_sequence', 'target_sequences',
        'input_sequence', 'input_sequences',
    ])

    # Params that hold chemical structure notations (SMILES, InChI, etc.)
    _SMILES_PARAM_NAMES: frozenset = frozenset([
        'smiles', 'compound_smiles', 'ligand_smiles', 'molecule_smiles',
        'smiles_string', 'drug_smiles',
    ])

    def _detect_param_type(self, name: str, default_val: str) -> str:
        """Heuristic type detection for a single Nextflow parameter.

        Returns one of: 'file' | 'sequence' | 'smiles' | 'boolean' |
                        'integer' | 'float' | 'string'
        """
        low = name.lower()
        # Sequence-text params — raw AA/NT strings, not file paths
        if low in self._SEQUENCE_PARAM_NAMES:
            return 'sequence'
        # Chemical-notation params
        if low in self._SMILES_PARAM_NAMES:
            return 'smiles'
        if low in self._INPUT_FILE_PARAM_NAMES or low.endswith('_file') or low.endswith('_path'):
            return 'file'
        if default_val in ('true', 'false', 'True', 'False'):
            return 'boolean'
        # Check numeric before file — "2.0" / "0.05" are floats, not file paths
        try:
            int(default_val); return 'integer'
        except (ValueError, TypeError):
            pass
        try:
            float(default_val); return 'float'
        except (ValueError, TypeError):
            pass
        if default_val and (
            default_val.startswith('/') or
            default_val.startswith('s3://') or
            default_val.startswith('gs://') or
            '.' in default_val.split('/')[-1]
        ):
            return 'file'
        return 'string'

    def _parse_nextflow_params(self, filename: str) -> dict:
        """Parse params.* lines from .nf file. Returns {"required": [...], "optional": [...]}.

        Section header comments of the form `// [Phase A] Description` assign a `group`
        field to each parameter so the UI can display them per-phase instead of globally.
        """
        import re as _re
        nf_path = self._find_nf_file(filename)
        if not nf_path:
            return {"required": [], "optional": []}
        try:
            text = nf_path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            return {"required": [], "optional": []}
        # Normalize DSL2 params { } block → flat params.xxx = value lines so the
        # regex below can parse them. Generated workflows used to emit block syntax;
        # flat syntax is now enforced in the LLM prompt but old cached files may still
        # have the block form. Prepend flattened entries so seen_names deduplication
        # keeps block-defined values when both forms appear in the same file.
        _block_re = _re.compile(r'\bparams\s*\{([^}]*)\}', _re.DOTALL)
        _block_entry_re = _re.compile(r'^\s*([a-zA-Z_]\w*)\s*=\s*(.+)$')
        _flat_extra: list = []
        for _bm in _block_re.finditer(text):
            for _bline in _bm.group(1).splitlines():
                _em = _block_entry_re.match(_bline)
                if _em:
                    _flat_extra.append(f'params.{_em.group(1)} = {_em.group(2).rstrip()}')
        if _flat_extra:
            text = '\n'.join(_flat_extra) + '\n' + text

        required, optional, data_inputs = [], [], []
        seen_names: set = set()
        section_re = _re.compile(r'//\s*\[([A-Za-z][A-Za-z0-9 _-]*)\]')
        param_re = _re.compile(r'^\s*params\.(\w+)\s*=\s*(.+)$')
        current_group: Optional[str] = None
        # A default the workflow's own comment calls test/example/demo data is an EXAMPLE input
        # (shown as 示例, never as a recommendation, and never as something the user supplied).
        _example_re = _re.compile(r'\b(test|example|demo|sample)\s+(data|input|inputs|compounds?|molecules?|sequences?|smiles|values?)\b', _re.I)
        prev_comment = ''  # the whole comment block directly above the current line
        for line in text.splitlines():
            _stripped = line.strip()
            if _stripped.startswith('//'):
                prev_comment = (prev_comment + ' ' + _stripped).strip()
            elif _stripped.startswith('params.'):
                pass  # the block applies to this param; reset after it (below)
            else:
                prev_comment = ''
            # Detect section header: // [Phase A] ... or // [Global] ...
            sec_m = section_re.search(line)
            if sec_m and line.strip().startswith('//'):
                raw_sec = sec_m.group(1).strip()
                if raw_sec.lower().startswith('phase '):
                    current_group = raw_sec.split()[-1].upper()
                elif raw_sec.lower() in ('global', 'infrastructure', 'performance', 'advanced'):
                    current_group = 'global'
                else:
                    current_group = raw_sec
                continue
            m = param_re.match(line)
            if not m:
                continue
            name = m.group(1)
            if name in seen_names:
                continue  # first declaration wins (top-level params block)
            # Separate inline comment from value — preserve comment as description
            raw_with_comment = m.group(2).strip()
            comment_m = _re.search(r'//\s*(.+)$', raw_with_comment)
            inline_desc = comment_m.group(1).strip() if comment_m else ''
            raw = _re.sub(r'\s*//.*$', '', raw_with_comment).strip()
            val_raw = raw
            if name in self._NEXTFLOW_INTERNAL_PARAMS:
                # Executor-owned required data inputs still surface as data_inputs
                # (never editable params) — mirrors _parse_nextflow_schema.
                if (
                    name in ('input', 'samplesheet', 'reads')
                    and val_raw == "null"
                    and name not in self._OPTIONAL_NULL_PARAMS
                    and _null_required(text, name)
                ):
                    data_inputs.append({
                        'name': name,
                        'label': self._EXECUTOR_DATA_INPUT_LABELS.get(
                            name, name.replace('_', ' ').title()),
                        'description': (inline_desc or '')[:200],
                        'required': True,
                        'executor_bound': True,
                    })
                    seen_names.add(name)
                continue
            label = name.replace("_", " ").title()
            description = inline_desc if inline_desc else f"Workflow parameter: {label}"
            # A param is truly required only if it's null AND not in the known-optional set.
            # ...and the workflow's own code does not handle its absence (nf_param_requirement).
            # Clinic hard primary data (movies_path, samplesheet, matrix, …) stay required
            # even when the .nf elvis-falls-back to test_data (nf_param_requirement demo rule).
            is_required = (
                (val_raw == "null")
                and (name not in self._OPTIONAL_NULL_PARAMS)
                and (
                    name in self._CLINIC_HARD_REQUIRED_DATA
                    or _null_required(text, name)
                )
            )
            # null-default params get Python None (renders as empty in UI), not the string "null"
            default_str = None if (is_required or val_raw == "null") else val_raw.strip("'\"")
            # iGenomes key is a string build ID even when default is null
            if name.lower() in self._IGENOMES_KEY_PARAM_NAMES:
                param_type = 'string'
            else:
                param_type = self._detect_param_type(name, default_str or "")
            if param_type == 'boolean' and default_str in ('true', 'True'):
                default_str = True
            elif param_type == 'boolean' and default_str in ('false', 'False'):
                default_str = False
            # Pipe-separated options in the trailing comment → select enum
            # (e.g. "Reference genome: GRCh38 | GRCm39 | …")
            allowed_values: list = []
            if inline_desc and '|' in inline_desc:
                options_part = inline_desc.split(':')[-1] if ':' in inline_desc else inline_desc
                raw_opts = [o.strip() for o in options_part.split('|') if o.strip()]
                if raw_opts and all(len(o) <= 40 and ' ' not in o.split('(')[0].strip() for o in raw_opts):
                    allowed_values = [o.split('(')[0].strip() for o in raw_opts]
                    if allowed_values:
                        param_type = 'select'
            entry: dict = {
                "name": name,
                "label": label,
                "description": description,
                "type": param_type,
                "default": default_str,
            }
            if allowed_values:
                entry['options'] = [{'label': v, 'value': v} for v in allowed_values]
            if default_str not in (None, '', True, False) and (_example_re.search(inline_desc) or _example_re.search(prev_comment)):
                entry["example"] = True
            prev_comment = ''
            if current_group:
                entry["group"] = current_group
            seen_names.add(name)
            if is_required:
                required.append(entry)
            else:
                optional.append(entry)

        # ── Style-A declared data inputs ────────────────────────────────────
        # Bioconductor-style subworkflows declare their data file via a code
        # header (`// Input: patient_clinical_data.csv`) rather than a config
        # file-param, so the loop above found NO file param and the workflow
        # panel showed "no data inputs to bind" even though the workflow needs
        # a data file. Surface each declared token as an OPTIONAL file-type
        # param so the viewer's existing file-picker logic (type == 'file')
        # renders a picker. OPTIONAL (not required) so one-click/no-input demo
        # workflows — which fall back to a placeholder in the executor — are
        # NOT newly blocked. Named by the declared base token so the executor's
        # Style-A staging (nextflow_executor._build_bioc_entry_wrapper →
        # params.get(name) / base-name fallback) binds the uploaded file.
        # Dedup: skip a token already covered by a real config file-param
        # (<base>, <base>_path, <base>_ref) so there are no double rows.
        _input_decl = _re.search(r'(?m)^\s*//\s*Input:\s*(.+?)\s*$', text)
        if _input_decl:
            _decl_tokens = [
                _re.split(r'\s*\(', _t)[0].strip()
                for _t in _re.split(r'[,\s]+', _input_decl.group(1))
                if _t.strip()
            ]
            for _tok in _decl_tokens:
                # `input_files` is the vestigial stageAs:'?/*' slot, not a
                # user-facing data file — never surface it as a picker.
                if not _tok or _tok == "input_files":
                    continue
                # Base token: drop a trailing short extension (.csv/.rds/.txt…)
                # to match the executor's base-name resolution. Dotless tokens
                # (e.g. `sce2`) are used verbatim.
                _base = _tok
                _mext = _re.search(r'\.([A-Za-z0-9]{1,6})$', _tok)
                if _mext:
                    _base = _tok[: _mext.start()]
                if not _base or any(
                    _k in seen_names
                    for _k in (_base, _tok, _base + "_path", _base + "_ref")
                ):
                    continue
                seen_names.add(_base)
                optional.append({
                    "name": _base,
                    "label": _base.replace("_", " ").title(),
                    "description": "Data input file read by the workflow",
                    "type": "file",
                    "default": None,
                    "data_input": True,
                })

        out = {"required": required, "optional": optional}
        if data_inputs:
            out["data_inputs"] = data_inputs
        return out

    # iGenomes / assembly key params — string build IDs (GRCh38), never file paths
    # unless the schema explicitly declares format=file-path.
    _IGENOMES_KEY_PARAM_NAMES: frozenset = frozenset([
        'genome', 'genome_build', 'genome_id', 'assembly',
    ])

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
        low = name.lower()
        # Bare `genome` in nf-core schemas is the iGenomes key, not a FASTA path.
        if low in self._IGENOMES_KEY_PARAM_NAMES and fmt not in ('file-path', 'file-path-pattern'):
            return 'string'
        # Heuristic for unformatted strings that look like file inputs
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
        from pathlib import Path as _Path
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
        data_inputs: list = []  # executor-owned required data inputs (see below)
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
                if param_name in self._NEXTFLOW_INTERNAL_PARAMS:
                    # Executor-owned, but a REQUIRED data input is still a requirement the user
                    # must meet (files or an accession). Describe it — never as an editable
                    # param: the executor builds it (fetchngs samplesheet / upload wiring).
                    if param_name in group_required and self._is_schema_data_input(param_name, param_def):
                        data_inputs.append({
                            'name': param_name,
                            'label': self._EXECUTOR_DATA_INPUT_LABELS.get(param_name, param_name.replace('_', ' ').title()),
                            'description': (param_def.get('description') or param_def.get('help_text') or '')[:200],
                            'required': True,
                            'executor_bound': True,
                        })
                    continue

                ptype = self._schema_type_to_param_type(param_name, param_def)
                default = param_def.get('default', None)
                # JSON Schema booleans are already Python bools; strings need no conversion
                # since nf-core schemas emit native JSON true/false for boolean defaults.

                description = param_def.get('description', '') or ''
                help_text = param_def.get('help_text', '')
                # Keep description short for UI; put help_text in description if no description
                full_description = description or help_text

                # Schema `required: []` is common on stubs (differentialabundance);
                # clinic primary data with no usable default is still required.
                _clinic_hard = (
                    param_name in self._CLINIC_HARD_REQUIRED_DATA
                    and (default is None or default == '')
                )
                is_required = param_name in group_required or _clinic_hard
                entry: dict = {
                    'name': param_name,
                    'label': param_name.replace('_', ' ').title(),
                    'description': full_description,
                    'type': ptype,
                    'default': default,
                    'group': group_title,
                    'required': is_required,
                }
                if self._is_schema_data_input(param_name, param_def) or _clinic_hard:
                    entry['data_input'] = True

                if 'enum' in param_def:
                    entry['options'] = [{'label': str(v), 'value': v} for v in param_def['enum']]
                if 'minimum' in param_def:
                    entry['minimum'] = param_def['minimum']
                if 'maximum' in param_def:
                    entry['maximum'] = param_def['maximum']
                if 'pattern' in param_def:
                    entry['pattern'] = param_def['pattern']

                if is_required:
                    required_params.append(entry)
                else:
                    optional_params.append(entry)

        if not required_params and not optional_params:
            return None  # schema was empty or all groups skipped — fall back
        return {'required': required_params, 'optional': optional_params, 'data_inputs': data_inputs}

    def _get_workflow_params(self, filename: str) -> dict:
        """Get parameter metadata for a workflow.

        Tries nextflow_schema.json (nf-core) first for authoritative types, groups, enums,
        and min/max constraints. Falls back to parsing params.* from the .nf file when no
        schema is found (custom drug-discovery workflows).
        """
        schema_params = self._parse_nextflow_schema(filename)
        if schema_params is not None:
            return schema_params
        return self._reconcile_required_with_executed_schema(
            filename, self._parse_nextflow_params(filename)
        )

    def _reconcile_required_with_executed_schema(self, filename: str, params: dict) -> dict:
        """Take required-ness, declared params and defaults from the pipeline that actually runs.

        See galaxy.ai.executed_schema. The stub's curated entries are kept for display, demoted
        to optional when the executed pipeline does not require them; entries for params the
        executed pipeline does not declare are dropped (Nextflow would ignore or reject them);
        defaults are the pipeline's own (a stub default sent on the CLI overrides the pipeline's
        config and its -profile, e.g. add_decoys=true on a target-decoy database); schema-
        required params the stub lacks are added.
        """
        from galaxy.ai.executed_schema import executed_pipeline_params  # noqa: PLC0415
        got = executed_pipeline_params(filename)
        if got is None:
            return params
        req_names, props, known, defaults = got['required'], got['props'], got['known'], got['defaults']
        required, optional = [], []
        for p in list(params.get('required', [])) + list(params.get('optional', [])):
            name = p.get('name')
            if name not in known:
                continue
            entry = dict(p, required=name in req_names)
            if name in defaults:
                entry['default'] = defaults[name]
            (required if entry['required'] else optional).append(entry)
        have = {p.get('name') for p in required}
        for name in sorted(req_names - have):
            d = props.get(name, {})
            required.append({
                'name': name,
                'label': name.replace('_', ' ').title(),
                'description': d.get('description') or d.get('help_text') or '',
                'type': self._schema_type_to_param_type(name, d),
                'default': defaults.get(name, d.get('default')),
                'required': True,
            })
        return {'required': required, 'optional': optional}

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

    # Organism / vernacular → canonical nf-core iGenomes key (rule-based; no LLM).
    _ORGANISM_GENOME_PATTERNS: tuple = (
        (r'\b(GRCh38|hg38|GRCh38\.p\d+)\b', 'GRCh38'),
        (r'\b(GRCh37|hg19|GRCh37\.p\d+)\b', 'GRCh37'),
        (r'\b(GRCm39|mm39)\b', 'GRCm39'),
        (r'\b(GRCm38|mm10|GRCm38\.p\d+)\b', 'GRCm38'),
        (r'\bhuman\b|\bhomo\s+sapiens\b', 'GRCh38'),
        (r'\bpatient\b|\bclinical\s+(?:trial|sample|cohort|specimen)\b', 'GRCh38'),
        (r'\bmouse\b|\bmurine\b|\bmus\s+musculus\b', 'GRCm39'),
        (r'\brat\b|\brattus\s+norvegicus\b', 'Rnor_6.0'),
        (r'\bzebrafish\b|\bdanio\s+rerio\b', 'GRCz11'),
        (r'\bdrosophila\b|\bfruit\s*fly\b', 'BDGP6'),
        (r'\byeast\b|\bsaccharomyces\b', 'R64-1-1'),
    )

    def _extract_genome_build(self, user_intent: str) -> Optional[str]:
        """Return a canonical iGenomes / nf-core genome key from the user's message.

        Prefer explicit build IDs, then organism vernacular (human → GRCh38). Returns
        the nf-core form (GRCh38) so select enums on rnaseq stubs match; igenomes S3
        lookups lower-case the key.
        """
        if not user_intent:
            return None
        for pattern, genome_id in self._ORGANISM_GENOME_PATTERNS:
            if re.search(pattern, user_intent, re.IGNORECASE):
                return genome_id
        m = self._GENOME_BUILD_RE.search(user_intent)
        if not m:
            return None
        raw = m.group(1)
        canon = {
            'hg38': 'GRCh38', 'grch38': 'GRCh38',
            'hg19': 'GRCh37', 'grch37': 'GRCh37',
            'mm10': 'GRCm38', 'grcm38': 'GRCm38',
            'mm39': 'GRCm39', 'grcm39': 'GRCm39',
        }
        return canon.get(raw.lower(), raw)

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

        _key = (genome_build or '').lower()
        # Accept both GRCh38 and hg38 style keys in the igenomes path tables.
        _path_aliases = {
            'grch38': 'grch38', 'hg38': 'hg38',
            'grch37': 'grch37', 'hg19': 'hg19',
            'grcm38': 'mm10', 'mm10': 'mm10',
            'grcm39': 'mm39', 'mm39': 'mm39',
        }
        _path_key = _path_aliases.get(_key, _key)
        ref_path = self._IGENOMES_REFERENCE.get(_path_key) or self._IGENOMES_REFERENCE.get(_key)
        ks_path = self._IGENOMES_KNOWN_SITES.get(_path_key) or self._IGENOMES_KNOWN_SITES.get(_key)
        # UCSC-style aliases some schemas declare instead of GRCh*
        _ucsc_alias = {
            'grch38': 'hg38', 'grch37': 'hg19', 'grcm38': 'mm10', 'grcm39': 'mm39',
        }

        def _genome_value_for(p: dict) -> str:
            """Pick a value that matches the param's enum when present."""
            options = p.get('options') or []
            vals = [
                (o.get('value') if isinstance(o, dict) else o)
                for o in options
            ]
            vals = [v for v in vals if v is not None]
            if not vals:
                return genome_build
            for candidate in (genome_build, _ucsc_alias.get(_key), genome_build.lower(), _key):
                if not candidate:
                    continue
                for v in vals:
                    if str(v).lower() == str(candidate).lower():
                        return v
            return genome_build

        def _patch(p: dict) -> dict:
            n = p['name']
            if n in _REFERENCE_NAMES and not p.get('default') and ref_path:
                return {**p, 'default': ref_path, 'value': ref_path, 'genome_auto': True}
            if n in _KNOWN_SITES_NAMES and not p.get('default') and ks_path:
                return {**p, 'default': ks_path, 'value': ks_path, 'genome_auto': True}
            if n in _GENOME_NAMES and not p.get('default'):
                gv = _genome_value_for(p)
                return {**p, 'default': gv, 'value': gv, 'genome_auto': True}
            return p

        return [_patch(p) for p in req_params], [_patch(p) for p in opt_params]

    def _build_prereq_validation(self, required_params: list) -> Optional[dict]:
        """Build prerequisitesValidation payload consumed by prereq-normalizer.ts.
        Excludes params that have a pre-filled default (e.g. SRR accession injected) from
        missingParameters — those are provided by the user and do not block the Run button."""
        # A param is truly missing only when it has neither a default NOR a pre-filled value.
        # The 'value' field is set by AI extraction (e.g. movies_path from user query) and
        # is distinct from 'default' which comes from the .nf file's params.* declaration.
        truly_missing = [p for p in required_params if not p.get('default') and not p.get('value')]
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

    def _bind_uploaded_datasets_to_params(
        self,
        req: list,
        opt: list,
        uploaded_datasets: Optional[List[Dict[str, Any]]],
    ) -> tuple:
        """Bind session uploads to unfilled file parameters without an LLM.

        This is intentionally conservative: it only fills an input when the
        filename gives a clear semantic match (for example count matrix →
        ``matrix`` and sample metadata → ``samplesheet``).  The former LLM-only
        path made an otherwise runnable bulk-DE request randomly lose its count
        matrix and metadata when the model was unavailable.
        """
        if not uploaded_datasets:
            return req, opt

        def _dataset_value(dataset: Dict[str, Any]) -> str:
            for key in ("s3_uri", "file_path", "path", "uri", "source_url"):
                value = dataset.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
            return ""

        files = [
            {"name": str(d.get("name") or _dataset_value(d).rsplit("/", 1)[-1]).lower(), "value": _dataset_value(d)}
            for d in uploaded_datasets
            if isinstance(d, dict) and _dataset_value(d)
        ]
        if not files:
            return req, opt

        # High-confidence filename cues, ordered from most specific to least.
        cues = {
            "matrix": ("matrix", "count", "featurecount", "htseq", "expression"),
            "counts": ("matrix", "count", "featurecount", "htseq", "expression"),
            "count_matrix": ("matrix", "count", "featurecount", "htseq", "expression"),
            "samplesheet": ("samplesheet", "sample", "metadata", "coldata", "design"),
            "sample_sheet": ("samplesheet", "sample", "metadata", "coldata", "design"),
            "metadata": ("metadata", "sample", "coldata", "design"),
            "sample_metadata": ("metadata", "sample", "coldata", "design"),
            "coldata": ("coldata", "metadata", "sample", "design"),
            "design": ("design", "metadata", "sample", "coldata"),
            "contrasts": ("contrast", "comparison"),
            "contrast": ("contrast", "comparison"),
            # Bioconductor Style-A declared inputs (coldstart Batch G)
            "patient_clinical_data": ("clinical", "patient", "survival", "cohort", "pbc"),
            "proteingroups": ("proteingroups", "protein_groups", "lfq"),
            "transcriptome": ("transcriptome", "transcript", "mrna", "rna"),
            "proteome": ("proteome", "protein", "proteomic"),
            "metabolome": ("metabolome", "metabol", "hmdb", "lipid"),
            "gene_summary": ("gene_summary", "rra.gene"),
            "sgrna_summary": ("sgrna_summary", "rra.sgrna"),
        }
        suggestions = []
        used_values: set = set()
        for param in req + opt:
            name = str(param.get("name") or "")
            if not name or param.get("default") not in (None, "") or param.get("value") not in (None, ""):
                continue
            name_l = name.lower()
            # Exact stem / basename match first (patient_clinical_data.csv → patient_clinical_data)
            exact = next(
                (
                    f for f in files
                    if f["value"] not in used_values
                    and (
                        f["name"] == name_l
                        or f["name"].rsplit(".", 1)[0] == name_l
                        or f["name"] == f"{name_l}.csv"
                        or f["name"] == f"{name_l}.txt"
                        or f["name"] == f"{name_l}.tsv"
                    )
                ),
                None,
            )
            if exact:
                suggestions.append({
                    "name": name,
                    "value": exact["value"],
                    "rationale": f"Exact filename match '{exact['name']}' → {name}.",
                })
                used_values.add(exact["value"])
                continue
            terms = cues.get(name_l)
            if not terms:
                continue
            match = next((f for f in files if f["value"] not in used_values and any(term in f["name"] for term in terms)), None)
            if match:
                suggestions.append({
                    "name": name,
                    "value": match["value"],
                    "rationale": f"Matched uploaded file '{match['name']}' to {name}.",
                })
                used_values.add(match["value"])
        return self._apply_llm_suggestions(req, opt, suggestions)

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

    _PARAM_SUGGEST_SYSTEM = """You are a scientific parameter extraction assistant for a bioinformatics platform.

Your job: given a workflow name, parameter list, and user query, extract parameter values the user explicitly provided or that can be unambiguously inferred.

EXTRACTION RULES (apply in order):
1. PATHS AND URLS — highest priority. If the query contains s3://, gs://, or a filesystem path AND the parameter list has a file-type param, match each path to the most appropriate parameter using the parameter name AND description. For example: a file named "featureCounts.txt" or with "matrix" in the name → param named "matrix" (if available); a metadata/samplesheet file (.xlsx, .csv with sample info) → param named "input", "samplesheet", or "contrasts"; a .fastq/.bam file → "reads" or "input"; a .mrc/.tif file → "movies_path". Match by filename semantics, not just extension. Never fabricate a path.
2. NUMERIC SCALARS — extract values like "pixel_size=0.885", "voltage=300 kV" (strip units), "1.96 Å/px" → 1.96.
3. IDENTIFIERS — PDB codes (4 chars), SMILES strings, gene symbols, accession numbers — copy exactly.
4. RAW SEQUENCES — if the query contains a long amino-acid or nucleotide string (e.g. MVLSEGEWQL...) AND the param list has a param of type 'sequence', copy the sequence there verbatim. Never put a raw sequence into a 'file' type param.
5. ENUM SELECTION — map user language to an allowed enum value: "XP docking" → "XP", "de novo" → "de_novo".
6. BOOLEAN FLAGS — "use GPU" → gpu=true, "single-end" → single_end=true.
7. UNIT CONVERSION — "37°C" → temperature=310 (Kelvin), "ns" → n_steps=N×500 (fs timestep).

SKIP a parameter if:
- Its value equals the [current: X] default shown (no change needed).
- You would have to guess or infer beyond what the user actually said.
- It is a path/URL and no path appears in the query.
- It is a 'file' type and no file/path appears in the query.
- It is a 'sequence' type and no raw AA/NT sequence appears in the query.

OUTPUT: JSON array only — no prose. Max 6 entries. Format:
[{"name": "param_name", "value": <value>, "rationale": "one sentence"}]
Return [] if nothing qualifies.

EXAMPLES:
Query: "Run CryoSPARC on s3://my-bucket/empiar/movies pixel_size=0.885 symmetry=D2"
→ [{"name":"movies_path","value":"s3://my-bucket/empiar/movies","rationale":"S3 path in query"},
   {"name":"pixel_size","value":0.885,"rationale":"explicit pixel_size"},
   {"name":"symmetry","value":"D2","rationale":"explicit symmetry"}]

Query: "analyze KRAS G12C mutation in lung cancer patients, PDB 6OIM"
→ [{"name":"receptor_pdb","value":"6OIM","rationale":"explicit PDB ID"},
   {"name":"target_gene","value":"KRAS","rationale":"mutation specified"}]

Query: "RNA-seq on human samples, 150bp paired-end reads, stranded dUTP"
→ [{"name":"read_length","value":150,"rationale":"explicit read length"},
   {"name":"strandedness","value":"reverse","rationale":"dUTP protocol = reverse strand"}]

Query (differentialabundance): "Run DE analysis. [Uploaded datasets: featureCounts.txt: s3_uri=s3://storage/uploads/abc/featureCounts.txt; coldata.xlsx: s3_uri=s3://storage/uploads/abc/coldata.xlsx]"
→ [{"name":"matrix","value":"s3://storage/uploads/abc/featureCounts.txt","rationale":"featureCounts.txt is a count matrix file → matrix param"},
   {"name":"input","value":"s3://storage/uploads/abc/coldata.xlsx","rationale":"coldata.xlsx is sample metadata → input samplesheet"}]

Query (differentialabundance): "Run DESeq2 on these MG files. [Uploaded datasets: counts_matrix.csv: s3_uri=s3://storage/uploads/xyz/counts_matrix.csv; sample_metadata.csv: s3_uri=s3://storage/uploads/xyz/sample_metadata.csv; contrasts.csv: s3_uri=s3://storage/uploads/xyz/contrasts.csv]"
→ [{"name":"matrix","value":"s3://storage/uploads/xyz/counts_matrix.csv","rationale":"counts_matrix.csv contains gene×sample counts → matrix param"},
   {"name":"input","value":"s3://storage/uploads/xyz/sample_metadata.csv","rationale":"sample_metadata.csv is the sample samplesheet (sample,condition,…) → input param"},
   {"name":"contrasts","value":"s3://storage/uploads/xyz/contrasts.csv","rationale":"contrasts.csv defines comparisons (id,variable,reference,target) → contrasts param"}]

FILE ACCESS RULE: Only use S3 URIs that appear inside an [Uploaded datasets:] block — these were provided by BioMate's upload system and are already accessible. If a user mentions an S3 path NOT in [Uploaded datasets:], do NOT assume it is accessible; instead respond: "To use files from an external location, please first upload them via the file upload button, or provide access credentials."

Query: "run on fixture:empiar-10028-movies pixel_size=0.885 voltage=300 symmetry=D2"
→ [{"name":"movies_path","value":"fixture:empiar-10028-movies","rationale":"demo fixture token in query (execute-time expands to staged movies)"},
   {"name":"pixel_size","value":0.885,"rationale":"explicit"},
   {"name":"voltage","value":300,"rationale":"explicit"},
   {"name":"symmetry","value":"D2","rationale":"explicit"}]"""

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

        # Build a compact param catalogue for the prompt
        all_params = req + opt
        # Gate params by what the query actually contains so the LLM doesn't
        # hallucinate values it can't derive:
        #   file      — only shown when an explicit path/URI is in the query
        #   sequence  — only shown when a long AA/NT string is in the query
        #   smiles    — only shown when a SMILES-pattern string is in the query
        #   all others — always shown
        import re as _re2
        _query_has_path = bool(_re2.search(
            r's3://|gs://|/[a-zA-Z]|\.(?:mrc|tif|eer|dm4|fastq|fq|bam|vcf|csv|tsv|xlsx|fasta|fa)',
            user_intent))
        _query_has_raw_seq = bool(_re2.search(
            r'\b[ACDEFGHIKLMNPQRSTVWY]{15,}\b', user_intent, _re2.IGNORECASE))
        _query_has_smiles = bool(_re2.search(
            r'(?:^|\s)([A-Za-z0-9@+\-\[\]()=#$]{6,}(?:[A-Z][a-z]?|\d){2,})',
            user_intent))
        inferable = [
            p for p in all_params
            if (
                p.get("type") not in ("file", "sequence", "smiles")
                or (_query_has_path and p.get("type") == "file")
                or (_query_has_raw_seq and p.get("type") == "sequence")
                or (_query_has_smiles and p.get("type") == "smiles")
            )
        ]
        if not inferable:
            return []

        # Cap the catalogue: prioritise file params + required-with-no-default + first N optional.
        # Large nf-core schemas (100+ params) degrade LLM inference — the signal is in the top ~30.
        _MAX_PARAMS = 30
        if len(inferable) > _MAX_PARAMS:
            _file_and_req = [p for p in inferable if p.get("type") == "file" or not p.get("default")]
            _rest = [p for p in inferable if p not in _file_and_req]
            inferable = (_file_and_req + _rest)[:_MAX_PARAMS]

        param_lines = []
        for p in inferable:
            name = p["name"]
            ptype = p.get("type", "string")
            desc = p.get("description", "")[:120]
            enum_vals = [str(o["value"]) for o in p.get("options", [])] if p.get("options") else None
            # Show current default so the LLM knows what would need to be overridden
            current_default = p.get("default") or p.get("value")
            default_note = f' [current: {current_default}]' if current_default is not None else ' [required]'
            if enum_vals:
                param_lines.append(f'- {name} (select: {"|".join(enum_vals)}){default_note}: {desc}')
            else:
                param_lines.append(f'- {name} ({ptype}){default_note}: {desc}')

        params_text = "\n".join(param_lines)
        # Include the full [Uploaded datasets:] block (may appear after first 600 chars)
        import re as _re_llm
        _uploaded_block = _re_llm.search(r'\[Uploaded datasets:[^\]]*\]', user_intent)
        _uploaded_suffix = f"\n{_uploaded_block.group(0)}" if _uploaded_block else ""

        # Sniff S3 file content to help LLM understand what each file contains.
        # Reading the first few lines is more reliable than guessing from filename.
        _file_snippets: list = []
        if _uploaded_block:
            _s3_uris = _re_llm.findall(r's3_uri=(s3://[^\s;,\]]+)', _uploaded_block.group(0))
            for _uri in _s3_uris[:4]:  # cap at 4 files
                _uri = _uri.rstrip('.,;)]')
                _fname = _uri.rsplit('/', 1)[-1]
                _ext = _fname.rsplit('.', 1)[-1].lower() if '.' in _fname else ''
                if _ext in ('txt', 'tsv', 'csv', 'fasta', 'fa', 'gff', 'gtf', 'vcf', 'bed'):
                    try:
                        import subprocess as _sp
                        _head = _sp.run(
                            ['aws', 's3', 'cp', _uri, '-'],
                            capture_output=True, timeout=10,
                        )
                        if _head.returncode == 0:
                            _lines = _head.stdout.decode('utf-8', errors='replace').split('\n')[:3]
                            _snippet = '\n'.join(l[:120] for l in _lines if l.strip())
                            if _snippet:
                                _file_snippets.append(f"File '{_fname}' first lines:\n{_snippet}")
                    except Exception:
                        pass  # non-blocking; LLM will use filename heuristic as fallback

        _file_context = ("\n\nFile previews:\n" + "\n---\n".join(_file_snippets)) if _file_snippets else ""

        user_msg = (
            f"Workflow: {workflow_name}\n\n"
            f"Available parameters:\n{params_text}\n\n"
            f"User query: {user_intent[:600]}{_uploaded_suffix}"
            f"{_file_context}"
        )

        try:
            # Route through the resilient fallback LLM client (Gemini primary →
            # Claude → …) instead of calling gemini_flash directly: deploy.sh
            # images lack the google SDK ("No module named 'google'"), so the
            # direct call hard-failed with NO fallback — dropping every extracted
            # param (SMILES, gene, PDB id). Fold the system prompt into the user
            # message since the fallback path uses a generic system role.
            from .llm_client import LLMClient  # noqa: PLC0415
            _ps_prompt = f"{self._PARAM_SUGGEST_SYSTEM}\n\n{user_msg}"
            text = LLMClient(self.config).call(
                messages=[{"role": "user", "content": _ps_prompt}],
                max_tokens=1024,  # S3 URIs can be long; 512 causes truncation
                use_fast_model=True,
            ).strip()
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
            suggestions = [
                s for s in suggestions
                if isinstance(s, dict)
                and s.get("name") in valid_names
                and s.get("value") is not None
                and str(s.get("value", "")).strip() != ""
            ]
            # Resolve chemical names → SMILES for any SMILES-type params
            try:
                from galaxy.ai.federated_query import resolve_smiles_params
                suggestions = resolve_smiles_params(suggestions)
            except Exception as _resolve_exc:
                log.debug("[ParamSuggest] SMILES resolution skipped: %s", _resolve_exc)
            # Validation guardrail (CLAUDE.md extraction = rules + LLM + validation):
            # the LLM is fed the "[Uploaded datasets: name: dataset_id=<id>, ...,
            # s3_uri=<uri>]" block and sometimes copies a whole entry into a dataset/id
            # param value as "<id>, s3_uri=<uri>" / "<id>, galaxy_dataset_id=<gid>",
            # which then renders as a raw serialized object in the field (e.g. the cryo
            # "Dataset Id"). Keep only the leading id/uri token. The leading token is a
            # valid dataset reference (BioMate stages id->S3 at execute time), so the
            # executor input binding is unaffected — this only cleans the composite.
            for _s in suggestions:
                _v = _s.get("value")
                if isinstance(_v, str):
                    _m = _re_llm.match(r'^\s*(\S+?)\s*,\s*(?:s3_uri|galaxy_dataset_id|dataset_id|name)=', _v)
                    if _m:
                        _s["value"] = _m.group(1)
            return suggestions
        except Exception as exc:
            log.debug("[ParamSuggest] LLM inference failed: %s", exc)
            return []

    def _extract_explicit_params_from_query(
        self,
        user_intent: str,
        req: list,
        opt: list,
    ) -> list:
        """Extract explicit key=value param assignments from user query text.

        Handles patterns like:
          movies_path=/data/empiar10345/movies/
          pixel_size=0.83, symmetry=O
          cryosparc_license=f312a30e-63fc-11f0-8e36-e3c932851287.

        This supplements LLM inference for file-type params (which LLM skips) and
        for any param the user typed explicitly in the query.
        Returns list of {name, value} dicts.
        """
        import re as _re

        all_param_names = {p["name"] for p in req + opt}
        if not all_param_names:
            return []

        suggestions = []
        # Match: param_name=value  where value ends at comma, space, newline, or end-of-string
        pattern = _re.compile(
            r'\b(' + '|'.join(_re.escape(n) for n in all_param_names) + r')\s*=\s*([^\s,;]+)',
            _re.IGNORECASE,
        )
        for m in pattern.finditer(user_intent):
            name_lower = m.group(1).lower()
            value = m.group(2).rstrip('.,;')
            # Match case-insensitively to actual param name
            matched_name = next(
                (n for n in all_param_names if n.lower() == name_lower), None
            )
            if matched_name and value:
                suggestions.append({"name": matched_name, "value": value, "rationale": "Value provided explicitly in your query."})

        # Rule: map S3/local file paths in query to the most appropriate file-type params.
        # Covers all workflows, not just cryo-EM.
        _already_set = {s["name"] for s in suggestions}
        _path_re = _re.compile(r'\b(s3://\S+|gs://\S+|/(?:data|nfs|mnt|home|scratch)\S+)', _re.IGNORECASE)
        _all_paths = [m.group(1).rstrip('.,;)]') for m in _path_re.finditer(user_intent)]

        # Extension → candidate parameter names for UNAMBIGUOUS cases only.
        # Ambiguous extensions (.txt, .csv, .xlsx, .tsv) are left to LLM inference,
        # which sees both the workflow name and parameter descriptions.
        _EXT_TO_PARAMS: dict = {
            '.mrc': ['movies_path', 'movie_dir'],
            '.mrcs': ['movies_path', 'movie_dir'],
            '.tif': ['movies_path', 'movie_dir'],
            '.tiff': ['movies_path', 'movie_dir'],
            '.eer': ['movies_path', 'movie_dir'],
            '.dm4': ['movies_path', 'movie_dir'],
            '.fastq': ['reads', 'reads1', 'input'],
            '.fastq.gz': ['reads', 'reads1', 'input'],
            '.fq': ['reads', 'reads1', 'input'],
            '.fq.gz': ['reads', 'reads1', 'input'],
            '.bam': ['bam', 'input'],
            '.cram': ['bam', 'cram', 'input'],
            '.vcf': ['vcf', 'input'],
            '.vcf.gz': ['vcf', 'input'],
            '.fasta': ['fasta', 'genome', 'input'],
            '.fa': ['fasta', 'genome', 'input'],
            '.fa.gz': ['fasta', 'genome', 'input'],
            '.gtf': ['gtf', 'annotation'],
            '.gff': ['gtf', 'annotation', 'gff'],
            '.gff3': ['gff', 'annotation'],
            '.sdf': ['ligand_sdf', 'input'],
            '.pdb': ['receptor_pdb', 'input'],
            '.nwk': ['tree', 'input'],
            '.newick': ['tree', 'input'],
        }

        for _path in _all_paths:
            _path_lower = _path.lower()
            # Find matching extension
            _candidates: list = []
            for _ext, _param_list in sorted(_EXT_TO_PARAMS.items(), key=lambda x: -len(x[0])):
                if _path_lower.endswith(_ext):
                    _candidates = _param_list
                    break
            if not _candidates:
                continue  # unrecognized extension — let LLM inference handle it

            # Pick first candidate that exists in the workflow params and isn't already set
            _target = next((p for p in _candidates if p in all_param_names and p not in _already_set), None)
            if _target:
                suggestions.append({"name": _target, "value": _path, "rationale": f"File path found in query (mapped by extension)."})
                _already_set.add(_target)  # don't reuse same param for another file

        # Rule: map "SMILES: <value>" or "SMILES= <value>" to smiles_list param.
        # Generalizable: applies to any workflow with smiles_list (ADMET, docking, PKsim, etc.).
        # Using JSON-array format required by Groovy's JsonSlurper at workflow startup.
        # When smiles_list is the only required param, this causes _explicit_covers_required=True
        # which skips _infer_params_from_intent_llm — eliminating an LLM call that adds latency.
        import json as _json_smiles
        # Robust path (runs first): when the query is about chemistry and the
        # workflow takes a smiles_list, split the query and RDKit-validate every
        # candidate token. This captures a LIST of molecules — including short ones
        # like 'CCO' and natural phrasings ("screen these SMILES for hERG: CCO,
        # c1ccccc1") that the narrow 'SMILES:'-prefixed regex below misses. RDKit
        # rejects non-molecule words (hERG, rank, screen…), so it does not
        # false-positive. Falls through to the regex path if RDKit is unavailable.
        if 'smiles_list' in all_param_names and 'smiles_list' not in _already_set:
            _mentions_chem = bool(_re.search(
                r'\b(smiles|compound|molecul|ligand|screen|admet|dock|herg|scaffold)\b',
                user_intent, _re.IGNORECASE))
            if _mentions_chem:
                try:
                    from rdkit import Chem as _Chem
                    from rdkit import RDLogger as _RDLogger
                    _RDLogger.DisableLog('rdApp.*')  # quiet parse errors for non-SMILES tokens
                    _valid_smiles: list = []
                    for _tok in _re.split(r'[\s,;]+', user_intent or ""):
                        _tok = (_tok or "").strip().strip('.').rstrip(')')
                        if not _tok or not _re.fullmatch(r'[A-Za-z0-9@\[\]\(\)\+\-=#\/\\%.]{2,}', _tok):
                            continue
                        _mol = _Chem.MolFromSmiles(_tok)
                        if _mol is not None and _mol.GetNumAtoms() >= 2:
                            _canon = _Chem.MolToSmiles(_mol)
                            if _canon not in _valid_smiles:
                                _valid_smiles.append(_canon)
                    if _valid_smiles:
                        suggestions.append({
                            "name": "smiles_list",
                            "value": _json_smiles.dumps(_valid_smiles[:50]),
                            "rationale": f"{len(_valid_smiles)} SMILES RDKit-validated from the query.",
                        })
                        _already_set.add('smiles_list')
                except Exception as _rdkit_exc:  # RDKit missing → regex fallback below
                    log.debug("[ParamExtract] RDKit SMILES extraction skipped: %s", _rdkit_exc)
        if 'smiles_list' in all_param_names and 'smiles_list' not in _already_set:
            _smiles_m = _re.search(
                r'\bSMILES\s*[=:]\s*([A-Za-z0-9@\[\]\(\)\+\-=#\/\\\.%:]{8,})',
                user_intent,
                _re.IGNORECASE,
            )
            if _smiles_m:
                _smiles_raw = _smiles_m.group(1)
                # Strip unbalanced trailing ')' that sentence punctuation wrapping adds.
                _depth = 0
                _smiles_val = _smiles_raw
                for _i, _ch in enumerate(_smiles_raw):
                    if _ch == '(':
                        _depth += 1
                    elif _ch == ')':
                        if _depth == 0:
                            _smiles_val = _smiles_raw[:_i]
                            break
                        _depth -= 1
                suggestions.append({
                    "name": "smiles_list",
                    "value": _json_smiles.dumps([_smiles_val]),
                    "rationale": "SMILES string extracted from 'SMILES:' notation in query.",
                })
                _already_set.add('smiles_list')

        # Rule: extract raw AA or NT sequence from query → first unfilled 'sequence'-type param.
        # This is rule-based (no LLM) so it is zero-latency and 100% reliable.
        # Handles patterns like:
        #   "analyze MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR"
        #   "帮我跑一下：MVLSEGEWQLVLHVWAKVEADVAGHGQDILIR"
        # We look for the LONGEST contiguous run of AA/NT letters (≥15) in the query.
        # If the workflow has a sequence-type param that isn't already set, fill it.
        _seq_params_unfilled = [
            p for p in req + opt
            if self._detect_param_type(p.get("name", ""), str(p.get("default", "") or "")) == "sequence"
            and p.get("name") not in _already_set
        ]
        if _seq_params_unfilled:
            _AA_CHARS = r'[ACDEFGHIKLMNPQRSTVWYBZXU]'
            _seq_match = None
            _best_len = 0
            for _m in _re.finditer(rf'\b({_AA_CHARS}{{15,}})\b', user_intent, _re.IGNORECASE):
                if len(_m.group(1)) > _best_len:
                    _seq_match = _m.group(1)
                    _best_len = len(_seq_match)
            if _seq_match:
                # Fill ALL required sequence params with the found sequence.
                # Some workflows (e.g. nf-core/proteinfold) declare both `sequence`
                # and `protein_sequences` as null-required aliases for the same input —
                # filling only the first leaves the other blocking the Run button.
                # If there are NO required sequence params, fill the first optional one.
                _req_seq = [p for p in _seq_params_unfilled if p.get("required", True)]
                _opt_seq = [p for p in _seq_params_unfilled if not p.get("required", True)]
                for _sp in (_req_seq if _req_seq else _opt_seq[:1]):
                    suggestions.append({
                        "name": _sp["name"],
                        "value": _seq_match.upper(),
                        "rationale": "Amino-acid/nucleotide sequence extracted directly from your query.",
                    })
                    _already_set.add(_sp["name"])

        return suggestions

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
                    # Always override default with LLM suggestion — the user explicitly
                    # stated this value so it must override the schema default (pdb_id,
                    # ligand_smiles, box_center, exhaustiveness, etc.)
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
                # Build scientific_rationale from candidate workflows if available,
                # so the LLM can use tool-specific knowledge to ask better
                # differentiating questions on this clarification turn.
                _pipeline_clarif_rationale: dict = {}
                _candidates = terminal_state.get("workflow_candidates") or []
                _cand_tools: List[str] = []
                for _cand in _candidates[:3]:
                    _t = getattr(_cand, 'tools', None) or (
                        _cand.get('tools_used', []) if isinstance(_cand, dict) else []
                    )
                    for _tool in (_t or []):
                        if _tool not in _cand_tools:
                            _cand_tools.append(_tool)
                if _cand_tools:
                    _pipeline_clarif_rationale = self._build_scientific_rationale(
                        '', 'candidate workflows', _cand_tools
                    ) or {}
                _final_resp = terminal_state.get("final_response") or {}
                return {
                    "success": False,
                    "message": (
                        _final_resp.get("message")
                        or "Please clarify your request."
                    ),
                    "source": "clarification",
                    **({'scientific_rationale': _pipeline_clarif_rationale}
                       if _pipeline_clarif_rationale else {}),
                }
            log.warning("[run_via_pipeline] terminal state has no final_response, falling back")
            return self.generate_workflow_unified(user_intent, uploaded_datasets, user_id)
        except Exception as exc:
            log.warning("[run_via_pipeline] pipeline invocation failed: %s — falling back", exc)
            return self.generate_workflow_unified(user_intent, uploaded_datasets, user_id)

    # ── Example-data detection ──────────────────────────────────────────────
    # A workflow "runs on its own example data" when it can execute with NO user
    # input because its data inputs resolve to bundled/built-in example data. This
    # is a REAL property of the workflow DEFINITION (never a hard-coded list of
    # names), derived from the executed .nf:
    #   (B) a built-in example/demo DATA fallback keyed on the absence of a data
    #       param — the author's documented "merfish/voyager" pattern: a
    #       `def demo = ( !params.x )` guard, a demo_mode / input_is_demo /
    #       demo_used flag, a "built-in demo default" block, or a "param-less"
    #       quick run. These paths download/use REAL public data (chipseq CTCF,
    #       atac nf-core BAMs, chemoproteomics LFQ-Analyst, wsi OpenSlide,
    #       metaboanalystr human_cachexia); and/or
    #   (A) a data-input param whose default is itself bundled example data — a
    #       sample_data / test-data FILE PATH (flow cytometry's Accuri FCS) or an
    #       inline example-values literal (EBV's ELISA OD JSON).
    # It is NOT a synthetic/random generator (those draw values at runtime and are
    # blocked elsewhere); every path above is real, fixed, clearly-labelled data.
    _EXAMPLE_DATA_FALLBACK_RE = re.compile(
        r'\bdef\s+demo\s*=|\bdemo_mode\b|\binput_is_demo\b|\bdemo_used\b'
        r'|built-in demo default|param-?less',
        re.IGNORECASE,
    )
    _EXAMPLE_DATA_BUNDLED_PATH_RE = re.compile(
        r'params\.\w+\s*=\s*["\'][^"\']*'
        r'(?:sample_data|/test[-_/]|/testdata|example_data|openslide-testdata)'
        r'[^"\']*\.\w{2,6}["\']',
        re.IGNORECASE,
    )
    _EXAMPLE_DATA_INLINE_RE = re.compile(
        r'params\.\w*(?:data|od|elisa|readings|counts|matrix|titer)\w*'
        r'\s*=\s*[\'"]\s*[\[{]',
        re.IGNORECASE,
    )

    def _detect_example_data(self, filename: str) -> Optional[Dict[str, Any]]:
        """Return an example-data descriptor when the workflow runs on its own
        bundled example data with no user input, else None. Derived from the .nf
        definition (see the signal notes above) — never from the workflow name."""
        nf_path = self._find_nf_file(filename)
        if not nf_path:
            return None
        try:
            text = nf_path.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            return None
        has_fallback = bool(self._EXAMPLE_DATA_FALLBACK_RE.search(text))
        has_bundled = bool(self._EXAMPLE_DATA_BUNDLED_PATH_RE.search(text))
        has_inline = bool(self._EXAMPLE_DATA_INLINE_RE.search(text))
        if not (has_fallback or has_bundled or has_inline):
            return None
        return {
            'present': True,
            # One honest, storage-path-free sentence the reply can surface.
            'note': ("Runs on the workflow's built-in example dataset when no files "
                     "are attached — attach your own files to replace it."),
            'signals': {
                'fallback': has_fallback,
                'bundled_default': has_bundled,
                'inline_default': has_inline,
            },
        }

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
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
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
        # Executor-owned required data inputs: satisfied when this request carries data the
        # executor binds (an accession it fetches, or attached/uploaded files).
        _data_match = self._RUN_DATA_RE.search(user_intent or '')
        # bound_value: the public accession when that is what satisfies it (shown in the panel);
        # None for attached files (the panel says "provided in chat" in the UI language).
        _bound_value = _data_match.group(0) if _data_match and not _data_match.group(0).startswith('[') else None
        data_inputs = [{**d, 'bound': bool(_data_match), 'bound_value': _bound_value}
                       for d in nf_params.get('data_inputs', [])]
        # Example-data capability: does THIS workflow run on its own bundled example
        # data with no user input? A real property of the .nf definition (see
        # _detect_example_data). When present, the chat reply presents the card as
        # runnable on the example dataset instead of asking for an upload; the
        # frontend decides to surface it only when the request carries no user data.
        # When no run data was provided, mark any executor-owned data input as
        # satisfied-by-example so the panel shows it bound (not "required, not set").
        _example_data = self._detect_example_data(match.filename)
        if _example_data and not _data_match and not uploaded_datasets:
            data_inputs = [
                d if d.get('bound') else {**d, 'bound': True, 'bound_value': 'example dataset'}
                for d in data_inputs
            ]
        log.info(f"[_return_nextflow_match] filename={match.filename} req={len(req)} opt={len(opt)} "
                 f"opt_names={[p['name'] for p in opt]} example_data={bool(_example_data)}")
        sra = self._extract_sra_accession(user_intent)
        if sra:
            req, opt = self._inject_sra_into_params(req, opt, sra)
        genome = self._extract_genome_build(user_intent)
        if genome:
            req, opt = self._inject_genome_into_params(req, opt, genome)
        max_spots = self._extract_max_spots(user_intent)
        if max_spots:
            opt = self._inject_max_spots_into_params(opt, max_spots)
        # Layer 1a′: deterministic library-layout rules (paired-end → single_end=false).
        # Genome/organism aliases are handled above via _extract_genome_build.
        _rule_suggestions: list = []
        _param_names = {p.get('name') for p in req + opt}
        if 'single_end' in _param_names:
            if re.search(r'\bpaired[-\s]?end\b|\bPE\b|\bR1\b.*\bR2\b', user_intent or '', re.IGNORECASE):
                _rule_suggestions.append({
                    'name': 'single_end', 'value': False,
                    'rationale': 'rule-based: paired-end → single_end=false',
                })
            elif re.search(r'\bsingle[-\s]?end\b|\bSE\b', user_intent or '', re.IGNORECASE):
                _rule_suggestions.append({
                    'name': 'single_end', 'value': True,
                    'rationale': 'rule-based: single-end → single_end=true',
                })
        # Standing project-rule / prose FDR phrases when a significance param exists
        _fdr_names = [n for n in _param_names if re.search(r'fdr|padj|p_?adj|q_?val|alpha|max_qval', n or '', re.I)]
        if _fdr_names and re.search(r'\bFDR\b|\badjusted\s+p\b|\bp\s*adj|\bq\s*-?\s*val', user_intent or '', re.I):
            _m_fdr = re.search(r'(?:FDR|padj|p-?adj|q-?val|alpha)\s*[<≤=:]?\s*(0?\.\d+)', user_intent or '', re.I)
            if _m_fdr:
                _fv = float(_m_fdr.group(1))
                _rule_suggestions.append({
                    'name': _fdr_names[0], 'value': _fv,
                    'rationale': 'rule-based: significance threshold from query',
                })
        if _rule_suggestions:
            req, opt = self._apply_llm_suggestions(req, opt, _rule_suggestions)
        # Layer 2: apply DB-driven tool_knowledge hints
        hints = (scientific_rationale or {}).get('parameter_hints', [])
        req, opt = self._apply_parameter_hints(req, opt, hints)
        # Layer 1b: extract explicit key=value assignments from user query (covers file-type params
        # that LLM inference skips, and any param the user typed verbatim).
        explicit_suggestions = self._extract_explicit_params_from_query(user_intent, req, opt)
        req, opt = self._apply_llm_suggestions(req, opt, explicit_suggestions)
        # Layer 2: apply LLM intent-inferred suggestions (non-blocking).
        # Skip when the user already supplied explicit values (common in Plan B E2E / CLI
        # parity prompts) — gemini param inference can exceed the Node proxy timeout.
        _q_low = user_intent.lower()
        _explicit_registry_10813 = bool(
            re.search(r'\b10813\b', _q_low)
            or 'optimize_codons_for_heterologous_expression' in _q_low
        )
        _required_names = {p.get('name') for p in req if p.get('required', True)}
        _explicit_names = {s.get('name') for s in explicit_suggestions if s.get('name')}
        _explicit_covers_required = _required_names and _required_names.issubset(_explicit_names)
        _explicit_dock_12824 = bool(
            re.search(r'\b12824\b', _q_low)
            or 'docking_autodock_vina' in _q_low
            or 'autodock vina' in _q_low
        )
        _skip_param_llm = (
            _explicit_covers_required
            or _explicit_registry_10813
            or (_explicit_dock_12824 and 'pdb_input' in _q_low)
        )
        if not _skip_param_llm:
            llm_suggestions = self._infer_params_from_intent_llm(user_intent, match.name, req, opt)
            req, opt = self._apply_llm_suggestions(req, opt, llm_suggestions)
        # Session uploads are authoritative user inputs.  Bind clearly named
        # files deterministically after best-effort LLM inference so a transient
        # model failure cannot leave a bulk-DE matrix/samplesheet unbound.
        req, opt = self._bind_uploaded_datasets_to_params(req, opt, uploaded_datasets)
        citations = self._build_workflow_citations(match.tools, match.domain, match.tags)
        warnings = [] if not needs_user_feedback else [
            'Medium confidence match — please verify tool selection is appropriate'
        ]
        # CryoSPARC SPA has its own dedicated GPU executor — route it there
        _is_cryosparc = "cryosparc" in (match.filename or '').lower() or "cryosparc" in (match.name or '').lower()
        _wf_type = 'cryosparc' if _is_cryosparc else 'nextflow'
        _exec_engine = 'cryosparc' if _is_cryosparc else 'nextflow'
        # Build flat parameters dict for CryoSPARC execute endpoint.
        # File-path params (movies_path etc.) are NOT in the schema so Haiku skips them;
        # extract them directly from the raw user intent via regex.
        import re as _re
        _exec_params: dict = {}
        _is_cryo_em = _is_cryosparc or match.domain in ('cryo_em',) or 'cryo' in match.name.lower()
        if _is_cryosparc:
            for _kw in ('movies_path', 'movie_dir', 'pixel_size', 'num_movies'):
                _m = _re.search(rf'\b{_kw}\s*=\s*([^\s,;]+)', user_intent, _re.IGNORECASE)
                if _m:
                    _exec_params[_kw] = _m.group(1).rstrip('.,;')
        # Auto-inject movies_path from uploaded files for ALL cryo-EM workflows (CryoSPARC + Nextflow)
        if _is_cryo_em and not _exec_params.get('movies_path') and uploaded_datasets:
            _cryo_exts = ('.mrc', '.mrcs', '.tif', '.tiff', '.eer', '.dm4')
            for _ds in uploaded_datasets:
                _fp = _ds.get('file_path', '') or ''
                _nm = _ds.get('name', '') or ''
                if any((_fp.lower().endswith(ext) or _nm.lower().endswith(ext))
                       for ext in _cryo_exts):
                    _exec_params['movies_path'] = _fp or _nm
                    break
        if _is_cryosparc:
            for _p in req + opt:
                _pn = _p.get('name', '')
                _pv = _p.get('default') or _p.get('value')
                if _pn and _pv is not None:
                    _exec_params.setdefault(_pn, _pv)
        # workflow_ga.parameters must carry the rule/LLM-extracted values (SMILES,
        # gene, PDB id, …) for ALL workflows, not just cryosparc. Headless consumers
        # (connector execute_workflow, chat auto-execute) send workflow_ga straight
        # to /api/workflows/execute; without this they run with NO params and the
        # extracted value is dropped ([Nextflow Direct] Parameters: undefined).
        # BUT exclude INTERNAL config vars (e.g. _useAws, _ECR, CHEM_CONTAINER)
        # whose "default" is a Groovy/nextflow config EXPRESSION, not a literal.
        # These are resolved inside nextflow.config — passing them on the CLI as
        # `--_useAws "params.use_aws || System.getenv(...)"` makes Nextflow abort
        # at parse time ("Dynamic parameter expected a value of the form a=b")
        # → run dies instantly with zero output (e.g. cyp_ddi_panel, 2026-06-29).
        def _is_internal_param(_name, _val):
            if str(_name).startswith('_'):
                return True
            _s = str(_val)
            return ('params.' in _s) or ('System.getenv' in _s) or ('${' in _s)
        for _p in req + opt:
            _pn = _p.get('name', '')
            _pv = _p.get('default')
            if _pn and _pv not in (None, '') and not _is_internal_param(_pn, _pv):
                _exec_params.setdefault(_pn, _pv)
        return {
            'success': True,
            'nextflow_path': match.filename,
            'workflow_name': match.name,
            'workflow_type': _wf_type,
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
            'execution_engine': _exec_engine,
            'format': 'nextflow',
            'hardware_requirements': hardware_requirements,
            **({'qc_profile': qc_profile} if qc_profile else {}),
            'scientific_rationale': scientific_rationale,
            'workflow_ga': {
                'name': match.name,
                'description': match.description,
                'annotation': match.description,
                'tags': match.tags,
                'domain': match.domain,
                'format': 'nextflow',
                'nextflow_path': match.filename,
                'workflow_type': _wf_type,
                'steps': _eager_load_steps(match.filename),
                'scientific_rationale': scientific_rationale,
                'hardware_requirements': hardware_requirements,
                'required_params': req,
                'optional_params': opt,
                **({'data_inputs': data_inputs} if data_inputs else {}),
                **({'example_data': _example_data} if _example_data else {}),
                **({'parameters': _exec_params} if _exec_params else {}),
                **({'prerequisitesValidation': self._build_prereq_validation(req)} if req else {}),
            },
            'datasets_assigned': any(p.get('type') == 'file' and p.get('value') not in (None, '') for p in req + opt),
            'required_params': req,
            'optional_params': opt,
            **({'data_inputs': data_inputs} if data_inputs else {}),
            **({'example_data': _example_data} if _example_data else {}),
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
            **({'citations': citations} if citations else {}),
        }

    def _resolve_selected_workflow(self, selected: Dict[str, Any]) -> Optional[Any]:
        """Resolve a structured workflow selection to ONE catalog row, or None.

        Most specific identifier first: catalog id (only when its name agrees, so a stale id
        after a re-index cannot point at another workflow), exact nextflow_path, then the name
        (exact identifier forms via resolve_named_workflow, then case-insensitive exact name).
        No fuzzy search: a selection that does not resolve is reported, not approximated.
        """
        name = str(selected.get('name') or '').strip()
        path = str(selected.get('nextflow_path') or '').strip()
        wf_id = selected.get('id')
        search = self.workflow_search
        if isinstance(wf_id, int) or (isinstance(wf_id, str) and wf_id.isdigit()):
            m = search.get_workflow(int(wf_id))
            if m and (not name or (m.name or '').lower() == name.lower()):
                return m
        if path:
            m = search.get_workflow_by_filename_pattern(path)
            if m and (m.filename or '').lower() == path.lower():
                return m
        if name:
            return search.resolve_named_workflow(name) or search.get_workflow_by_name(name)
        return None

    def _generate_selected_workflow(
        self,
        selected: Dict[str, Any],
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """Card for the workflow the user explicitly selected (see generate_workflow_unified)."""
        label = selected.get('name') or selected.get('nextflow_path') or selected.get('id')
        try:
            top = self._resolve_selected_workflow(selected)
        except Exception as exc:  # noqa: BLE001 — reported to the caller, not swallowed
            log.warning("[UnifiedWorkflowGeneration] selected workflow lookup failed (%s): %s", label, exc)
            top = None
        if not top:
            log.warning("[UnifiedWorkflowGeneration] selected workflow not found / not executable: %s", label)
            return {
                'success': False,
                'error': f'selected_workflow_not_found: {label}',
                'message': f"The selected workflow '{label}' is not available in the catalog.",
            }
        log.info("[UnifiedWorkflowGeneration] User-selected workflow → %s (id=%s)", top.name, top.id)
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='user_selected',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    @staticmethod
    def _named_workflow_tokens(user_intent: str) -> List[str]:
        """Candidate workflow identifiers explicitly written in a request.

        snake_case tokens (``perform_chipseq_peak_calling_with_macs2``) and
        "the <name> workflow" phrases. File names (``counts_matrix.csv``), parameter
        keys (``min_fold_change=2``) and path fragments (``s3://bucket/raw_reads/``)
        are not identifiers and are skipped.
        """
        import re as _re_named

        low = (user_intent or '').lower()
        tokens: List[str] = []
        for m in _re_named.finditer(r'(?<![\w./-])([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(?![\w/-])', low):
            following = low[m.end():m.end() + 8]
            if _re_named.match(r'\.[a-z0-9]{1,5}\b', following) or _re_named.match(r'\s*[=:]', following):
                continue
            tokens.append(m.group(1))
        tokens += _re_named.findall(r'\bthe\s+([a-z][a-z0-9_]{5,})\s+workflow\b', low)
        return list(dict.fromkeys(tokens))

    def _try_fast_path_named_catalog_workflow(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route a request that explicitly names ONE catalog workflow to exactly that workflow.

        "Run perform_chipseq_peak_calling_with_macs2 using its built-in ... demo files" and
        "Run the metaboanalystr workflow ..." name the workflow outright. An explicit name is
        the strongest routing signal there is, so this runs before every keyword fast path
        and retrieval — which otherwise sent the ChIP-seq demo to nf-core/chipseq (needs real
        reads) and the metaboanalystr demo to a sibling workflow. Exactly one resolved
        workflow is required: none -> normal routing; two or more -> a multi-workflow
        request, left to chain/multi-intent routing. Explicit ``nf-core/<slug>`` mentions
        are left to _try_fast_path_nfcore_pipeline.
        """
        import re as _re_named

        # Only what the user wrote names a workflow. generate_workflow_unified appends
        # "[Memory context]" (workflow names from PAST corrections) and the API layer appends
        # "[Inline parameters: ...]"; neither may steer this request to a named workflow.
        request_text = _re_named.split(r'\n\s*\[(?:Memory context|Inline parameters:)', user_intent or '')[0]
        if _re_named.search(r'\bnf-core/[a-z]', request_text, _re_named.IGNORECASE):
            return None
        resolved: Dict[int, Any] = {}
        for token in self._named_workflow_tokens(request_text):
            match = self.workflow_search.resolve_named_workflow(token)
            if match:
                resolved.setdefault(match.id, match)
        if len(resolved) != 1:
            return None
        top = next(iter(resolved.values()))
        log.info(
            "[UnifiedWorkflowGeneration] Named-workflow fast path → %s (id=%d)", top.name, top.id
        )
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def _try_fast_path_explicit_codon_workflow(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Return codon optimization workflow without chain/LLM routing when registry 10813 is explicit.

        Plan B E2E and CLI parity prompts name optimize_codons_for_heterologous_expression with
        explicit parameters. The full unified path can exceed HTTP worker timeouts when LLM
        param inference or chain verification runs unnecessarily.
        """
        import re as _re_fast

        q_low = user_intent.lower()
        explicit_10813 = bool(
            _re_fast.search(r'\b10813\b', q_low)
            or 'optimize_codons_for_heterologous_expression' in q_low
        )
        if not explicit_10813:
            return None

        # Direct registry lookup — skip BGE embedding search (cold start can exceed
        # gunicorn worker timeout and fail Plan B E2E when Galaxy was just restarted).
        top = self.workflow_search.get_workflow(10813)
        if not top:
            results = self.workflow_search.search(user_intent, limit=3)
            if not results:
                return None
            top = results[0]
            top_fn = (top.filename or '').lower()
            if top.id != 10813 and 'optimize_codons' not in top_fn:
                return None
            results_list = results
        else:
            top_fn = (top.filename or '').lower()
            if 'optimize_codons' not in top_fn and top.id != 10813:
                return None
            results_list = [top]

        log.info(
            "[UnifiedWorkflowGeneration] Fast path registry 10813 → %s (score=%.1f)",
            top.name,
            top.score,
        )
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=results_list,
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def _try_fast_path_explicit_docking_workflow(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Return AutoDock Vina without BGE search when named without DiffDock."""
        import re as _re_dock

        q_low = user_intent.lower()
        explicit_vina = bool(
            _re_dock.search(r'\b12824\b', q_low)
            or 'docking_autodock_vina' in q_low
            or 'autodock vina' in q_low
        )
        if not explicit_vina:
            return None
        # When both AutoDock Vina AND DiffDock are requested, defer to virtual-screening path.
        if 'diffdock' in q_low:
            return None

        top = self.workflow_search.get_workflow_by_filename_pattern('%docking_autodock_vina%')
        if not top:
            top = self.workflow_search.get_workflow_by_name('Docking Autodock Vina')
        if not top:
            return None

        log.info("[UnifiedWorkflowGeneration] Fast path docking_autodock_vina → %s", top.name)
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def _try_fast_path_virtual_screening(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route compound-library virtual-screening queries (Vina + DiffDock) to drugclip_virtual_screening."""
        import re as _re_vs

        q_low = user_intent.lower()
        has_vina = bool(_re_vs.search(r'\bautodock\b|\bvina\b', q_low))
        has_diffdock = 'diffdock' in q_low
        has_screening = bool(_re_vs.search(r'\bscreen\b|\bcompound.librar\b|\bvirtual.screen\b', q_low))

        if not ((has_vina and has_diffdock) or (has_screening and (has_vina or has_diffdock))):
            return None

        top = self.workflow_search.get_workflow_by_filename_pattern('%drugclip_virtual_screening%')
        if not top:
            top = self.workflow_search.get_workflow_by_name_like('%virtual_screening%')
        if not top:
            top = self.workflow_search.get_workflow_by_filename_pattern('%run_diffdock_with_smiles%')
        if not top:
            return None

        log.info("[UnifiedWorkflowGeneration] Fast path virtual screening → %s", top.name)
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def _try_fast_path_boin_trial(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route BOIN dose-escalation queries to clinical_trial_simulation."""
        import re as _re_boin

        q_low = user_intent.lower()
        has_boin = 'boin' in q_low
        has_dose_esc = bool(_re_boin.search(r'\bdose.escalat\b|\bmtd\b|\bdlt\b', q_low))

        if not (has_boin or has_dose_esc):
            return None

        top = self.workflow_search.get_workflow_by_filename_pattern('%clinical_trial_simulation%')
        if not top:
            top = self.workflow_search.get_workflow_by_filename_pattern('%adaptive_trial_design%')
        if not top:
            return None

        log.info("[UnifiedWorkflowGeneration] Fast path BOIN/dose-escalation → %s", top.name)
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def _try_fast_path_somatic_variant_calling(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route somatic/tumor variant calling queries to detect_and_annotate_somatic_mutations."""
        import re as _re_som

        q_low = user_intent.lower()
        has_somatic = bool(_re_som.search(r'\bsomatic\b|\btumor\b|\btumour\b|\bclinvar\b|\bacmg\b', q_low))
        has_variant = bool(_re_som.search(r'\bvariant.call\b|\bvariant\b|\bgatk\b|\bmutect\b', q_low))
        # Do not capture germline-only queries (no tumor mention)
        has_germline_only = bool(_re_som.search(r'\bgermline\b', q_low)) and not has_somatic

        if not (has_somatic and has_variant) or has_germline_only:
            return None

        top = self.workflow_search.get_workflow_by_filename_pattern('%detect_and_annotate_somatic_mutations%')
        if not top:
            top = self.workflow_search.get_workflow_by_name_like('%somatic%')
        if not top:
            return None

        log.info("[UnifiedWorkflowGeneration] Fast path somatic variant calling → %s", top.name)
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def _try_fast_path_cryosparc_spa(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route CryoSPARC single-particle analysis queries directly, bypassing chain clarification."""
        q_low = user_intent.lower()
        has_cryosparc = 'cryosparc' in q_low
        has_cryo_em = bool(__import__('re').search(r'\bcryo.?em\b|\bcryo.electron\b|\bsingle.particle\b|\bspa\b', q_low))

        if not (has_cryosparc or has_cryo_em):
            return None

        top = self.workflow_search.get_workflow_by_filename_pattern('%cryosparc_standard_spa%')
        if not top:
            top = self.workflow_search.get_workflow_by_name_like('%cryosparc%')
        if not top:
            return None

        log.info("[UnifiedWorkflowGeneration] Fast path CryoSPARC SPA → %s", top.name)
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    # The request's TASK is to make new molecules or improve existing ones (not to predict
    # properties of given ones). Property/ADMET terms in such a request are design constraints.
    _GENERATIVE_TASK_PATTERNS = (
        r'\b(generate|design|propose|create|enumerate|grow|decorate)\b[^.\n]{0,60}?'
        r'\b(candidates?|molecules?|compounds?|analogu?es?|leads?|ligands?|binders?|series|scaffolds?|peptides?|macrocycles?)\b',
        r'\b(de novo|generative|candidate generation|molecule generation|lead (?:generation|optimi[sz]ation)|scaffold[- ]hop\w*)\b',
        r'\b(optimi[sz]e|improve|fix|reduce|lower|increase|raise)\b[^.\n]{0,60}?'
        r'\b(series|scaffold|leads?|compounds?|potency|solubility|druglikeness|drug-likeness|liabilit\w*|'
        r'selectivity|permeability|stability|affinity|half-life|clearance)\b',
        r'\b(adapt|fine-?tune|retrain)\b[^.\n]{0,40}?\b(generative|generator|reinvent)\b',
    )

    # Campaign Bayesian DMTA (Models Optimise) — must NOT be treated as reinvent4_lead_design.
    _DMTA_LOOP_PATTERNS = (
        r'\bdesign[-–—\s]*make[-–—\s]*test\b',
        r'\bdmta\b',
        r'\bbayesian\s+optim',
        r'\b96[-\s]?assay\b',
        r'\bassay\s+budget\b',
        r'\bpropos\w*\s+the\s+next\s+round\b',
        r'\bnext\s+round\b.{0,40}\brefit\b',
        r'\brefit\b.{0,40}\b(results?|round|propos)',
    )

    @staticmethod
    def _request_task_text(user_intent: str) -> str:
        """The request's statement of its task: the user's own text (without the
        "[Memory context]" / "[Inline parameters" suffixes added server-side), first paragraph.
        Supporting material follows a blank line — e.g. the cold-start examples' "Prepared demo
        context", whose own wording ("this design exercise", assay cut-offs) must not be read as
        the task: matched on the full text, 23 of 106 cold-start prompts that predict, dock or
        rank looked generative; on the first paragraph, none do."""
        import re as _re_task

        own = _re_task.split(r'\n\s*\[(?:Memory context|Inline parameters:)', user_intent or '')[0]
        return own.strip().split('\n\n')[0]

    @classmethod
    def _is_dmta_loop_task(cls, user_intent: str) -> bool:
        """True when the task is a campaign design–make–test / next-round / assay-budget loop
        (Models Molecular Rounds + drug-discovery retrain APIs), not generative lead design."""
        import re as _re_dmta

        task = cls._request_task_text(user_intent).lower()
        return any(_re_dmta.search(p, task) for p in cls._DMTA_LOOP_PATTERNS)

    @classmethod
    def _is_generative_task(cls, user_intent: str) -> bool:
        """The task is to make new molecules or improve existing ones (generate / design /
        optimise / adapt a generator), as opposed to predicting, docking or ranking given ones.
        DMTA campaign loops are excluded — those are not reinvent4_lead_design."""
        import re as _re_gen

        if cls._is_dmta_loop_task(user_intent):
            return False
        task = cls._request_task_text(user_intent).lower()
        return any(_re_gen.search(p, task) for p in cls._GENERATIVE_TASK_PATTERNS)

    @classmethod
    def _admet_is_generation_constraint(cls, user_intent: str) -> bool:
        """True when ADMET/SMILES terms appear in a request whose task is generative ("Generate
        candidates ... with ADMET filtering"): the ADMET fast path, which fires on any "admet",
        must not answer it with Property prediction. (Measured 2026-11-03: the observed
        generate/optimise -> ADMET misroutes came from SEARCH, not this fast path — see
        _is_generative_task's routing hint; this guard covers explicit ADMET phrasing.)"""
        import re as _re_gen

        text = _re_gen.split(r'\n\s*\[(?:Memory context|Inline parameters:)', user_intent or '')[0]
        mentions_admet = bool(_re_gen.search(r'\badmet\b', text.lower())) or bool(_re_gen.search(
            r'\bSMILES\s*[=:]\s*[A-Za-z0-9@\[\]\(\)\+\-=#\/\\\.%:]{8,}', text, _re_gen.IGNORECASE))
        return mentions_admet and cls._is_generative_task(user_intent)

    def _try_fast_path_admet_workflow(  # noqa: deploy-trigger
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Return predict_admet_properties workflow directly when ADMET intent is clear.

        Bypasses the disambiguation gate which fires when multiple pharmacology
        workflows score within 3 points of each other, causing success=False for
        ADMET queries even though predict_admet_properties is the correct match.
        """
        import re as _re_admet

        log.info("[AdmetFastPath] called — intent[:120]=%s", user_intent[:120])
        q_low = user_intent.lower()
        # Primary trigger: explicit "admet" keyword
        _has_admet = bool(_re_admet.search(r'\badmet\b', q_low))
        # Secondary trigger: explicit "SMILES: <value>" notation — unambiguous signal that
        # the user is supplying a compound structure for drug-property prediction.
        _has_smiles_notation = bool(_re_admet.search(
            r'\bSMILES\s*[=:]\s*[A-Za-z0-9@\[\]\(\)\+\-=#\/\\\.%:]{8,}',
            user_intent, _re_admet.IGNORECASE,
        ))
        log.info("[AdmetFastPath] has_admet=%s has_smiles=%s", _has_admet, _has_smiles_notation)
        if not (_has_admet or _has_smiles_notation):
            return None

        # Primary lookup: direct DB filename pattern — bypasses embedding search variance.
        # When many pharmacology workflows compete, the embedding search may push
        # predict_admet_properties below the top-20 cutoff.  A LIKE query on filename
        # always finds the workflow as long as it is in the DB.
        top = self.workflow_search.get_workflow_by_filename_pattern('%predict_admet_properties%')
        results = [top] if top else []
        if top:
            log.info("[AdmetFastPath] Found predict_admet_properties via direct DB filename pattern")

        if not top:
            # Fallback 1: broad embedding search — check both filename AND name
            results = self.workflow_search.search("predict admet properties pharmacology", limit=20)
            for r in results:
                fn = (r.filename or '').lower()
                nm = (r.name or '').lower()
                if ('predict_admet_properties' in fn
                        or ('admet' in nm and ('predict' in nm or 'screen' in nm))):
                    top = r
                    break

        if not top:
            # Fallback 2: embedding search on user intent
            results = self.workflow_search.search(user_intent, limit=20)
            for r in results:
                fn = (r.filename or '').lower()
                nm = (r.name or '').lower()
                if ('predict_admet_properties' in fn
                        or ('admet' in nm and ('predict' in nm or 'screen' in nm))):
                    top = r
                    break

        if not top:
            # Fallback 3: display-name search
            results = self.workflow_search.search("Predict ADMET Properties AI", limit=20)
            for r in results:
                fn = (r.filename or '').lower()
                nm = (r.name or '').lower()
                if ('predict_admet_properties' in fn
                        or ('admet' in nm and ('predict' in nm or 'screen' in nm))):
                    top = r
                    break

        if not top:
            # Fallback 4: exact name lookup — underscore and spaced Title Case variants
            top = self.workflow_search.get_workflow_by_name('predict_admet_properties')
            if not top:
                top = self.workflow_search.get_workflow_by_name('Predict Admet Properties')
            if top:
                log.info("[AdmetFastPath] Found predict_admet_properties via exact name lookup")

        if not top:
            # Fallback 5: broad SQL name LIKE '%admet%' — catches any naming variation
            # (e.g. 'ADMET Prediction', 'Drug ADMET Screening') in the dev DB.
            top = self.workflow_search.get_workflow_by_name_like('%admet%')
            if top:
                log.info("[AdmetFastPath] Found via name LIKE %%admet%%: %s", top.name)

        if not top:
            log.warning("[AdmetFastPath] predict_admet_properties not found in DB — fast path skipped")
            return None

        # Extract SMILES from query. We do NOT inject it into the intent string —
        # doing so lets _apply_llm_suggestions overwrite the value with a raw SMILES
        # string after LLM inference, which then fails Groovy's JsonSlurper().parseText().
        # Instead we post-process the result dict to force the correct JSON-array format.
        import json as _json_admet
        _smiles_match = _re_admet.search(
            r'\bSMILES\s*[=:]\s*([A-Za-z0-9@\[\]\(\)\+\-=#\/\\\.%:]+)',
            user_intent,
            _re_admet.IGNORECASE,
        )
        _smiles_json: Optional[str] = None  # None → use workflow default (valid JSON array)
        if _smiles_match:
            _smiles_raw = _smiles_match.group(1)
            # Strip trailing closing parens that are unbalanced — the query pattern
            # "(SMILES: <smiles>)" wraps the SMILES in sentence punctuation so the
            # regex captures the sentence's closing ) as part of the SMILES string.
            # Walk char-by-char; when a ) would push depth negative, stop there.
            _depth = 0
            _smiles_val = _smiles_raw
            for _i, _ch in enumerate(_smiles_raw):
                if _ch == '(':
                    _depth += 1
                elif _ch == ')':
                    if _depth == 0:
                        _smiles_val = _smiles_raw[:_i]
                        break
                    _depth -= 1
            _smiles_json = _json_admet.dumps([_smiles_val])
            log.info("[AdmetFastPath] Extracted SMILES → smiles_list=%s", _smiles_json)

        # Fallback: no explicit SMILES in query → try to resolve drug/compound name via PubChem.
        # Handles "Screen iptacopan for ADMET" (no SMILES: notation). resolve_chemical_name
        # uses PubChem PUG REST with 7-day Redis cache; fails gracefully (returns None).
        if not _smiles_json:
            try:
                from galaxy.ai.federated_query import resolve_chemical_name as _rcn
                # Extract a likely compound name: favour known patterns (drug INN suffix,
                # CAS-like, or any capitalized word near ADMET / screen keyword).
                _compound_m = _re_admet.search(
                    r'\b(?:screen|predict|evaluat|assess)\b\s+([A-Za-z][A-Za-z0-9\-]{2,30})'
                    r'|([A-Za-z][A-Za-z0-9\-]{2,30})\s+(?:for|in)\s+(?:admet|drug|pharmacok)',
                    user_intent, _re_admet.IGNORECASE,
                )
                if _compound_m:
                    _cname = (_compound_m.group(1) or _compound_m.group(2) or '').strip()
                    if _cname and len(_cname) > 3:
                        _resolved = _rcn(_cname)
                        if _resolved:
                            _smiles_json = _json_admet.dumps([_resolved])
                            log.info(
                                "[AdmetFastPath] Drug name %r → SMILES resolved via PubChem: %s",
                                _cname, _resolved[:60],
                            )
            except Exception as _rcn_err:
                log.debug("[AdmetFastPath] Drug name resolution skipped: %s", _rcn_err)

        log.info(
            "[UnifiedWorkflowGeneration] ADMET fast path → %s (score=%.1f)",
            top.name,
            top.score,
        )
        result = self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=results[:3],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

        # Post-process: force smiles_list to the JSON-array form the Groovy sharding
        # step requires. LLM inference inside _return_nextflow_match may have set it
        # to a raw SMILES string, which JsonSlurper().parseText() cannot parse and
        # causes an immediate JsonException → the Nextflow workflow fails at startup.
        if result and _smiles_json is not None:
            def _fix_param_list(param_list: list) -> None:
                for _p in param_list:
                    if _p.get('name') == 'smiles_list':
                        _p['value'] = _smiles_json
                        _p['default'] = _smiles_json
                        _p['autoFilled'] = True

            for _key in ('required_params', 'optional_params'):
                _fix_param_list(result.get(_key, []))
                _wf_ga = result.get('workflow_ga')
                if isinstance(_wf_ga, dict):
                    _fix_param_list(_wf_ga.get(_key, []))
                    # Also update the flat parameters dict used by the executor
                    if isinstance(_wf_ga.get('parameters'), dict):
                        _wf_ga['parameters']['smiles_list'] = _smiles_json
            log.info("[AdmetFastPath] Forced smiles_list=%s in result params", _smiles_json)

        return result

    def _detect_geo_platform(self, gse_id: str) -> Optional[str]:
        """Read GEO's own Series metadata to determine data modality — the DATA-FIRST
        signal for routing (vs guessing from the user's prose).

        Returns 'microarray' | 'scrna' | 'bulk_rnaseq' | None (unknown / lookup failed).
        One HTTP GET to GEO's SOFT text endpoint; `!Series_type` is authoritative for
        array-vs-sequencing, and title/summary/design disambiguate scRNA from bulk.
        Any failure returns None so the caller can fall back — never raises into routing.
        Results are cached per accession for the process lifetime.
        """
        cache = getattr(self, '_geo_platform_cache', None)
        if cache is None:
            cache = self._geo_platform_cache = {}
        # Delegate to the shared module-level implementation (also used by the
        # execute-gate via /api/ai_assistant/geo_platform) so there is ONE source
        # of truth for data-modality routing.
        return detect_geo_platform(gse_id, cache=cache)

    def _try_fast_path_geo_scrna_pseudobulk(  # noqa: deploy-trigger
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """CASE B GEO routing: accession present but no S3 paths → geo_scrna_pseudobulk.

        When the user provides only a GEO accession (e.g. GSE227835) with no
        pre-staged S3 file paths for samplesheet/matrix/contrasts, route to
        geo_scrna_pseudobulk which downloads raw data directly from NCBI GEO,
        pseudobulk-aggregates scRNA-seq cells, and outputs DESeq2-ready CSVs.

        CASE A (S3 paths already in the message or [Inline parameters:] block) is
        handled by the LLM via the system prompt CASE A rule → differentialabundance.
        This fast path only triggers for CASE B (no S3 paths).

        Note: by the time this is called, inline_parameters have already been merged
        into user_intent as '[Inline parameters:\nkey: value\n...]' so checking
        user_intent for 's3://' covers both the raw message and inline params.
        """
        import re as _re_geo

        # Extract GEO accession (only GSE for now; SRR/ERR are handled by nfcore fast path)
        _geo_m = _re_geo.search(r'\bGSE\d{4,9}\b', user_intent, _re_geo.IGNORECASE)
        if not _geo_m:
            return None
        _geo_id = _geo_m.group(0).upper()

        # GSE227835 is pre-staged with demo S3 data; the LLM system prompt rule
        # always routes it to differentialabundance with those paths — never
        # geo_scrna_pseudobulk, even when the user message contains no S3 URIs.
        if _geo_id == 'GSE227835':
            log.info("[GeoFastPath] GSE227835 is pre-staged — deferring to LLM differentialabundance rule")
            return None

        # CASE A detection: if message already contains S3 URIs for samplesheet/matrix,
        # skip this fast path and let the LLM handle it via differentialabundance.
        _has_s3_paths = bool(_re_geo.search(r's3://[^\s]+\.(csv|tsv|txt|gz)', user_intent, _re_geo.IGNORECASE))
        if _has_s3_paths:
            log.info("[GeoFastPath] CASE A detected (S3 paths present) — skipping geo_scrna_pseudobulk fast path")
            return None

        # Only trigger for DE / RNA-seq / scRNA-seq intent
        _q = user_intent.lower()
        _is_de_intent = any(kw in _q for kw in [
            'differential', 'deseq2', 'edger', 'rna-seq', 'rnaseq', 'scrna',
            'expression', 'de genes', 'deg', 'pseudobulk', 'download', 'fetch',
        ])
        if not _is_de_intent:
            return None

        # Modality gate: pseudobulk AGGREGATES single cells, so it is only meaningful
        # for scRNA data. Decide DATA-FIRST, not by guessing from prose — read GEO's own
        # Series metadata (ground truth) for the accession. Microarray / bulk RNA-seq →
        # defer to normal routing (limma / differentialabundance); single-cell → pseudobulk.
        _platform = self._detect_geo_platform(_geo_id)  # 'microarray'|'scrna'|'bulk_rnaseq'|None
        if _platform in ('microarray', 'bulk_rnaseq'):
            # A bare GEO accession is not a count matrix.  Falling through here used
            # to let ordinary similarity routing emit an empty differentialabundance
            # card (matrix/samplesheet unset) that looked runnable.  Fetch and inspect
            # the series first instead.  We intentionally do *not* auto-chain this to
            # DESeq2: a GEO series can be normalized microarray data or lack an
            # interpretable comparison, both of which require a method/contrast choice.
            return self._return_geo_bulk_connector(_geo_id, _platform)
        if _platform is None:
            # GEO metadata unavailable (network/parse) → do not guess that an
            # accession is single-cell.  Pseudobulk irreversibly changes the unit of
            # analysis, so it is allowed only with an explicit single-cell signal;
            # every other unknown accession goes through retrieval/review.
            _scrna_signal = any(kw in _q for kw in [
                'scrna', 'sc-rna', 'single cell', 'single-cell', 'pseudobulk', '10x', 'cellranger',
            ])
            if not _scrna_signal:
                log.info("[GeoFastPath] GEO %s metadata unavailable; no explicit single-cell signal "
                         "— routing to connector for data review", _geo_id)
                return self._return_geo_bulk_connector(_geo_id, 'unknown')
        # _platform == 'scrna', or metadata is unavailable but the user explicitly
        # requested a single-cell/pseudobulk analysis → proceed with pseudobulk.

        # Single-cell CLUSTERING / trajectory / cell-typing intent must NOT be collapsed
        # to pseudobulk — pseudobulk aggregation destroys per-cell resolution and cannot
        # reproduce Seurat/Scanpy clustering, UMAP, marker discovery, or trajectory work
        # (the actual analysis in the source papers). Defer to normal routing so the
        # router can select a real single-cell workflow (nf-core/scrnaseq,
        # bioconductor_scrna_seq, Seurat/Scanpy clustering, cell-type annotation).
        # Keep pseudobulk ONLY when the intent is explicit cross-condition DE.
        _singlecell_analysis = any(kw in _q for kw in [
            'cluster', 'umap', 't-sne', 'tsne', 'cell type', 'cell-type', 'celltype',
            'annotat', 'marker gene', 'markers', 'subpopulation', 'sub-population',
            'sub-cluster', 'trajectory', 'pseudotime', 'seurat', 'scanpy', 'cell atlas',
        ])
        _explicit_pseudobulk_de = any(kw in _q for kw in [
            'pseudobulk', 'pseudo-bulk', 'deseq2', 'edger', 'differential expression',
            'differential abundance',
        ])
        if _singlecell_analysis and not _explicit_pseudobulk_de:
            log.info("[GeoFastPath] GEO %s single-cell clustering/trajectory intent — skipping "
                     "pseudobulk fast path, deferring to normal routing (nf-core/scrnaseq / Seurat)", _geo_id)
            return None

        # Look up geo_scrna_pseudobulk in the DB
        top = self.workflow_search.get_workflow_by_filename_pattern('%geo_scrna_pseudobulk%')
        if not top:
            top = self.workflow_search.get_workflow_by_name('geo_scrna_pseudobulk')
        if not top:
            log.warning("[GeoFastPath] geo_scrna_pseudobulk not found in DB — fast path skipped")
            return None

        log.info("[GeoFastPath] CASE B: routing GSE=%s → geo_scrna_pseudobulk (id=%s)", _geo_id, top.id)

        _wf_ga = {
            'id': top.id,
            'name': top.name,
            'filename': top.filename,
            'format': 'nextflow',
            'domain': getattr(top, 'domain', 'transcriptomics'),
            'description': (top.description or
                            'Auto-fetch and pseudobulk-aggregate scRNA-seq data from GEO, '
                            'then output count matrix + sample metadata ready for DESeq2.'),
            'required_params': [
                {
                    'name': 'geo_accession',
                    'value': _geo_id,
                    'default': _geo_id,
                    'type': 'text',
                    'required': True,
                    'autoFilled': True,
                    'description': 'GEO accession (e.g. GSE227835)',
                }
            ],
            'optional_params': [],
            'steps': {},
            'nextflow_path': top.filename,
        }
        return {
            'success': True,
            # Every sibling fast path (nf-core/ADMET/cryosparc via _return_nextflow_match,
            # plus the template-confidence paths) sets 'source'; this one reuses a DB
            # template (geo_scrna_pseudobulk), so it is 'template_reuse'. Omitting it made
            # the endpoint's result['source'] subscript raise KeyError -> 500 for scRNA.
            'source': 'template_reuse',
            'message': (
                f"I'm fetching the raw data directly from GEO using GEOquery — "
                f"this downloads and pseudobulk-aggregates the scRNA-seq data for {_geo_id} "
                f"before running DESeq2. The geo_scrna_pseudobulk workflow will output "
                f"counts_matrix.csv + sample_metadata.csv + contrasts.csv ready for differential expression."
            ),
            'workflow_type': 'workflow_generation',
            'workflow_ga': _wf_ga,
            'needsWorkflowGeneration': False,
        }

    def _return_geo_bulk_connector(self, accession: str, platform: str) -> Optional[Dict[str, Any]]:
        """Return a non-empty, scientifically safe GEO retrieval card for bulk data.

        This is deliberately a retrieval/review step rather than a pretend automatic
        DE chain.  GEOquery can retrieve a series matrix and phenotype table, but it
        cannot establish that matrix is raw counts or infer a defensible contrast.
        """
        top = self.workflow_search.get_workflow_by_filename_pattern('%geo_data_connector%')
        if not top:
            top = self.workflow_search.get_workflow_by_name('geo_data_connector')
        if not top:
            log.error("[GeoFastPath] geo_data_connector not found in DB; refusing empty DE card for %s", accession)
            return {
                'success': False,
                'source': 'geo_accession_preflight',
                'workflow_type': 'workflow_generation',
                'needsWorkflowGeneration': False,
                'message': (
                    f"BioMate recognized {accession}, but the GEO retrieval workflow is not available in this "
                    "environment. Differential expression was not created because no count matrix, sample "
                    "metadata, or confirmed contrast is available."
                ),
                'validation': {
                    'is_valid': False,
                    'issues': ['GEO retrieval workflow is unavailable'],
                    'warnings': [],
                    'suggestions': ['Enable geo_data_connector, then retrieve and review the series before selecting a DE method.'],
                },
            }

        platform_label = {
            'bulk_rnaseq': 'bulk RNA-seq',
            'microarray': 'microarray',
        }.get(platform, 'an unconfirmed bulk or microarray assay')
        log.info("[GeoFastPath] GEO %s platform=%s → geo_data_connector (id=%s)", accession, platform, top.id)
        required = {
            'name': 'accession',
            'value': accession,
            'default': accession,
            'type': 'text',
            'required': True,
            'autoFilled': True,
            'description': 'GEO series or sample accession to retrieve via GEOquery.',
        }
        return {
            'success': True,
            'source': 'geo_accession_preflight',
            'message': (
                f"I identified {accession} as {platform_label}. I will retrieve its GEO series matrix and "
                "sample metadata first. Before differential expression, BioMate will need to verify whether "
                "the matrix is raw counts and which phenotype column/contrast is scientifically appropriate."
            ),
            'workflow_type': 'workflow_generation',
            'workflow_ga': {
                'id': top.id,
                'name': top.name,
                'filename': top.filename,
                'format': 'nextflow',
                'domain': getattr(top, 'domain', 'transcriptomics'),
                'description': (
                    'Retrieve a GEO series matrix and sample metadata for assay, count-scale, and contrast review. '
                    'This retrieval step does not automatically run differential expression.'
                ),
                'required_params': [required],
                'optional_params': [],
                'parameters': {'accession': accession},
                'steps': {},
                'nextflow_path': top.filename,
            },
            'required_params': [required],
            'optional_params': [],
            'generated_parameters': [required],
            'needsWorkflowGeneration': False,
            'validation': {'is_valid': True, 'issues': [], 'warnings': [], 'suggestions': []},
        }

    def _try_fast_path_protein_structure(  # noqa: deploy-trigger
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route a structure-prediction request with a sequence to nf-core/proteinfold.

        Sequence content identifies the input, not the requested operation. A bare
        sequence retains the historical folding default; explicit property,
        alignment or annotation tasks must continue through task-aware routing.

        The detected sequence is injected as the `sequence` param suggestion so the
        frontend renders it pre-filled without the user having to copy-paste again.
        """
        import re as _re_prot

        _AA_CHARS = r'[ACDEFGHIKLMNPQRSTVWYBZXUacdefghiklmnpqrstvwyb]'
        _best_seq: Optional[str] = None
        _best_len = 0
        for _m in _re_prot.finditer(rf'\b({_AA_CHARS}{{15,}})\b', user_intent):
            # A/C/G/T(/U/N) are also amino-acid letters: a run made only of them is DNA/RNA —
            # e.g. 10x cell barcodes "AAACCTGAGAAGGCCT" in an inline scRNA count table were read
            # as a protein and the request got nf-core/proteinfold (dev replay, 2026-11-04).
            if _re_prot.fullmatch(r'[ACGTUNacgtun]+', _m.group(1)):
                continue
            if len(_m.group(1)) > _best_len:
                _best_seq = _m.group(1).upper()
                _best_len = len(_best_seq)

        if not _best_seq:
            return None

        # A sequence in a DESIGN request is the target/binding site or the molecule to improve,
        # not a structure-prediction job: "Design cyclic peptides against this binding site" and
        # "Improve serum stability without losing affinity (peptide design)" carry a target
        # sequence and were answered with nf-core/proteinfold (dev 2026-11-04, once the real
        # nf-core pipelines were restored and proteinfold became resolvable). Same rule as the
        # ADMET fast path: the request's own task decides, not the presence of a sequence.
        if self._is_generative_task(user_intent):
            log.info("[ProteinStructureFastPath] generative task with a sequence (target/molecule to "
                     "design against) — not structure prediction; skipping")
            return None

        # Only route here if the query is NOT clearly about nucleotide analysis
        # (e.g. "align to reference genome", "variant calling") — those also match AA regex.
        _nucleotide_only_kw = ('variant call', 'snp', 'indel', 'vcf', 'genome align', 'bwa',
                               'bowtie', 'gatk', 'samtools', 'fastq', 'methylat')
        _low = user_intent.lower()
        if any(kw in _low for kw in _nucleotide_only_kw):
            return None

        # Do NOT trigger for multi-sequence conservation / alignment requests
        _MULTI_SEQ_SIGNALS = (
            'conserv', 'align', 'phylogen', 'multiple sequence', 'multi.*sequence',
            'compare.*sequence', 'msa', 'homolog', 'evolution',
        )
        if any(_re_prot.search(sig, _low) for sig in _MULTI_SEQ_SIGNALS):
            return None

        # A peptide-property request was answered with proteinfold on live dev
        # (2026-11-07), although the prose named an entirely different workflow.
        # Require positive structure intent rather than adding an ever-growing
        # blacklist of non-folding assays. Context below the first blank line is
        # data, not a replacement for the user's requested operation.
        _task = user_intent.split('\n\n', 1)[0].lower()
        _structure_intent = _re_prot.search(
            r'\bfold(?:ing)?\b(?![\s-]*changes?\b)|\b(?:alphafold\d*|esmfold|proteinfold)\b'
            r'|\b(?:predict|model|determine|infer|calculate)\w*\b.{0,60}\b(?:3d\s+|tertiary\s+|protein\s+)?structure\b'
            r'|\b(?:3d\s+|tertiary\s+|protein\s+)?structure\s+(?:prediction|model(?:ing|ling)?)\b'
            r'|(?:预测|建模|计算|推断).{0,15}(?:三维|三级|蛋白质|肽)?结构'
            r'|(?:结构预测|结构建模|蛋白折叠)',
            _task,
        )
        _bare_sequence = _re_prot.fullmatch(rf'\s*{_AA_CHARS}{{15,}}\s*', user_intent)
        if not _structure_intent and not _bare_sequence:
            log.info('[ProteinStructureFastPath] sequence present without folding intent; skipping')
            return None

        # Semantic search is more reliable than DB pattern lookup here because
        # the DB stores nf-core workflow names with hyphens ("nf-core/proteinfold")
        # which the LIKE-based helpers don't match consistently.
        results = self.workflow_search.search(
            "protein structure prediction single sequence folding ESMFold AlphaFold proteinfold",
            domain="structural_biology",
            limit=15,
        )
        # Walk results: prefer 'proteinfold', accept any single-sequence fold workflow,
        # but explicitly EXCLUDE multi-sequence conservation/alignment pipelines.
        _FOLD_NAMES = ('proteinfold', 'alphafold', 'esmfold', 'openfold', 'rosettafold')
        _EXCLUDE_NAMES = ('conservation', 'align', 'homolog', 'phylogen', 'evolution', 'msa',
                          'comparative', 'chai1', 'multiple')
        top = None
        for match in results:
            name_low = (getattr(match, 'name', '') or '').lower()
            fname_low = (getattr(match, 'filename', '') or '').lower()
            combined = name_low + ' ' + fname_low
            if any(ex in combined for ex in _EXCLUDE_NAMES):
                continue
            if any(fn in combined for fn in _FOLD_NAMES) and self._is_executable_nextflow_match(match):
                top = match
                break

        # Fallback to DB LIKE lookup if semantic search didn't yield a runnable match
        if not top:
            top = self.workflow_search.get_workflow_by_filename_pattern('%proteinfold%')
        if not top:
            log.warning("[ProteinStructureFastPath] proteinfold not found in DB — skipping")
            return None

        log.info(
            "[UnifiedWorkflowGeneration] protein-structure fast path → proteinfold "
            "(seq_len=%d, workflow_id=%d)",
            _best_len,
            top.id,
        )
        result = self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )
        # Inject sequence into all sequence-type required params so the frontend
        # renders them pre-filled (same logic as _extract_explicit_params_from_query
        # but applied post-routing so the correct param list is available).
        if result and result.get('workflow_ga'):
            _wf = result['workflow_ga']
            _best_len = len(_best_seq)
            for _p in _wf.get('required_params', []) + _wf.get('optional_params', []):
                _pname = _p.get('name', '')
                if self._detect_param_type(_pname, '') == 'sequence' \
                        and not _p.get('value'):
                    _p['value'] = _best_seq
                    _p['default'] = _best_seq
                elif _pname == 'sequence_length' and not _p.get('value'):
                    _p['value'] = str(_best_len)
                    _p['default'] = str(_best_len)
        return result

    def _try_fast_path_nfcore_pipeline(  # noqa: deploy-trigger
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
    ) -> Optional[Dict[str, Any]]:
        """Route explicit nf-core/X pipeline mentions directly to _return_nextflow_match.

        When the user writes "nf-core/rnaseq", "nf-core/scrnaseq", etc. the normal
        embedding-search path may fail on dev (different DB state, scoring variance,
        NextflowComposer fallback errors). This fast path bypasses embedding search
        entirely and looks up the pipeline by filename in the DB.
        """
        import re as _re_nfcore

        m = _re_nfcore.search(r'\bnf-core/([a-zA-Z][a-zA-Z0-9_-]+)', user_intent, _re_nfcore.IGNORECASE)
        if not m:
            return None

        slug = m.group(1).lower()  # e.g. "rnaseq", "scrnaseq", "sarek"
        filename_pattern = f'nfcore/{slug}/main.nf'

        top = self.workflow_search.get_workflow_by_filename_pattern(filename_pattern)
        if not top:
            # Broader search: allow subdirectory variants like nfcore/rnaseq/workflows/main.nf
            top = self.workflow_search.get_workflow_by_filename_pattern(f'nfcore/{slug}/%')
        if not top:
            log.warning("[NfcoreFastPath] No DB entry found for %s", filename_pattern)
            return None

        log.info(
            "[UnifiedWorkflowGeneration] nf-core fast path → %s (slug=%s, id=%d)",
            top.name,
            slug,
            top.id,
        )
        return self._return_nextflow_match(
            match=top,
            score=top.score,
            user_intent=user_intent,
            source='template_reuse',
            needs_user_feedback=False,
            search_results=[top],
            selected_trial='',
            trials=[],
            uploaded_datasets=uploaded_datasets,
        )

    def generate_workflow_unified(
        self,
        user_intent: str,
        uploaded_datasets: Optional[List[Dict[str, Any]]] = None,
        user_id: Optional[str] = None,
        key_terms: Optional[List[str]] = None,
        preferred_domains: Optional[List[str]] = None,
        penalized_domains: Optional[List[str]] = None,
        credential_map: Optional[Dict[str, bool]] = None,
        user_input_kinds: Optional[List[str]] = None,
        selected_workflow: Optional[Dict[str, Any]] = None,
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

        # The user already chose this exact workflow (Workflows library "Run" or another explicit picker, or a
        # follow-up that fills inputs for the workflow open in the panel). Identity is given, so
        # no route or search may replace it: build THAT workflow's card (params prefilled from
        # user_intent) or fail honestly — never silently substitute another workflow.
        if selected_workflow:
            return self._generate_selected_workflow(selected_workflow, user_intent, uploaded_datasets)

        # ml_training route (feature-flagged via ML_TRAINING_ROUTING, default OFF).
        # A model-TRAINING request short-circuits to the ml_training pipeline card
        # instead of the normal workflow search. route_ml_training_result() returns
        # None when the flag is off, for non-training intents, and for training
        # requests it can't resolve a dataset for — so wiring this in is inert until
        # the flag is set, and even then it can only ADD a route, never break one.
        # Lazy-imported + guarded so any failure degrades to the normal search path.
        try:
            from galaxy.ai.ml_training.routing import route_ml_training_result
            # The user's ATTACHED data is what a "train a model on our data" request trains on, so
            # it is threaded in. Without it the router could not resolve a dataset, returned None,
            # and the request fell through to the catalog search — which answered a model-TRAINING
            # request with a molecule-DESIGN workflow (dev 2026-11-11: "Train a potency predictor on
            # our in-house assay data." + bace_assays.csv → a scaffold-hopping card whose required
            # param is the "compound series to hop"). Only readable training tables qualify
            # (select_training_dataset), so a request with raw reads attached still falls through
            # to the normal search exactly as before.
            _ml_result = route_ml_training_result(user_intent, uploaded_datasets=uploaded_datasets)
        except Exception as _ml_err:
            _ml_result = None
            log.warning("[UnifiedWorkflowGeneration] ml_training routing skipped: %s", _ml_err)
        if _ml_result is not None:
            log.info("[UnifiedWorkflowGeneration] ml_training route matched → training card")
            return _ml_result

        # multi-omics integration route (feature-flagged via MULTIOMICS_ROUTING, default OFF).
        # An "integrate my RNA + methylation + proteomics" request short-circuits to a
        # data-shape-selected integration card (which method + per-modality normalization +
        # which workflow to run) instead of the normal single-workflow search. Same
        # discipline as ml_training above: inert until the flag is set, only ADDs a route,
        # and guarded so any failure degrades to the normal search path.
        try:
            from galaxy.ai.multiomics.routing import route_multiomics_result
            _mo_result = route_multiomics_result(user_intent)
        except Exception as _mo_err:
            _mo_result = None
            log.warning("[UnifiedWorkflowGeneration] multiomics routing skipped: %s", _mo_err)
        if _mo_result is not None:
            log.info("[UnifiedWorkflowGeneration] multiomics route matched → integration card")
            return _mo_result

        # C1b — Inject recent user corrections into the intent for personalized search/generation
        # Only attempt when user_id is a UUID (LTM tables key on UUID, not Galaxy integer IDs).
        _user_id_is_uuid = bool(
            user_id and len(user_id) == 36 and user_id.count("-") == 4
        )
        if MEMORY_AVAILABLE and self.agentic_memory and _user_id_is_uuid:
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

            # DMTA / Optimise campaign loop — not a Nextflow card. Chat Node layer
            # deep-links to Models Molecular Rounds; if this path is hit directly,
            # refuse reinvent4_lead_design rather than template-reusing it as DMTA.
            if self._is_dmta_loop_task(user_intent):
                log.info(
                    "[UnifiedWorkflowGeneration] DMTA loop task — refusing reinvent4_lead_design "
                    "(use Models → Molecular → Rounds / drug-discovery retrain APIs)"
                )
                return {
                    'success': False,
                    'error': (
                        'DMTA / design–make–test loop is a campaign Bayesian propose/refit surface '
                        '(Models → Molecular learning → Rounds), not reinvent4_lead_design. '
                        'Open /models?tab=molecular to create a campaign and propose the next round.'
                    ),
                    'source': 'dmta_models_rounds',
                    'needs_user_feedback': False,
                    'search_results': [],
                    'selected_trial': '',
                    'trials': [],
                    'uploaded_datasets': uploaded_datasets,
                }

            # An explicitly named workflow outranks every keyword heuristic below.
            _fast_named = self._try_fast_path_named_catalog_workflow(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_named:
                return _fast_named

            _fast_codon = self._try_fast_path_explicit_codon_workflow(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_codon:
                return _fast_codon

            _fast_dock = self._try_fast_path_explicit_docking_workflow(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_dock:
                return _fast_dock

            _fast_vs = self._try_fast_path_virtual_screening(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_vs:
                return _fast_vs

            _fast_boin = self._try_fast_path_boin_trial(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_boin:
                return _fast_boin

            _fast_somatic = self._try_fast_path_somatic_variant_calling(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_somatic:
                return _fast_somatic

            _fast_cryo = self._try_fast_path_cryosparc_spa(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_cryo:
                return _fast_cryo

            # ADMET named as a constraint of a generation/optimisation request is not an
            # ADMET-prediction request: skip the ADMET fast path and steer search (hint below).
            _admet_as_constraint = self._admet_is_generation_constraint(user_intent)
            _generative_task = self._is_generative_task(user_intent)

            try:
                _fast_admet = None if _admet_as_constraint else self._try_fast_path_admet_workflow(
                    user_intent, uploaded_datasets=uploaded_datasets
                )
            except Exception as _fa_exc:
                log.error("[AdmetFastPath] Unexpected exception: %s", _fa_exc, exc_info=True)
                _fast_admet = None
            if _fast_admet:
                return _fast_admet

            try:
                _fast_geo = self._try_fast_path_geo_scrna_pseudobulk(
                    user_intent, uploaded_datasets=uploaded_datasets
                )
            except Exception as _fg_exc:
                log.error("[GeoFastPath] Unexpected exception: %s", _fg_exc, exc_info=True)
                _fast_geo = None
            if _fast_geo:
                return _fast_geo

            try:
                _fast_prot = self._try_fast_path_protein_structure(
                    user_intent, uploaded_datasets=uploaded_datasets
                )
            except Exception as _fp_exc:
                log.error("[ProteinStructureFastPath] Unexpected exception: %s", _fp_exc, exc_info=True)
                _fast_prot = None
            if _fast_prot:
                return _fast_prot

            _fast_nfcore = self._try_fast_path_nfcore_pipeline(
                user_intent, uploaded_datasets=uploaded_datasets
            )
            if _fast_nfcore:
                return _fast_nfcore

            # Ensure the fast LLM client is initialized before chain search.
            # _llm_select_chain (chain verifier) needs workflow_search._llm_client set BEFORE
            # search_chains() is called — otherwise it returns None (no verification) and
            # embedding-ranked candidates are returned unchecked.
            # We create the client without making an API call by checking _fast_llm_client directly.
            if self._fast_llm_client is None:
                try:
                    from .llm_client import LLMClient
                    _init_client = LLMClient(self.config)
                    _provider = self.config.llm_provider.lower()
                    _fast_model = _FAST_CLASSIFICATION_MODELS.get(_provider)
                    if _fast_model:
                        _init_client.model = _fast_model
                    self._fast_llm_client = _init_client
                    self.workflow_search.set_llm_client(self._fast_llm_client)
                    log.info("[UnifiedWorkflowGeneration] Fast LLM client initialized for chain verification")
                except Exception as _init_err:
                    log.warning("[UnifiedWorkflowGeneration] Fast LLM client init failed: %s", _init_err)

            # Step 0: Chain lookup — preferred path for multi-step research projects.
            # The search uses embedding similarity (threshold 0.42) + LLM scope check.
            # If the LLM is uncertain it sets clarification_needed and returns a question.
            # Skip chain lookup when the user is clearly requesting a specific single workflow:
            # do a preliminary workflow search; if the top result scores very high (meaning the
            # query names a specific workflow explicitly), chains are inappropriate.
            try:
                _prelim = self.workflow_search.search(user_intent, limit=1)
                _prelim_score = _prelim[0].score if _prelim else 0.0
                _SPECIFIC_WORKFLOW_THRESHOLD = 55.0
                if _prelim_score >= _SPECIFIC_WORKFLOW_THRESHOLD:
                    chain_results = []
                    log.info(
                        "[UnifiedWorkflowGeneration] Skipping chain lookup — specific workflow match "
                        f"(top_score={_prelim_score:.1f} >= {_SPECIFIC_WORKFLOW_THRESHOLD})"
                    )
                else:
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
                        # Build scientific_rationale for the candidate chain's tools so the
                        # LLM can ask targeted differentiating questions on clarification turns.
                        _chain_clarif_tools: List[str] = []
                        for _step in (top_chain.steps or []):
                            _wf_name = _step.get('workflow_name', '') if isinstance(_step, dict) else ''
                            if _wf_name:
                                _wf_hits = self.workflow_search.search(_wf_name, limit=1)
                                if _wf_hits and _wf_hits[0].tools:
                                    _chain_clarif_tools.extend(
                                        t for t in _wf_hits[0].tools
                                        if t not in _chain_clarif_tools
                                    )
                        _chain_clarif_rationale = (
                            self._build_scientific_rationale(
                                '', top_chain.display_name, _chain_clarif_tools
                            ) if _chain_clarif_tools else {}
                        )
                        return {
                            'success': False,
                            'workflow_type': 'clarification',
                            'source': 'chain_lookup',
                            'confidence': 5,
                            'message': q,
                            'clarification_question': q,
                            'candidate_chain': top_chain.name,
                            **({'scientific_rationale': _chain_clarif_rationale,
                                'workflow_name': top_chain.display_name}
                               if _chain_clarif_rationale else {}),
                        }
                    log.info("[UnifiedWorkflowGeneration] Chain match: %s (%d steps)", top_chain.name, len(top_chain.steps))
                    try:
                        from galaxy.webapps.galaxy.api.workflow_chain import enrich_chain_steps  # noqa: PLC0415
                        enriched_steps = enrich_chain_steps(top_chain.steps)
                    except Exception as _enrich_exc:
                        log.warning("[UnifiedWorkflowGeneration] Chain step enrich failed: %s", _enrich_exc)
                        enriched_steps = top_chain.steps
                    chain_result: Dict[str, Any] = {
                        'success': True,
                        'workflow_type': 'chain',
                        'chain_name': top_chain.name,
                        'chain_display_name': top_chain.display_name,
                        'chain_domain': top_chain.domain,
                        'chain_description': top_chain.description,
                        'chain_steps': enriched_steps,
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
                    return chain_result
            except Exception as chain_exc:
                log.warning("[UnifiedWorkflowGeneration] Chain lookup failed: %s", chain_exc)

            # Microarray: prevent embedding search from returning nf-core/rnaseq.
            # Microarray intensities are continuous log-ratios; DESeq2/edgeR/rnaseq pipeline
            # assumes Poisson-distributed integer counts — fundamentally wrong model.
            _MICROARRAY_PAT = re.compile(
                r'\b(microarray|affymetrix|agilent|illumina\s+beadchip|expression\s+array|'
                r'probe\s+intensit|cel\s+file|gpl\d+|\.cel\b|affy\b|limma\b|'
                r'differential\s+expression.*array|array.*differential\s+expression)\b',
                re.IGNORECASE,
            )
            if _MICROARRAY_PAT.search(user_intent):
                user_intent = user_intent + (
                    "\n[Routing: microarray gene expression — use limma or differentialabundance, "
                    "NOT nf-core/rnaseq. rnaseq requires raw integer counts (Poisson model); "
                    "microarray uses log-ratio intensities (Gaussian model). "
                    "Preferred: limma_microarray_analysis or nf-core/differentialabundance.]"
                )
                log.info("[UnifiedWorkflowGeneration] Microarray pattern detected — injected limma routing hint")

            # Plan B / synthetic biology: codon optimization before mRNA-LNP engineering.
            _CODON_MRNA_PAT = re.compile(
                r'\b(optimize\s+codons?|codon\s+optimi[sz]ation|heterologous\s+expression|'
                r'host_codon_usage|target_sequence|optimize_codons_for_heterologous_expression|'
                r'mrna[\s-]lnp|registry\s+id\s+10813)\b',
                re.IGNORECASE,
            )
            if _CODON_MRNA_PAT.search(user_intent):
                _hint = (
                    "\n[Routing hint: codon optimization / mRNA construct engineering — "
                    "use optimize_codons_for_heterologous_expression (registry id 10813), "
                    "NOT nf-core/epitopeprediction or immunopeptidomics workflows]"
                )
                user_intent = user_intent + _hint
                log.info("[UnifiedWorkflowGeneration] Codon/mRNA pattern detected — injected optimize_codons routing hint")

            # ANDV inhibitor / pharmacology: site-directed AutoDock Vina (not DiffDock / AF3 chain).
            _DOCKING_VINA_PAT = re.compile(
                r'\b(autodock\s*vina|docking_autodock_vina|site[- ]directed\s+docking|vina\s+docking)\b',
                re.IGNORECASE,
            )
            if _DOCKING_VINA_PAT.search(user_intent) and not re.search(
                r'\bdiffdock\b', user_intent, re.IGNORECASE
            ):
                _hint = (
                    "\n[Routing hint: site-directed AutoDock Vina molecular docking — "
                    "use pharmacology/docking_autodock_vina (registry id 12824), "
                    "NOT structure_prediction_docking or ADMET-only workflows unless ADMET was explicitly requested]"
                )
                user_intent = user_intent + _hint
                log.info("[UnifiedWorkflowGeneration] AutoDock Vina pattern detected — injected docking_autodock_vina routing hint")

            # Relative binding free energy (ΔΔG) for a RESIDUE / PEPTIDE mutation → gromacs_pmx_fep.
            # gromacs_pmx_fep (id 14652) was registered after the routing hints were written, so with
            # no hint the LLM-browse pass pulls "peptide binder" to cyclic_peptide_design (enumerative
            # design, not an affinity engine). The mutation/residue/peptide gate keeps a generic
            # two-ligand congeneric-series RBFE on openfe_rbfe and an MD MM-GBSA ask on gromacs_protein_md.
            _FEP_MUTATION_PAT = re.compile(
                r'\b(relative\s+binding\s+free\s+energy|binding\s+free\s+energy|'
                r'free\s+energy\s+perturbation|\bFEP\b|\bRBFE\b|ΔΔG|'
                r'delta[\s-]*delta[\s-]*g|\bddg\b)\b',
                re.IGNORECASE,
            )
            _FEP_MUTATION_CTX = re.compile(
                r'\b(single[- ]residue|residue\s+mutation|point\s+mutation|mutate\w*|mutant|'
                r'amino[- ]acid\s+(?:change|substitution)|peptide|cyclic)\b',
                re.IGNORECASE,
            )
            # An explicit MM-GBSA / MM-PBSA ask is an MD endpoint-free-energy workflow
            # (gromacs_protein_md), not a pmx alchemical ΔΔG — leave those on their own route.
            _FEP_MMGBSA_EXCLUDE = re.compile(r'\b(mm[- ]?gbsa|mm[- ]?pbsa|mmpbsa)\b', re.IGNORECASE)
            if (_FEP_MUTATION_PAT.search(user_intent) and _FEP_MUTATION_CTX.search(user_intent)
                    and not _FEP_MMGBSA_EXCLUDE.search(user_intent)):
                _hint = (
                    "\n[Routing hint: relative binding free energy (ΔΔG / FEP) for a RESIDUE or "
                    "PEPTIDE mutation — use gromacs_pmx_fep (registry id 14652), NOT openfe_rbfe "
                    "(two-ligand congeneric-series RBFE) and NOT cyclic_peptide_design "
                    "(enumerative peptide design, not an affinity engine)]"
                )
                user_intent = user_intent + _hint
                log.info("[UnifiedWorkflowGeneration] FEP residue/peptide-mutation pattern detected — injected gromacs_pmx_fep routing hint")

            # De novo / redesign of a PROTEIN or ENZYME (backbone + sequence) → bionemo_structure_design.
            # profam (id 14474) is a variant-fitness SCORER (ranks supplied variants); it cannot propose
            # new ones, but it lexically dominates "enzyme variants / protein engineering" and wins when
            # no hint names a generative protein-design workflow. Excludes antibody/nanobody (own
            # workflows), peptide/macrocycle (cyclic_peptide_design) and small-molecule (reinvent4).
            # Design-SPECIFIC nouns only: a bare "protein" + generic verb over-fires on
            # non-design asks (primer design for a protein-coding gene, strain engineering,
            # contact maps, purification/plasmid protocols). Require a protein-DESIGN noun
            # (active-site/pocket redesign, enzyme variant, protein backbone/binder/scaffold,
            # de novo protein/enzyme). Small-molecule-for-a-protein asks (inhibitor/substrate/
            # ligand) are excluded — those are reinvent4 / docking, not protein design.
            _PROTEIN_DESIGN_PAT = re.compile(
                r'(?:'
                r'\b(?:design|redesign|propose|engineer|generate|create)\b[^.\n]{0,60}?\b(?:'
                r'active[- ]site|binding\s+pocket|enzyme\s+(?:variant|design|redesign|engineer\w*)|'
                r'protein\s+(?:backbone|binder|scaffold|sequence|fold|design)|'
                r'(?:de\s+novo|novel|new)\s+(?:protein|enzyme|binder|backbone)|'
                r'backbone\s+(?:\+|and)\s+sequence)\b'
                r'|\bde\s+novo\s+(?:protein|enzyme|binder|backbone)\b'
                r'|\bprotein\s+(?:backbone|binder|scaffold|sequence|fold)\s+design\b'
                r')',
                re.IGNORECASE,
            )
            _PROTEIN_DESIGN_EXCLUDE = re.compile(
                r'\b(antibod\w*|nanobod\w*|vhh|scfv|bispecific|peptide|macrocycl\w*|cyclic|stapled|'
                r'small[- ]molecule|compound|ligand|smiles|inhibitor\w*|substrate)\b',
                re.IGNORECASE,
            )
            if _PROTEIN_DESIGN_PAT.search(user_intent) and not _PROTEIN_DESIGN_EXCLUDE.search(user_intent):
                _hint = (
                    "\n[Routing hint: de novo design or active-site redesign of a PROTEIN or ENZYME "
                    "(backbone + sequence) — use bionemo_structure_design (registry id 14449, "
                    "RFdiffusion + ProteinMPNN), NOT profam (a variant-fitness SCORER that ranks "
                    "SUPPLIED variants and cannot propose new sequences)]"
                )
                user_intent = user_intent + _hint
                log.info("[UnifiedWorkflowGeneration] Protein/enzyme design pattern detected — injected bionemo_structure_design routing hint")

            # Generative/optimisation task: retrieval otherwise ranks on the property words that
            # come with it ("drug-like properties", hERG/MW cut-offs in the context) and returns
            # a property PREDICTOR. Measured 2026-11-03 (dev logs): "Generate candidates ... with
            # drug-like properties" and "Adapt the generative model ..." reached Step 1 search
            # (ADMET fast path not involved) and selected predict_admet_properties / ADMET_pred.
            if _generative_task:
                _task_low = self._request_task_text(user_intent).lower()
                if re.search(r'\b(peptides?|macrocycl\w*|cyclic|stapled)\b', _task_low):
                    _gen_wf = "cyclic_peptide_design (peptide/macrocycle design)"
                elif re.search(r'\b(antibod\w*|nanobod\w*|vhh|scfv|bispecific)\b', _task_low):
                    _gen_wf = "an antibody / nanobody design workflow"
                else:
                    _gen_wf = ("a small-molecule generative design workflow "
                               "(reinvent4_lead_design for generation / multi-objective optimisation, "
                               "a scaffold-hopping workflow for scaffold hops)")
                user_intent = user_intent + (
                    "\n[Routing hint: the task is to GENERATE or OPTIMISE molecules; property / ADMET "
                    f"criteria in the request are design objectives or constraints, not the task. Prefer {_gen_wf}, "
                    "NOT a property-prediction-only workflow, and NOT gromacs_pmx_fep / openfe_rbfe "
                    "(those are relative-FEP affinity engines, not generators).]"
                )
                log.info(
                    "[UnifiedWorkflowGeneration] Generative task (ADMET as constraint=%s) — injected generative-design hint",
                    _admet_as_constraint,
                )

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
                    user_input_kinds=user_input_kinds,
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

            # Relevance floor (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md §4): an unrelated
            # catalog hit must never be attached (mmuphin for a JSONL table; "Estimate Alpha Particle
            # Radiotherapy Dosimetry"). _classify_match's 12/6 cut-offs predate the current score
            # scale (junk tops score 18–41 and are labelled high_confidence), so a request whose best
            # hit is below the calibrated floor — or whose hit cannot take the user's data kind —
            # gets no workflow and an honest reason instead of a mismatched card.
            if search_results:
                _floor_verdict = workflow_relevance_verdict(
                    search_results, score,
                    input_compatible=lambda r: self.workflow_search.input_compatible(
                        user_intent, r.id, user_input_kinds=user_input_kinds) if getattr(r, 'id', None) is not None else None,
                )
                if _floor_verdict['reject']:
                    log.warning("[UnifiedWorkflowGeneration] relevance floor: %s", _floor_verdict['reason'])
                    return {
                        'success': False,
                        'error': 'no_relevant_workflow',
                        'message': _floor_verdict['message'],
                        'reason': _floor_verdict['reason'],
                        'candidate_workflows': [
                            {'name': m.name, 'domain': m.domain, 'score': round(m.score, 2)} for m in search_results[:3]
                        ],
                    }
                if _floor_verdict.get('promote') is not None:
                    best_match = _floor_verdict['promote']
                    score = best_match.score
                    match_type = best_match.match_type
                    search_results = [best_match] + [r for r in search_results if r is not best_match]

            workflow_ga = None
            source = None
            datasets_assigned = False
            generated_parameters = []  # Initialize for all paths

            # ── Disambiguation gate ──────────────────────────────────────────────
            # When no single dominant match exists and multiple plausible candidates
            # score within 3 points of each other, surface them for user selection
            # instead of silently committing to #1.
            # Thresholds match UnifiedWorkflowSearch._classify_match():
            #   _MATCH_SCORE_HIGH = 12.0  (high_confidence)
            #   _MATCH_SCORE_MED  = 6.0   (medium_confidence / plausible)
            _DISAMBIG_MIN_SCORE = 6.0
            _DISAMBIG_GAP_THRESHOLD = 3.0

            # Intent-driven override: when the user explicitly enumerates multiple
            # alternative methods (e.g. "DESeq2 or edgeR", "compare DESeq2 edgeR limma"),
            # the request is by definition ambiguous — even when BGE dense retrieval
            # produces a single high-confidence winner. Force disambig in that case
            # so the user can pick which method to actually run. The set is
            # intentionally narrow (well-known DE / DEG methods that often appear
            # as alternatives in bioc consensus chains) to avoid spurious triggers.
            # Extend cautiously as similar consensus-style patterns surface.
            _methods_mentioned, _enumerates_alternatives = _detect_alt_method_enumeration(
                user_intent
            )
            if _enumerates_alternatives and search_results:
                # Surface the top plausible matches (relax the score floor since the
                # intent signal alone justifies disambig). Prefer matches that mention
                # one of the named methods in name/description so the candidate list
                # actually reflects what the user asked to compare.
                def _method_in_match(m: Any) -> bool:
                    blob = (
                        (getattr(m, 'name', '') or '')
                        + ' '
                        + (getattr(m, 'description', '') or '')
                    ).lower()
                    return any(t in blob for t in _methods_mentioned)

                method_matches = [m for m in search_results if _method_in_match(m)]
                other_matches = [m for m in search_results if not _method_in_match(m)]
                ordered = method_matches + other_matches
                disambig_candidates = []
                for m in ordered[:4]:
                    disambig_candidates.append({
                        'name': m.name,
                        'display_name': getattr(m, 'display_name', None) or m.name,
                        'description': (getattr(m, 'description', None) or '')[:220],
                        'source': getattr(m, 'source', ''),
                        'format': getattr(m, 'format', ''),
                        'score': round(m.score, 2),
                    })
                if len(disambig_candidates) >= 2:
                    log.info(
                        "[UnifiedWorkflowGeneration] Disambiguation (alt-enumeration) — "
                        "methods=%s, candidates=%s",
                        _methods_mentioned, [c['name'] for c in disambig_candidates],
                    )
                    return {
                        'success': False,
                        'workflow_type': 'disambiguation',
                        'message': (
                            "You mentioned multiple methods (" + ", ".join(_methods_mentioned)
                            + "). Which workflow would you like to run?"
                        ),
                        'candidates': disambig_candidates,
                    }

            if search_results and match_type != 'high_confidence':
                plausible = [r for r in search_results if r.score >= _DISAMBIG_MIN_SCORE]
                if (len(plausible) >= 2
                        and (plausible[0].score - plausible[1].score) < _DISAMBIG_GAP_THRESHOLD):
                    # ADMET bypass: "admet" in the query unambiguously identifies
                    # predict_admet_properties regardless of where it sits in the ranking.
                    # The gap is narrow because other pharmacology workflows (docking, PK)
                    # also score well for drug-screening queries — NOT because the intent is
                    # ambiguous. Scan the full plausible list and promote predict_admet_properties
                    # to position 0 so routing falls through to _return_nextflow_match.
                    _admet_match = None
                    if re.search(r'\badmet\b', user_intent, re.IGNORECASE):
                        for _pm in plausible:
                            _pm_nm = (_pm.name or '').lower()
                            _pm_fn = (_pm.filename or '').lower()
                            # Name may be stored as 'predict_admet_properties' (underscores)
                            # or 'Predict Admet Properties' (spaces, Title Case) — match both.
                            _nm_has_admet = 'admet' in _pm_nm and (
                                'predict' in _pm_nm or 'screen' in _pm_nm
                            )
                            _fn_has_admet = 'predict_admet_properties' in _pm_fn
                            if _nm_has_admet or _fn_has_admet:
                                _admet_match = _pm
                                break

                    if _admet_match is not None:
                        log.info(
                            "[UnifiedWorkflowGeneration] Disambiguation bypass — ADMET query, "
                            "found %s at score=%.1f (gap=%.1f) — promoting to #1",
                            _admet_match.name, _admet_match.score,
                            plausible[0].score - plausible[1].score,
                        )
                        # Promote the ADMET workflow to position 0
                        search_results = (
                            [_admet_match]
                            + [r for r in search_results if r is not _admet_match]
                        )
                        best_match = _admet_match
                        score = _admet_match.score
                        match_type = _admet_match.match_type
                        executable_nextflow_match = self._pick_best_executable_nextflow_match(
                            search_results
                        )
                        # Fall through to Step 2 routing below
                    else:
                        disambig_candidates = []
                        for m in plausible[:4]:
                            disambig_candidates.append({
                                'name': m.name,
                                'display_name': getattr(m, 'display_name', None) or m.name,
                                'description': (getattr(m, 'description', None) or '')[:220],
                                'source': getattr(m, 'source', ''),
                                'format': getattr(m, 'format', ''),
                                'score': round(m.score, 2),
                            })
                        log.info(
                            "[UnifiedWorkflowGeneration] Disambiguation — %d plausible candidates "
                            "(gap=%.1f < %.1f): %s",
                            len(plausible), plausible[0].score - plausible[1].score,
                            _DISAMBIG_GAP_THRESHOLD, [c['name'] for c in disambig_candidates],
                        )
                        return {
                            'success': False,
                            'workflow_type': 'disambiguation',
                            'message': (
                                "I found several workflows that could match your request. "
                                "Which best fits what you need?"
                            ),
                            'candidates': disambig_candidates,
                        }

            # Step 2: Decide strategy based on template match confidence
            # match_type is set by UnifiedWorkflowSearch._classify_match():
            #   high_confidence  : score >= 12.0  → reuse workflow as-is
            #   medium_confidence: score >= 6.0   → adapt template or compose via NextflowComposer
            #   low_confidence / no_match         → compose from scratch via NextflowComposer

            # ── LLM routing verification (rationale + self-audit) ────────────────
            # For medium_confidence and high_confidence cases where the top-2 gap is
            # narrow (< 8 points), ask the LLM to confirm the top pick and flag obvious
            # mismatches (wrong assay type, wrong data scope, irrelevant domain).
            # temperature=0 → deterministic; adds an audit trail to every routing decision.
            _routing_audit: Dict[str, Any] = {}
            if search_results and match_type in ("high_confidence", "medium_confidence"):
                _top2_gap = (search_results[0].score - search_results[1].score
                             if len(search_results) >= 2 else 999)
                _needs_verify = (
                    match_type == "medium_confidence"              # always verify borderline
                    or _top2_gap < 8.0                            # close race even at high_confidence
                )
                # Trust nfcore pipeline over bioconductor subworkflow in a close race.
                # When #1 is a full nf-core pipeline and #2 is a bioconductor subworkflow,
                # the subworkflow has already been penalised by the scoring function for
                # being a single-step component (not an end-to-end pipeline). Letting the
                # LLM verify override would undo that principled penalty. Safe to skip.
                if _needs_verify and len(search_results) >= 2:
                    _r1 = search_results[0]
                    _r2 = search_results[1]
                    _r1_is_nfcore_pipeline = (
                        getattr(_r1, 'source', '') == 'nfcore'
                        and getattr(_r1, 'format', '') == 'nextflow'
                        and '/subworkflows/' not in (getattr(_r1, 'filename', '') or '')
                    )
                    _r2_is_bioc_subwf = (
                        getattr(_r2, 'source', '') == 'bioconductor'
                        and '/subworkflows/' in (getattr(_r2, 'filename', '') or '')
                    )
                    if _r1_is_nfcore_pipeline and _r2_is_bioc_subwf:
                        _needs_verify = False
                        log.info(
                            "[UnifiedWorkflowGeneration] Skipping LLM routing verify — "
                            "#1 is nfcore pipeline (%s) leading bioconductor subworkflow (%s); "
                            "subworkflow penalty already applied in scoring.",
                            _r1.name, _r2.name,
                        )
                    # Extended guard: bioconductor subworkflow anywhere in top-N.
                    # The FTS subworkflow penalty (-8) already demoted it; allowing the
                    # LLM verifier to pick it from position 3+ undoes that principled penalty.
                    if _needs_verify and _r1_is_nfcore_pipeline:
                        _any_bioc_subwf = any(
                            getattr(r, 'source', '') == 'bioconductor'
                            and '/subworkflows/' in (getattr(r, 'filename', '') or '')
                            for r in search_results[1:]
                        )
                        if _any_bioc_subwf:
                            _needs_verify = False
                            log.info(
                                "[UnifiedWorkflowGeneration] Skipping LLM routing verify — "
                                "#1 is nfcore pipeline (%s) and bioconductor subworkflow(s) "
                                "present in top-N; subworkflow penalty already applied.",
                                _r1.name,
                            )
                # User named an nf-core slug explicitly — trust the explicit name over
                # semantic search ranking and LLM verify.
                _explicit_slug = self.workflow_search._extract_explicit_pipeline_slug(user_intent)
                if _explicit_slug:
                    _top_slug = self.workflow_search._normalise_pipeline_slug(
                        search_results[0].name.split("/")[-1]
                    )
                    if _top_slug == _explicit_slug:
                        _needs_verify = False
                        log.info(
                            "[UnifiedWorkflowGeneration] Skipping LLM routing verify — "
                            "explicit slug %r matches top hit %s",
                            _explicit_slug,
                            search_results[0].name,
                        )
                    else:
                        # Explicit slug is NOT at position 0 — scan the rest and promote it.
                        # Without promotion the LLM verify step can override to a semantically
                        # similar but wrong workflow (e.g. Bioconductor DESeq2 when the user
                        # explicitly names nf-core/differentialabundance).
                        _matched_idx = None
                        for _scan_idx, _scan_r in enumerate(search_results[1:], start=1):
                            _scan_slug = self.workflow_search._normalise_pipeline_slug(
                                _scan_r.name.split("/")[-1]
                            )
                            if _scan_slug == _explicit_slug:
                                _matched_idx = _scan_idx
                                break
                        if _matched_idx is not None:
                            search_results = (
                                [search_results[_matched_idx]]
                                + [r for i, r in enumerate(search_results) if i != _matched_idx]
                            )
                            best_match = search_results[0]
                            score = best_match.score
                            match_type = best_match.match_type
                            executable_nextflow_match = self._pick_best_executable_nextflow_match(
                                search_results
                            )
                            _needs_verify = False
                            log.info(
                                "[UnifiedWorkflowGeneration] Skipping LLM routing verify — "
                                "explicit slug %r found at position %d, promoted to #1: %s",
                                _explicit_slug, _matched_idx, search_results[0].name,
                            )
                # Plan B: trust retrieval when codon/mRNA intent matches a codon subworkflow top hit.
                # LLM verify has overridden #1 → mhcquant/epitopeprediction when the query
                # mentions vaccine/ANDV context.
                if _needs_verify and search_results:
                    _q_low = user_intent.lower()
                    _explicit_registry_10813 = bool(
                        re.search(r'\b10813\b', _q_low)
                        or 'optimize_codons_for_heterologous_expression' in _q_low
                    )
                    if _explicit_registry_10813:
                        _needs_verify = False
                        log.info(
                            "[UnifiedWorkflowGeneration] Skipping LLM routing verify — "
                            "explicit Plan B registry 10813 / optimize_codons in query"
                        )
                if _needs_verify:
                    _routing_audit = self._llm_verify_routing(
                        user_intent, search_results, match_type
                    )
                    if _routing_audit.get("flag") and _routing_audit.get("selected_idx", 0) != 0:
                        _override_idx = _routing_audit["selected_idx"]
                        _override = search_results[_override_idx]
                        log.info(
                            "[UnifiedWorkflowGeneration] LLM audit overriding #1 (%s) → #%d (%s). "
                            "Reason: %s",
                            search_results[0].name, _override_idx + 1, _override.name,
                            _routing_audit.get("audit", ""),
                        )
                        # Rebuild search_results with override at position 0
                        search_results = (
                            [_override]
                            + [r for i, r in enumerate(search_results) if i != _override_idx]
                        )
                        best_match = search_results[0]
                        score = best_match.score
                        match_type = best_match.match_type
                        executable_nextflow_match = self._pick_best_executable_nextflow_match(
                            search_results
                        )

            if match_type == "high_confidence":
                # High confidence - reuse existing workflow
                log.info("[UnifiedWorkflowGeneration] High confidence match - reusing workflow")
                best_match = search_results[0]
                source = 'template_reuse'

                # Check if this is a Nextflow workflow
                if best_match.format == 'nextflow':
                    if not self._is_executable_nextflow_match(best_match):
                        # Only swap to executable_nextflow_match when it represents the
                        # SAME pipeline (e.g. a subworkflow has an executable variant in
                        # the same file tree). If the two workflows are semantically
                        # different (different name core, different domain) the swap would
                        # silently return the wrong workflow — better to keep the best
                        # semantic match and let the execution layer adapt it.
                        def _same_pipeline(a: Any, b: Any) -> bool:
                            def _slug(m: Any) -> str:
                                n = (getattr(m, 'name', '') or '').lower()
                                return n.split('/')[-1].replace('-', '').replace('_', '')
                            return bool(_slug(a) and _slug(a) == _slug(b))

                        if executable_nextflow_match and _same_pipeline(best_match, executable_nextflow_match):
                            log.warning(
                                "[UnifiedWorkflowGeneration] Top Nextflow match is non-executable "
                                f"subworkflow ({best_match.filename}); using executable variant "
                                f"{executable_nextflow_match.filename}"
                            )
                            best_match = executable_nextflow_match
                            score = best_match.score
                        else:
                            # No same-pipeline executable variant.
                            # If the non-executable match is an nfcore/subworkflows/ COMPONENT
                            # (not a stub pipeline), routing to it will always fail at generation
                            # time — fall back to the best available executable match instead.
                            _fn = getattr(best_match, 'filename', '') or ''
                            if '/subworkflows/' in _fn and executable_nextflow_match:
                                log.warning(
                                    "[UnifiedWorkflowGeneration] Top Nextflow match (%s) is an "
                                    "nfcore subworkflow component — falling back to best "
                                    "executable match (%s).",
                                    best_match.name, executable_nextflow_match.name,
                                )
                                best_match = executable_nextflow_match
                                score = best_match.score
                            else:
                                # Non-subworkflow non-executable (e.g. stub pipeline without
                                # workflow{} block) — keep as routing result, execution layer adapts.
                                log.warning(
                                    "[UnifiedWorkflowGeneration] Top Nextflow match (%s) failed "
                                    "executability check but no same-pipeline executable variant "
                                    "found; keeping as routing result — execution layer must adapt.",
                                    best_match.name,
                                )

                if match_type == "high_confidence" and best_match and best_match.format == 'nextflow':
                    # ── Credential gate: if the matched workflow requires a license/API key
                    # that isn't configured, prompt the user to enter their credentials or
                    # switch to a free alternative instead of silently falling back.
                    # Mapping: workflow-name fragment → (credential_map key, fallback spec)
                    # fallback spec: (workflow_name_hint, extra_params_dict)
                    _CRED_GATE = {
                        "boltz":      ("boltz2",     ("structure_prediction", {"method": "chai1"})),
                        "alphafold3": ("alphafold3",  ("structure_prediction", {"method": "chai1"})),
                        "alphafold":  ("alphafold3",  ("structure_prediction", {"method": "chai1"})),
                        "chai1":      ("chai1",       ("structure_prediction", {"method": "esmfold"})),
                    }
                    _TOOL_DISPLAY_NAMES = {
                        "boltz2": "Boltz-2",
                        "alphafold3": "AlphaFold 3",
                        "chai1": "Chai-1",
                        "esmfold": "ESMFold",
                    }
                    if credential_map:
                        _match_stem = (getattr(best_match, 'name', '') or '').lower()
                        for _frag, (_cred_key, _fallback) in _CRED_GATE.items():
                            if _frag in _match_stem and not credential_map.get(_cred_key, True):
                                _fb_name, _fb_params = _fallback
                                _fb_cred_key = _fb_params.get("method")  # chai1 / esmfold
                                _fb_cred_ok = credential_map.get(_fb_cred_key, True)
                                # If neither the tool NOR its fallback is available, keep the
                                # original match so the user at least sees the right name.
                                if _fb_cred_ok:
                                    _tool_disp = _TOOL_DISPLAY_NAMES.get(_cred_key, _frag.title())
                                    _fb_disp   = _TOOL_DISPLAY_NAMES.get(_fb_cred_key or '', (_fb_cred_key or '').title())
                                    log.info(
                                        "[UnifiedWorkflowGeneration] credential gate: %s requires "
                                        "%s — returning credential_required prompt (fallback=%s)",
                                        best_match.name, _cred_key, _fb_cred_key,
                                    )
                                    return {
                                        'success': False,
                                        'workflow_type': 'credential_required',
                                        'missing_credential': _cred_key,
                                        'tool_name': _tool_disp,
                                        'fallback_method': _fb_cred_key,
                                        'fallback_name': _fb_disp,
                                        'message': (
                                            f"{_tool_disp} requires an API key or license that hasn't been configured. "
                                            f"You can enter your credentials to run with {_tool_disp}, "
                                            f"or switch to {_fb_disp} (available on this deployment)."
                                        ),
                                    }
                                break

                    log.info(f"[UnifiedWorkflowGeneration] High-confidence Nextflow match: {best_match.filename}")
                    result = self._return_nextflow_match(
                        match=best_match, score=score, user_intent=user_intent,
                        source='template_reuse', needs_user_feedback=False,
                        search_results=search_results, selected_trial=selected_trial, trials=trials,
                        uploaded_datasets=uploaded_datasets,
                    )
                    if _routing_audit:
                        result['routing_rationale'] = _routing_audit.get('rationale', '')
                        result['routing_audit'] = _routing_audit.get('audit', '')
                        result['routing_audit_flag'] = _routing_audit.get('flag', False)
                    return result

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
                    _raw = workflow_json['steps']
                    if isinstance(_raw, dict):
                        for step_id, step_data in _raw.items():
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
                    result = self._return_nextflow_match(
                        match=best_match, score=score, user_intent=user_intent,
                        source='template_adapt', needs_user_feedback=True,
                        search_results=search_results, selected_trial=selected_trial, trials=trials,
                        uploaded_datasets=uploaded_datasets,
                    )
                    if _routing_audit:
                        result['routing_rationale'] = _routing_audit.get('rationale', '')
                        result['routing_audit'] = _routing_audit.get('audit', '')
                        result['routing_audit_flag'] = _routing_audit.get('flag', False)
                    return result

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
                        'source': composed.get('source', 'template_compose'),
                        'cache_hit': composed.get('cache_hit', False),
                        'confidence': int(score),
                        'template_match_score': int(score),
                        'needs_user_feedback': True,
                        'feedback_prompt': (
                            f"I adapted a reference workflow ('{best_match.name}') as a starting point. "
                            "Please review the tool selection before running."
                        ),
                        'message': composed.get('message', f"Composed Nextflow workflow: {composed.get('workflow_name', best_match.name)}"),
                        'workflow_ga': {
                            'name': composed['workflow_name'],
                            'description': user_intent,
                            'format': 'nextflow',
                            'nextflow_path': composed['nextflow_path'],
                            'workflow_type': 'nextflow',
                            'steps': _eager_load_steps(composed['nextflow_path']),
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
                    # Build scientific rationale for composed tools so the response LLM
                    # has DB-verified context about the selected tools' constraints and pitfalls.
                    _composed_rationale = self._build_scientific_rationale(
                        composed['nextflow_path'],
                        composed['workflow_name'],
                        composed.get('tools_used', []),
                    )
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
                        'scientific_rationale': _composed_rationale,
                        'workflow_ga': {
                            'name': composed['workflow_name'],
                            'description': f"Composed Nextflow workflow for: {user_intent}",
                            'format': 'nextflow',
                            'nextflow_path': composed['nextflow_path'],
                            'workflow_type': 'nextflow',
                            'steps': _eager_load_steps(composed['nextflow_path']),
                            'tools_used': composed['tools_used'],
                            'required_params': _req_lc,
                            'optional_params': _opt_lc,
                            'scientific_rationale': _composed_rationale,
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
            # Only hits that clear the relevance floor are candidates: the chat layer may move
            # the card to a candidate the reply names (Step 6c / 6c-2), and a below-floor hit
            # there re-opened the path the floor closes (mismatched card via the text guardrail).
            candidate_workflows = [
                {
                    'name': m.name,
                    'domain': m.domain,
                    'source': m.source,
                    'score': m.score,
                    'format': m.format,
                }
                for m in relevant_candidates(search_results)
            ]

            # A match whose template has no steps (no workflow_json, no nextflow_path) is not a
            # workflow. Returning it as success produced the empty "Custom workflow" card (0 phases)
            # that also disabled run_code for the turn (2026-11-10 EPAR test).
            if not ((workflow_ga or {}).get('steps') or {}):
                log.warning("[UnifiedWorkflowGeneration] built workflow has no steps — returning no_runnable_workflow")
                return {
                    'success': False,
                    'error': 'no_runnable_workflow',
                    'message': 'No runnable workflow matched this request.',
                    'candidate_workflows': candidate_workflows,
                }

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
        workflow_name = _composed_workflow_name(template)
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
        workflow_name = _composed_workflow_name(workflow_data)
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
                    # {'default': X} is the workflow's OWN .nf default copied into the knowledge
                    # table, not a recommendation: surfacing it as one marked test-data examples
                    # (e.g. aspirin SMILES) as "推荐" and told the chat model the user supplied them
                    # (founder 2026-11-12). Only real recommendations become hints.
                    if isinstance(rv, dict) and set(rv.keys()) <= {"default"}:
                        continue
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

    # =========================================================================
    # Track 3A — Comprehensive Biological Database Query
    # =========================================================================

    def _get_ref_redis(self):
        """Lazily return a Redis client for the reference cache, or None if
        unavailable. Redis lets the cache survive gunicorn worker recycles
        (~3 min on dev) and be shared across workers. Fully optional — any
        failure (no REDIS_URL, missing package, unreachable) yields None and the
        cache degrades to in-process only. Reuses the billing/RunState pattern.
        """
        r = getattr(self, '_ref_redis', 'unset')
        if r != 'unset':
            return r
        client = None
        try:
            import os as _os
            url = _os.environ.get('REDIS_URL')
            if url:
                import redis as _redis
                client = _redis.from_url(url, decode_responses=True, socket_timeout=2)
                client.ping()
        except Exception:
            client = None
        self._ref_redis = client
        return client

    def _cached_fetch(self, key: str, producer, ttl: Optional[int] = None):
        """Run producer() and cache its non-None result under `key` for `ttl`s.

        Two-tier TTL cache for near-static external reference lookups (GET-JSON,
        POST-JSON, raw-text): in-process first, then Redis (survives worker
        recycles + shared across workers), then the producer. Only successful
        (non-None) results are cached (failures retry); the in-process store is
        size-bounded. Redis is optional and every Redis op falls back silently.
        """
        import time as _time
        import json as _json
        cache = getattr(self, '_ref_http_cache', None)
        if cache is None:
            cache = self._ref_http_cache = {}
        if ttl is None:
            ttl = getattr(self, '_ref_http_cache_ttl', 21600)  # 6h — reference data is near-static
        now = _time.time()

        # Tier 1: in-process (fastest).
        hit = cache.get(key)
        if hit is not None and (now - hit[0]) < ttl:
            return hit[1]

        # Tier 2: Redis (survives the ~3-min worker recycle; shared across workers).
        rkey = 'biomate:refcache:' + key
        rc = self._get_ref_redis()
        if rc is not None:
            try:
                raw = rc.get(rkey)
                if raw is not None:
                    val = _json.loads(raw)
                    cache[key] = (now, val)  # warm the in-process tier
                    return val
            except Exception:
                pass

        # Tier 3: produce, then populate both tiers.
        result = producer()
        if result is not None:  # cache successes only; failures retry next time
            if len(cache) >= 512:
                for k in sorted(cache, key=lambda kk: cache[kk][0])[:256]:
                    cache.pop(k, None)
            cache[key] = (now, result)
            if rc is not None:
                try:
                    rc.setex(rkey, int(ttl), _json.dumps(result))
                except Exception:
                    pass
        return result

    def _http_get_json(self, url: str, headers: Optional[Dict] = None) -> Optional[Dict]:
        """Shared HTTP GET helper that returns parsed JSON or None on error.

        Cached via _cached_fetch (TTL): external reference lookups
        (UniProt/PDB/AlphaFold/KEGG/Ensembl/STRING/ChEBI/ChEMBL/InterPro) are
        near-static, so a cache hit skips the 10s-timeout-bounded round-trip.
        """
        import urllib.request
        import json as _json

        key = url if not headers else url + '|' + repr(sorted(headers.items()))

        def _fetch():
            default_headers = {'User-Agent': 'BioMate/1.0 (biomate.ai; ai-assistant)'}
            if headers:
                default_headers.update(headers)
            req = urllib.request.Request(url, headers=default_headers)
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    return _json.loads(resp.read().decode())
            except Exception as e:
                import logging as _log
                _log.getLogger(__name__).debug(f"[DB query] HTTP GET failed for {url}: {e}")
                return None

        return self._cached_fetch(key, _fetch)

    def _query_uniprot(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = (f"https://rest.uniprot.org/uniprotkb/search"
               f"?query={q}+AND+reviewed:true&format=json&size=5")
        data = self._http_get_json(url)
        if not data:
            return {"source": "uniprot", "results": [], "error": "no_response"}
        results = []
        for entry in data.get('results', [])[:5]:
            results.append({
                "accession": entry.get('primaryAccession'),
                "name": entry.get('uniProtkbId'),
                "organism": (entry.get('organism') or {}).get('scientificName'),
                "function": next(
                    (c.get('texts', [{}])[0].get('value') for c in entry.get('comments', [])
                     if c.get('commentType') == 'FUNCTION'), None
                ),
            })
        return {"source": "uniprot", "query": query, "results": results,
                "total": data.get('totalResults', len(results))}

    def _query_ncbi_gene(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        search_url = (f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
                      f"?db=gene&term={q}&retmode=json&retmax=5")
        search = self._http_get_json(search_url)
        if not search:
            return {"source": "ncbi_gene", "results": [], "error": "no_response"}
        ids = search.get('esearchresult', {}).get('idlist', [])[:5]
        if not ids:
            return {"source": "ncbi_gene", "query": query, "results": [],
                    "total": int(search.get('esearchresult', {}).get('count', 0))}
        id_str = ','.join(ids)
        summary_url = (f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
                       f"?db=gene&id={id_str}&retmode=json")
        summary = self._http_get_json(summary_url)
        results = []
        if summary:
            for gid in ids:
                g = summary.get('result', {}).get(gid, {})
                if g:
                    results.append({
                        "gene_id": gid,
                        "symbol": g.get('name'),
                        "description": g.get('description'),
                        "organism": g.get('organism', {}).get('scientificname'),
                        "chromosome": g.get('chromosome'),
                    })
        return {"source": "ncbi_gene", "query": query, "results": results,
                "total": int(search.get('esearchresult', {}).get('count', 0))}

    def _query_ncbi_entrez(self, query: str, db: str = 'pubmed') -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = (f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
               f"?db={db}&term={q}&retmode=json&retmax=5")
        data = self._http_get_json(url)
        if not data:
            return {"source": db, "results": [], "error": "no_response"}
        sr = data.get('esearchresult', {})
        return {"source": db, "query": query,
                "ids": sr.get('idlist', []), "total": int(sr.get('count', 0))}

    def _query_pdb(self, query: str, operation: str = 'lookup') -> Dict:
        """RCSB PDB. operation drives the mode (chosen from user intent by the LLM):
        'similarity' -> full-scale sequence-similarity search across the entire PDB;
        'text' -> keyword search; 'lookup' (default) -> entry lookup by 4-char PDB ID
        (falls through to text search when the query is not a PDB ID)."""
        import urllib.parse, re, json as _json
        op = (operation or 'lookup').lower()

        # Intent = similarity: sequence homolog search across the whole PDB.
        if op in ('similarity', 'sequence', 'homolog'):
            seq = re.sub(r'\s+', '', query).upper()
            body = {"query": {"type": "terminal", "service": "sequence",
                              "parameters": {"evalue_cutoff": 1, "identity_cutoff": 0.3,
                                             "sequence_type": "protein", "value": seq}},
                    "return_type": "polymer_entity",
                    "request_options": {"paginate": {"start": 0, "rows": 10}}}
            url = ("https://search.rcsb.org/rcsbsearch/v2/query?json="
                   + urllib.parse.quote(_json.dumps(body)))
            data = self._http_get_json(url)
            hits = [{"entity_id": e.get('identifier'), "score": round(e.get('score', 0), 3)}
                    for e in (data or {}).get('result_set', [])[:10]]
            return {"source": "pdb", "search": "sequence_similarity",
                    "total_hits": (data or {}).get('total_count', 0), "results": hits}

        # Intent = lookup: direct entry lookup for a 4-char PDB ID.
        if op == 'lookup' and re.match(r'^[A-Za-z0-9]{4}$', query.strip()) and not query.strip().isalpha():
            pdb_id = query.strip().upper()
            data = self._http_get_json(f"https://data.rcsb.org/rest/v1/core/entry/{pdb_id}")
            if data:
                struct = data.get('struct', {})
                return {"source": "pdb", "pdb_id": pdb_id,
                        "title": struct.get('title'),
                        "resolution": data.get('refine', [{}])[0].get('ls_d_res_high'),
                        "method": data.get('exptl', [{}])[0].get('method')}

        # Intent = text (or lookup fallthrough): full-text search.
        url = (f"https://search.rcsb.org/rcsbsearch/v2/query?json="
               f'{{"query":{{"type":"terminal","service":"full_text","parameters":{{"value":"{query}"}}}},"return_type":"entry","request_options":{{"paginate":{{"start":0,"rows":5}}}}}}')
        data = self._http_get_json(url)
        results = [{"pdb_id": e.get('identifier'), "score": e.get('score')}
                   for e in (data or {}).get('result_set', [])[:5]]
        return {"source": "pdb", "query": query, "results": results}

    def _query_alphafold(self, query: str) -> Dict:
        import re
        # UniProt accession pattern
        if re.match(r'^[A-Z][0-9][A-Z0-9]{3}[0-9]$', query.strip().upper()):
            acc = query.strip().upper()
            data = self._http_get_json(f"https://alphafold.ebi.ac.uk/api/prediction/{acc}")
            if data and isinstance(data, list) and data:
                d = data[0]
                return {"source": "alphafold", "uniprot_accession": acc,
                        "model_url": d.get('pdbUrl'),
                        "pae_image_url": d.get('paeImageUrl'),
                        "confidence_metric": "pLDDT"}
        return {"source": "alphafold", "query": query, "note": "Provide UniProt accession for direct lookup"}

    def _query_kegg(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = f"https://rest.kegg.jp/find/pathway/{q}"
        # KEGG returns plain TSV text (not JSON) — fetch once (cached) and parse.
        def _fetch_text():
            import urllib.request
            try:
                with urllib.request.urlopen(url, timeout=10) as resp:
                    return resp.read().decode()
            except Exception:
                return None
        text = self._cached_fetch("kegg_text:" + url, _fetch_text)
        results = []
        if text:
            for line in text.strip().split('\n')[:5]:
                if '\t' in line:
                    pid, name = line.split('\t', 1)
                    results.append({"pathway_id": pid, "name": name})
        return {"source": "kegg", "query": query, "results": results}

    def _query_ensembl(self, query: str) -> Dict:
        import urllib.parse, re
        headers = {"Content-Type": "application/json"}
        # Try gene symbol lookup
        if re.match(r'^[A-Z][A-Z0-9]+$', query.strip()):
            url = (f"https://rest.ensembl.org/xrefs/symbol/homo_sapiens/{urllib.parse.quote(query)}"
                   f"?content-type=application/json")
            data = self._http_get_json(url)
            if data:
                return {"source": "ensembl", "query": query,
                        "results": [{"id": e.get("id"), "type": e.get("type")} for e in data[:5]]}
        return {"source": "ensembl", "query": query, "results": []}

    def _query_reactome(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = f"https://reactome.org/ContentService/search/query?query={q}&types=Pathway&pageSize=5&page=1"
        data = self._http_get_json(url)
        results = []
        if data:
            for r in data.get('results', [])[:5]:
                for entry in r.get('entries', [])[:3]:
                    results.append({
                        "id": entry.get("stId"),
                        "name": entry.get("name"),
                        "species": entry.get("species", ["Homo sapiens"])[0] if entry.get("species") else None,
                    })
        return {"source": "reactome", "query": query, "results": results}

    def _query_string(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = (f"https://string-db.org/api/json/get_string_ids"
               f"?identifiers={q}&species=9606&limit=5&caller_identity=biomate")
        data = self._http_get_json(url)
        if not data:
            return {"source": "string", "results": [], "error": "no_response"}
        results = [{"protein_id": p.get("stringId"), "gene": p.get("preferredName"),
                    "score": p.get("score")} for p in data[:5]]
        return {"source": "string", "query": query, "results": results}

    def _query_gnomad(self, query: str) -> Dict:
        import json as _json, urllib.request, urllib.error
        gql = """
        query ($term: String!) {
          search(query: $term) {
            ... on GeneSearchResult { gene { gene_id gene_name } }
            ... on VariantSearchResult { variant { variant_id } }
          }
        }
        """
        # POST (GraphQL) — cached via _cached_fetch keyed on the query term.
        def _fetch():
            payload = _json.dumps({"query": gql, "variables": {"term": query}}).encode()
            req = urllib.request.Request(
                "https://gnomad.broadinstitute.org/api",
                data=payload,
                headers={"Content-Type": "application/json",
                         "User-Agent": "BioMate/1.0"}
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = _json.loads(resp.read().decode())
                    return data.get('data', {}).get('search', [])
            except Exception:
                return None
        results = self._cached_fetch("gnomad_post:" + query, _fetch)
        if results is None:
            return {"source": "gnomad", "query": query, "error": "no_response"}
        return {"source": "gnomad", "query": query, "results": results[:5]}

    def _query_go(self, query: str) -> Dict:
        import urllib.parse, re
        # GO term direct lookup
        if re.match(r'^GO:\d+$', query.strip(), re.IGNORECASE):
            goid = query.strip().upper()
            data = self._http_get_json(f"https://api.geneontology.org/api/ontology/term/{goid}")
            if data:
                return {"source": "go", "go_id": goid,
                        "name": data.get("label"),
                        "definition": (data.get("definition") or {}).get("val")}
        # Text search
        q = urllib.parse.quote(query)
        url = f"https://api.geneontology.org/api/search/entity/autocomplete/{q}?rows=5&ontology=go"
        data = self._http_get_json(url)
        results = []
        if data:
            for d in data.get('docs', [])[:5]:
                results.append({"go_id": d.get("id"), "name": d.get("label")})
        return {"source": "go", "query": query, "results": results}

    def _query_hpo(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = f"https://hpo.jax.org/api/hpo/search?q={q}&max=5&offset=0&category=terms"
        data = self._http_get_json(url)
        results = []
        if data:
            for t in data.get('terms', [])[:5]:
                results.append({"hpo_id": t.get("id"), "name": t.get("name"),
                                 "definition": t.get("definition")})
        return {"source": "hpo", "query": query, "results": results}

    def _query_chebi(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = f"https://www.ebi.ac.uk/chebi/searchId.do?chebiId={q}&format=json"
        data = self._http_get_json(url)
        if not data:
            # Text search fallback
            url2 = f"https://www.ebi.ac.uk/webservices/chebi/2.0/lite?search={q}&max_results=5"
            data = self._http_get_json(url2)
        return {"source": "chebi", "query": query, "results": data or []}

    def _query_chembl(self, query: str, operation: str = 'lookup',
                      similarity_threshold: int = 80) -> Dict:
        """ChEMBL. operation drives the mode (chosen from user intent by the LLM):
        'similarity' -> full-scale Tanimoto similarity search across all of ChEMBL
        (query is a SMILES); 'lookup'/'text' (default) -> compound name/ID search."""
        import urllib.parse, re
        op = (operation or 'lookup').lower()

        # Intent = similarity: chemical (Tanimoto) search over all of ChEMBL.
        if op in ('similarity', 'tanimoto'):
            smiles = re.sub(r'^\s*smiles[:=]\s*', '', query, flags=re.IGNORECASE).strip()
            enc = urllib.parse.quote(smiles, safe='')
            url = (f"https://www.ebi.ac.uk/chembl/api/data/similarity/{enc}/"
                   f"{int(similarity_threshold)}?format=json&limit=10")
            data = self._http_get_json(url)
            results = []
            if data:
                for m in data.get('molecules', [])[:10]:
                    results.append({
                        "chembl_id": m.get('molecule_chembl_id'),
                        "name": m.get('pref_name'),
                        "similarity": round(float(m.get('similarity', 0)), 1),
                    })
            return {"source": "chembl", "query": smiles, "search": "tanimoto_similarity",
                    "threshold": similarity_threshold, "results": results}
        # Name/text search
        q = urllib.parse.quote(query)
        url = (f"https://www.ebi.ac.uk/chembl/api/data/molecule/search"
               f"?q={q}&format=json&limit=5")
        data = self._http_get_json(url)
        results = []
        if data:
            for m in data.get('molecules', [])[:5]:
                props = m.get('molecule_properties') or {}
                results.append({
                    "chembl_id": m.get('molecule_chembl_id'),
                    "name": m.get('pref_name'),
                    "formula": props.get('full_molformula'),
                    "mw": props.get('full_mwt'),
                })
        return {"source": "chembl", "query": query, "results": results}

    def _query_pubchem(self, query: str, operation: str = 'lookup') -> Dict:
        """PubChem PUG-REST. operation drives the mode (chosen from user intent):
        'similarity' -> 2D similarity search across PubChem by SMILES; 'lookup'
        (default) -> compound lookup by name or CID (CID, IUPAC name, formula, MW,
        canonical SMILES)."""
        import urllib.parse, re
        op = (operation or 'lookup').lower()
        base = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"

        # Intent = similarity: 2D (Tanimoto) similarity search by SMILES.
        if op in ('similarity', 'tanimoto'):
            smiles = re.sub(r'^\s*smiles[:=]\s*', '', query, flags=re.IGNORECASE).strip()
            enc = urllib.parse.quote(smiles, safe='')
            url = (f"{base}/compound/fastsimilarity_2d/smiles/{enc}/cids/JSON"
                   f"?Threshold=90&MaxRecords=10")
            data = self._http_get_json(url)
            cids = ((data or {}).get('IdentifierList') or {}).get('CID', [])[:10]
            return {"source": "pubchem", "query": smiles, "search": "similarity_2d",
                    "threshold": 90, "results": [{"cid": c} for c in cids]}

        # Intent = lookup: compound by name or CID.
        term = query.strip()
        selector = 'cid' if re.match(r'^\d+$', term) else 'name'
        enc = urllib.parse.quote(term, safe='')
        url = (f"{base}/compound/{selector}/{enc}/property/"
               f"IUPACName,MolecularFormula,MolecularWeight,ConnectivitySMILES/JSON")
        data = self._http_get_json(url)
        props = (((data or {}).get('PropertyTable') or {}).get('Properties') or [])
        results = []
        for p in props[:5]:
            results.append({
                "cid": p.get('CID'),
                "iupac_name": p.get('IUPACName'),
                "formula": p.get('MolecularFormula'),
                "mw": p.get('MolecularWeight'),
                "smiles": p.get('ConnectivitySMILES') or p.get('CanonicalSMILES'),
            })
        return {"source": "pubchem", "query": query, "results": results}

    def _query_bindingdb(self, query: str, operation: str = 'lookup') -> Dict:
        """BindingDB REST. Measured binding affinities (Ki/Kd/IC50). Query is a
        UniProt accession (returns ligands for that target) — the documented
        getLigandsByUniprots endpoint returns affinity + SMILES + PMID rows."""
        import urllib.parse, re
        term = query.strip()
        # UniProt accession -> ligands (affinities) for that target.
        if re.match(r'^([OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2})$', term.upper()):
            acc = term.upper()
            url = (f"https://bindingdb.org/rest/getLigandsByUniprots"
                   f"?uniprot={urllib.parse.quote(acc)}"
                   f"&cutoff=10000&code=2&response=application/json")
            # BindingDB responses can be large/slow (100s of KB) — the shared
            # _http_get_json 10s timeout is too tight, so fetch with 30s here
            # (cached via _cached_fetch, mirroring _query_gnomad/_query_kegg).
            def _fetch():
                import urllib.request, json as _json
                req = urllib.request.Request(
                    url, headers={'User-Agent': 'BioMate/1.0 (biomate.ai; ai-assistant)'})
                try:
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        return _json.loads(resp.read().decode())
                except Exception:
                    return None
            data = self._cached_fetch("bindingdb_get:" + url, _fetch)
            # BindingDB's documented response key (their spelling).
            resp = (data or {}).get('getLindsByUniprotsResponse') \
                or (data or {}).get('getLigandsByUniprotsResponse') or {}
            affinities = resp.get('affinities', [])
            if isinstance(affinities, dict):
                affinities = [affinities]
            results = []
            for a in affinities[:10]:
                results.append({
                    "target": a.get('query'),
                    "monomer_id": a.get('monomerid'),
                    "smiles": a.get('smile'),
                    "affinity_type": a.get('affinity_type'),
                    "affinity_nM": a.get('affinity'),
                    "pmid": a.get('pmid'),
                    "doi": a.get('doi'),
                })
            return {"source": "bindingdb", "query": acc, "target_uniprot": acc,
                    "results": results, "total": len(affinities)}
        return {"source": "bindingdb", "query": query, "results": [],
                "note": "Provide a UniProt accession (target) for affinity lookup"}

    def _query_pharos(self, query: str, operation: str = 'lookup') -> Dict:
        """Pharos / TCRD GraphQL. Target development level (Tclin/Tchem/Tbio/Tdark),
        family, and drug/ligand counts for a gene symbol."""
        import json as _json, urllib.request
        gene = query.strip().upper()
        gql = """
        query ($sym: String!) {
          target(q: { sym: $sym }) {
            name sym tdl fam novelty
            ligandCounts { name value }
          }
        }
        """
        def _fetch():
            payload = _json.dumps({"query": gql, "variables": {"sym": gene}}).encode()
            req = urllib.request.Request(
                "https://pharos-api.ncats.io/graphql",
                data=payload,
                headers={"Content-Type": "application/json",
                         "User-Agent": "BioMate/1.0"}
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    data = _json.loads(resp.read().decode())
                    return (data.get('data') or {}).get('target')
            except Exception:
                return None
        target = self._cached_fetch("pharos_post:" + gene, _fetch)
        if not target:
            return {"source": "pharos", "query": query, "error": "no_response"}
        counts = {c.get('name'): c.get('value') for c in (target.get('ligandCounts') or [])}
        return {"source": "pharos", "query": query,
                "name": target.get('name'), "symbol": target.get('sym'),
                "tdl": target.get('tdl'), "family": target.get('fam'),
                "novelty": target.get('novelty'),
                "ligand_count": counts.get('ligand'),
                "drug_count": counts.get('drug')}

    def _query_pdbe(self, query: str, operation: str = 'lookup') -> Dict:
        """PDBe REST. Summary + ligand (binding) annotations for a 4-char PDB ID,
        or best-covering experimental structures (SIFTS) for a UniProt accession."""
        import re
        base = "https://www.ebi.ac.uk/pdbe/api"
        term = query.strip()

        # UniProt accession -> best experimental structures covering it.
        if re.match(r'^([OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2})$', term.upper()):
            acc = term.upper()
            data = self._http_get_json(f"{base}/mappings/best_structures/{acc}")
            hits = (data or {}).get(acc, [])
            results = [{"pdb_id": h.get('pdb_id'), "chain": h.get('chain_id'),
                        "method": h.get('experimental_method'),
                        "resolution": h.get('resolution'),
                        "coverage": h.get('coverage')} for h in hits[:10]]
            return {"source": "pdbe", "query": acc, "uniprot": acc,
                    "best_structures": results}

        # 4-char PDB ID -> summary + ligand (binding) annotations.
        if re.match(r'^[A-Za-z0-9]{4}$', term) and not term.isalpha():
            pdb_id = term.lower()
            summary = self._http_get_json(f"{base}/pdb/entry/summary/{pdb_id}")
            entry = (summary or {}).get(pdb_id, [{}])
            entry = entry[0] if entry else {}
            ligand_data = self._http_get_json(f"{base}/pdb/entry/ligand_monomers/{pdb_id}")
            ligs = (ligand_data or {}).get(pdb_id, [])
            ligands = []
            seen = set()
            for lg in ligs:
                cid = lg.get('chem_comp_id')
                if cid and cid not in seen:
                    seen.add(cid)
                    ligands.append({"chem_comp_id": cid,
                                    "name": lg.get('chem_comp_name'),
                                    "chain": lg.get('chain_id')})
            return {"source": "pdbe", "pdb_id": pdb_id.upper(),
                    "title": entry.get('title'),
                    "method": (entry.get('experimental_method') or [None])[0],
                    "release_date": entry.get('release_date'),
                    "ligands": ligands[:15]}
        return {"source": "pdbe", "query": query, "results": [],
                "note": "Provide a 4-char PDB ID or a UniProt accession"}

    def _query_interpro(self, query: str) -> Dict:
        import urllib.parse
        q = urllib.parse.quote(query)
        url = f"https://www.ebi.ac.uk/interpro/api/entry/?search={q}&format=json&page_size=5"
        data = self._http_get_json(url)
        results = []
        if data:
            for e in data.get('results', [])[:5]:
                meta = e.get('metadata', {})
                results.append({"accession": meta.get('accession'),
                                 "name": meta.get('name'),
                                 "type": meta.get('type')})
        return {"source": "interpro", "query": query, "results": results}

    def _detect_database_from_query(self, query: str) -> str:
        import re
        q_lower = query.lower()
        q_stripped = query.strip()
        if re.match(r'^rs\d+$', q_stripped, re.IGNORECASE) or 'variant' in q_lower:
            return 'dbsnp'
        if re.match(r'^[A-Z][0-9][A-Z0-9]{3}[0-9]$', q_stripped.upper()):
            return 'uniprot'
        if re.match(r'^[A-Za-z0-9]{4}$', q_stripped) and not q_stripped.isalpha():
            return 'pdb'
        if re.match(r'^GO:\d+$', q_stripped, re.IGNORECASE):
            return 'go'
        if q_lower.startswith('hp:') or 'disease' in q_lower or 'phenotype' in q_lower:
            return 'hpo'
        if 'compound' in q_lower or 'smiles' in q_lower or 'drug' in q_lower:
            return 'chembl'
        if 'pathway' in q_lower or 'kegg' in q_lower:
            return 'kegg'
        if 'domain' in q_lower or 'pfam' in q_lower or 'interpro' in q_lower:
            return 'interpro'
        if 'protein' in q_lower or 'enzyme' in q_lower or 'uniprot' in q_lower:
            return 'uniprot'
        if 'interaction' in q_lower or 'ppi' in q_lower:
            return 'string'
        return 'ncbi_gene'

    def query_database(self, database: str, query: str, operation: str = 'lookup') -> Dict:
        """
        Route a biological database query to the appropriate public REST API.
        Supports: auto, federated, ncbi_gene, uniprot, pdb, alphafold, kegg,
                  reactome, go, hpo, chebi, chembl, pubchem, bindingdb, pharos,
                  pdbe, interpro, string, ensembl,
                  gnomad, dbsnp, clinvar, pubmed,
                  europepmc, semantic_scholar, openalex.

        `operation` is the search mode the LLM selects from user intent — NOT
        inferred from the shape of `query`. 'similarity' runs a similarity search
        (chembl -> Tanimoto over SMILES; pdb -> sequence homologs over the whole
        PDB); 'text' a keyword search; 'lookup' (default) an ID/name lookup.

        Pass database='federated' (or 'auto') to fan-out to all relevant sources
        in parallel and receive a merged result set.
        """
        db = database.lower().strip()

        # Private DB path (userdb:<conn_id>) — routed to galaxy.ai.private_db.
        # This dispatcher has no per-request `trans` (the AIAssistant is a process
        # singleton), and private_db enforces per-user ownership + read-only
        # execution through `trans.user`'s Vault namespace. So private DB queries
        # MUST be routed at the trans-aware API layer (query_biological_database in
        # webapps/.../api/ai_assistant.py), which intercepts `userdb:` before it
        # reaches here. If a `userdb:` value reaches this dispatcher, it means it was
        # invoked without user context — refuse rather than run unauthenticated.
        if db.startswith('userdb:'):
            return {
                "success": False,
                "source": "userdb",
                "error": "Private DB queries require an authenticated request; "
                         "route via /api/databases/query (trans-aware) not the singleton dispatcher.",
            }

        # Federated path: parallel fan-out to all relevant sources
        if db in ('federated', 'auto'):
            try:
                from galaxy.ai.federated_query import federated_query
                result = federated_query(query)
                result['success'] = True
                return result
            except Exception as e:
                import logging as _log
                _log.getLogger(__name__).warning(
                    f"[query_database] federated({query}) failed: {e}, falling back to single-source"
                )
                db = self._detect_database_from_query(query)

        handlers = {
            'ncbi_gene': self._query_ncbi_gene,
            'uniprot': self._query_uniprot,
            'pdb': self._query_pdb,
            'alphafold': self._query_alphafold,
            'kegg': self._query_kegg,
            'reactome': self._query_reactome,
            'go': self._query_go,
            'hpo': self._query_hpo,
            'chebi': self._query_chebi,
            'chembl': self._query_chembl,
            'pubchem': self._query_pubchem,
            'bindingdb': self._query_bindingdb,
            'pharos': self._query_pharos,
            'pdbe': self._query_pdbe,
            'interpro': self._query_interpro,
            'string': self._query_string,
            'ensembl': self._query_ensembl,
            'gnomad': self._query_gnomad,
            'dbsnp': lambda q: self._query_ncbi_entrez(q, 'snp'),
            'clinvar': lambda q: self._query_ncbi_entrez(q, 'clinvar'),
            'pubmed': lambda q: self._query_ncbi_entrez(q, 'pubmed'),
        }
        # New literature sources — delegate to federated_query module
        if db in ('europepmc', 'semantic_scholar', 'openalex'):
            try:
                import importlib
                fq = importlib.import_module('galaxy.ai.federated_query')
                fetcher = fq._FETCHERS.get(db)
                if fetcher:
                    result = fetcher(query)
                    result['success'] = True
                    return result
            except Exception as e:
                return {"success": False, "source": db, "error": str(e)}

        handler = handlers.get(db)
        if not handler:
            return {"success": False, "error": f"Unknown database: {db}",
                    "supported": list(handlers.keys()) +
                                 ['federated', 'europepmc', 'semantic_scholar', 'openalex']}
        try:
            # Handlers that support an intent-driven search mode take `operation`.
            if db in ('chembl', 'pdb', 'pubchem', 'bindingdb', 'pharos', 'pdbe'):
                result = handler(query, operation)
            else:
                result = handler(query)
            result['success'] = True
            return result
        except Exception as e:
            import logging as _log
            _log.getLogger(__name__).warning(f"[query_database] {db}({query}) failed: {e}")
            return {"success": False, "source": db, "error": str(e)}

    # =========================================================================
    # Track 3B — Domain Knowledge Highlights
    # =========================================================================

    _DOMAIN_KNOWLEDGE_FILES: Dict[str, str] = {
        # Genomics / variant calling / epigenomics
        'genomics': 'expert_knowledge_genomics.json',
        'variant_calling': 'expert_knowledge_genomics.json',
        'epigenomics': 'expert_knowledge_genomics.json',
        'genetics': 'expert_knowledge_genomics.json',
        'transcriptomics': 'expert_knowledge_cellbio_immuno.json',  # scRNA topics here
        'metagenomics': 'expert_knowledge_microbio_sysbio.json',
        # Drug discovery / pharmacology / structural biology
        'drug_discovery': 'expert_knowledge_pharmacology.json',
        'pharmacology': 'expert_knowledge_pharmacology.json',
        'structural_biology': 'expert_knowledge_pharmacology.json',
        'biochemistry': 'expert_knowledge_pharmacology.json',
        'biophysics': 'expert_knowledge_pharmacology.json',
        # Bioimaging
        'bioimaging': 'expert_knowledge_bioimaging.json',
        'imaging': 'expert_knowledge_bioimaging.json',
        'cryo_em': 'expert_knowledge_bioimaging.json',
        'cryo_et': 'expert_knowledge_bioimaging.json',
        'pathology': 'expert_knowledge_bioimaging.json',
        # Proteomics / molecular biology / multi-omics
        'proteomics': 'expert_knowledge_molecular_biology.json',
        'molecular_biology': 'expert_knowledge_molecular_biology.json',
        'multi_omics': 'expert_knowledge_molecular_biology.json',
        'metabolomics': 'expert_knowledge_molecular_biology.json',
        # Single cell / cell biology / immunology
        'single_cell': 'expert_knowledge_cellbio_immuno.json',
        'cell_biology': 'expert_knowledge_cellbio_immuno.json',
        'immunology': 'expert_knowledge_cellbio_immuno.json',
        'cancer_biology': 'expert_knowledge_cellbio_immuno.json',
        # Microbiology / systems biology / synthetic biology
        'microbiology': 'expert_knowledge_microbio_sysbio.json',
        'systems_biology': 'expert_knowledge_microbio_sysbio.json',
        'synthetic_biology': 'expert_knowledge_microbio_sysbio.json',
        'bioengineering': 'expert_knowledge_microbio_sysbio.json',
    }

    # Per-domain reference descriptions used to build BGE centroids for semantic
    # domain inference. Each string blends a natural-language summary with
    # representative tool names, method terms, and common user phrasings so the
    # embedding captures the full semantic space of that domain.
    #
    # These are reference material only — the BGE model makes its own cosine-
    # similarity decision and is not bound by any term listed here. Ambiguous
    # queries will naturally score low on all domains and return no domain (→ '').
    _DOMAIN_DESCRIPTIONS: Dict[str, str] = {
        'cryo_em': (
            'Cryo-electron microscopy single particle analysis for high-resolution '
            'protein structure determination. Tools: CryoSPARC, RELION, MotionCor2, '
            'CTFFIND4, Topaz, crYOLO, DeepEMhancer, EMAN2. Methods: motion correction, '
            'CTF estimation, particle picking, 2D classification, 3D refinement, '
            'map sharpening, local resolution, model building. Keywords: cryo-EM, '
            'cryoEM, cryo electron microscopy, single particle, micrograph, FSC, '
            'gold-standard, nanodisc, membrane protein structure.'
        ),
        'cryo_et': (
            'Cryo-electron tomography and subtomogram averaging for in-situ structural '
            'biology. Tools: AreTomo2, IsoNet, Dynamo, IMOD, eTomo. Methods: tilt series '
            'acquisition, tomogram reconstruction, subtomogram averaging, missing wedge '
            'correction, FIB milling, lamella preparation. Keywords: cryo-ET, tomography, '
            'tilt series, subtomogram, lamella, FIB-SEM, in-cell cryo-ET, in situ.'
        ),
        'genomics': (
            'DNA variant calling, genome sequencing, and genotyping pipelines. '
            'Tools: GATK, HaplotypeCaller, BWA, Bowtie2, samtools, bcftools, FreeBayes, '
            'DeepVariant, snpEff, VEP. Methods: germline and somatic variant calling, '
            'SNP, indel, CNV detection, WGS, WES, genome assembly, haplotyping. '
            'Keywords: variant calling, whole genome sequencing, WGS, SNP, indel, '
            'germline, somatic, mutation, genotype, exome.'
        ),
        'transcriptomics': (
            'Bulk RNA sequencing, gene expression quantification, and differential '
            'expression analysis. Tools: STAR, HISAT2, salmon, kallisto, featureCounts, '
            'HTSeq, DESeq2, edgeR, limma. Methods: read alignment, transcript '
            'quantification, differential expression, splicing analysis, gene ontology. '
            'Keywords: RNA-seq, bulk RNA, differential expression, transcriptome, '
            'read counts, TPM, FPKM, DESeq2, edgeR.'
        ),
        'epigenomics': (
            'Chromatin accessibility, histone modification, and DNA methylation profiling. '
            'Tools: MACS2, HOMER, Bismark, Bowtie2, deepTools, ENCODE pipeline, '
            'chromHMM. Methods: ChIP-seq peak calling, ATAC-seq open chromatin, '
            'bisulfite sequencing, CUT&RUN, CUT&TAG, WGBS. Keywords: ChIP-seq, '
            'ATAC-seq, epigenomics, histone, methylation, peak calling, chromatin, '
            'accessibility, H3K27ac, H3K4me3.'
        ),
        'single_cell': (
            'Single-cell RNA sequencing, multimodal single-cell, and spatial transcriptomics. '
            'Platforms: 10x Chromium (droplet scRNA-seq), 10x Multiome (joint RNA+ATAC on same cells), '
            'BD Biosciences Rhapsody (microwell capture, AbSeq protein co-detection), '
            'Parse Biosciences Evercode (split-pool combinatorial barcoding, no microfluidics, '
            'SPLiT-seq, WT/WT_mini/WT_mega kits, scales to 1M+ cells, fixed tissue), '
            'CITE-seq (RNA + ADT antibody-derived tags, TotalSeq, surface protein co-profiling, '
            'DSB normalization, WNN multimodal integration), '
            'MERFISH / Vizgen MERSCOPE (image-based spatial, subcellular RNA molecule detection, '
            'seqFISH+, 10x Xenium In Situ, CODEX multiplex protein imaging, Cellpose segmentation, '
            'spatialDE spatially variable genes, spatial domain detection). '
            'QC: DoubletFinder, Scrublet, doublet detection, pANN score, BCmvn pK selection. '
            'Tools: Seurat, Scanpy, Cell Ranger, Cell Ranger ARC, Monocle, scVI, SCENIC, '
            'chromVAR TF motif activity, MACS2 peak calling, peak-to-gene linkage, LSI. '
            'Methods: clustering, UMAP, Leiden, trajectory inference, RNA velocity, WNN, '
            'joint RNA+ATAC, open chromatin, ATAC-seq, scATAC. '
            'Keywords: scRNA-seq, single cell, single-cell, 10x Genomics, Rhapsody, '
            'Parse, SPLiT-seq, CITE-seq, multiome, MERFISH, seqFISH, Xenium, CODEX, '
            'doublet removal, cell type annotation, spatial transcriptomics.'
        ),
        'proteomics': (
            'Mass spectrometry-based proteomics, protein identification, and '
            'quantification. Tools: MaxQuant, Perseus, Proteome Discoverer, MSFragger, '
            'Spectronaut, DIA-NN, FragPipe. Methods: LC-MS/MS, data-dependent '
            'acquisition DDA, data-independent acquisition DIA, label-free quantification '
            'LFQ, TMT labeling, FDR filtering, peptide identification. Keywords: '
            'proteomics, LC-MS, mass spectrometry, peptide, protein abundance, '
            'label-free, LFQ, DIA, DDA, FDR.'
        ),
        'metabolomics': (
            'Small molecule metabolite profiling and metabolic pathway analysis. '
            'Tools: XCMS, MetaboAnalyst, MZmine, OpenMS, CAMERA. Methods: untargeted '
            'and targeted metabolomics, peak detection, metabolite annotation, '
            'pathway enrichment, flux analysis. Keywords: metabolomics, metabolite, '
            'small molecule, XCMS, MetaboAnalyst, metabolic pathway, NMR, LC-MS '
            'metabolomics, mass spectrometry metabolomics.'
        ),
        'drug_discovery': (
            'Computational drug discovery, molecular docking, ADMET prediction, '
            'molecular dynamics simulation, and virtual cell mechanistic modeling. '
            'Tools: AutoDock Vina, DiffDock, GROMACS, AMBER, REINVENT4, OpenFE, '
            'Schrödinger, RDKit, AlphaFold, Tellurium, COPASI, GEARS, CPA, PhysiCell. '
            'Methods: virtual screening, SMILES-based design, lead optimization, '
            'free energy perturbation, MD simulation, pharmacokinetics, ODE signaling '
            'simulation, CiPA cardiac safety, FBA metabolic flux, DILI prediction, '
            'drug combination synergy, tumor growth inhibition TGI, virtual patient. '
            'Keywords: drug discovery, ADMET, docking, molecular dynamics, SMILES, '
            'lead optimization, drug design, binding affinity, pharmacophore, GROMACS, '
            'AMBER, cardiac safety hERG, CiPA, signaling pathway ODE, MAPK ERK, '
            'metabolic flux DILI, gene perturbation GEARS, drug synergy combination, '
            'TGI tumor, virtual patient cohort PTA, LINCS MoA.'
        ),
        'structural_biology': (
            'Computational protein structure prediction and analysis outside of cryo-EM. '
            'Tools: AlphaFold2, AlphaFold3, RoseTTAFold, ESMFold, ColabFold, MODELLER. '
            'Methods: homology modeling, ab initio folding, structure refinement, '
            'interface analysis, evolutionary covariation. Keywords: protein structure '
            'prediction, AlphaFold, homology model, folding, structure refinement, '
            'multimer, protein complex structure prediction.'
        ),
        'metagenomics': (
            'Microbial community profiling from environmental or clinical samples. '
            'Tools: MetaPhlAn, Kraken2, HUMAnN, QIIME2, mothur, DADA2, MEGAHIT. '
            'Methods: 16S rRNA amplicon sequencing, shotgun metagenomics, taxonomic '
            'classification, OTU clustering, diversity analysis, functional profiling. '
            'Keywords: metagenomics, microbiome, 16S, amplicon, OTU, ASV, microbial '
            'diversity, MetaPhlAn, Kraken, shotgun.'
        ),
        'microbiology': (
            'Microbial genomics, pathogen analysis, and antimicrobial resistance. '
            'Tools: Prokka, Roary, ABRicate, CARD, Snippy, Gubbins. Methods: '
            'bacterial genome assembly, annotation, pan-genome analysis, AMR detection, '
            'phylogenetics, outbreak investigation. Keywords: microbiology, bacteria, '
            'pathogen, antimicrobial resistance, AMR, prokaryote, genome annotation, '
            'pan-genome, bacterial.'
        ),
        'systems_biology': (
            'Network analysis, pathway enrichment, and metabolic modeling. '
            'Tools: Cytoscape, GSEA, COBRA, EFMEvolver, STRING, BioGRID. Methods: '
            'gene set enrichment, flux balance analysis, protein interaction networks, '
            'regulatory network inference. Keywords: systems biology, network, pathway '
            'enrichment, GSEA, gene ontology, flux balance, metabolic network.'
        ),
        'synthetic_biology': (
            'Genetic circuit design, metabolic pathway engineering, and biosynthesis. '
            'Tools: SBOL, iBioSim, Geneious, Benchling, CRISPR design tools. Methods: '
            'gene circuit optimization, promoter design, codon optimization, CRISPR '
            'editing, metabolic flux engineering. Keywords: synthetic biology, gene '
            'circuit, metabolic engineering, CRISPR, biosynthesis, pathway design, '
            'codon optimization.'
        ),
        'immunology': (
            'Immune cell profiling, repertoire analysis, and immune response '
            'characterization. Tools: ImmGen, CellRanger VDJ, MiXCR, TRUST4, '
            'VDJTOOLS, Immcantation. Methods: flow cytometry analysis, TCR/BCR '
            'repertoire sequencing, immune cell type classification, clonotype '
            'tracking. Keywords: immunology, T cell, B cell, antibody, immune, '
            'TCR, BCR, repertoire, flow cytometry, cytokine, checkpoint.'
        ),
        'cell_biology': (
            'Cell imaging, morphology analysis, and subcellular structure '
            'characterization. Tools: ImageJ, CellProfiler, ilastik, StarDist, '
            'Cellpose, napari. Methods: fluorescence microscopy, confocal imaging, '
            'segmentation, tracking, organelle quantification. Keywords: cell biology, '
            'confocal, fluorescence microscopy, live imaging, segmentation, imaging '
            'analysis, organelle, CellProfiler, Cellpose.'
        ),
        'cancer_biology': (
            'Cancer genomics, tumor evolution, and oncology data analysis. '
            'Tools: TCGA pipelines, MuTect2, TITAN, ABSOLUTE, OncoKB. Methods: '
            'somatic mutation calling, copy number variation, tumor purity estimation, '
            'driver gene identification, survival analysis. Keywords: cancer, tumor, '
            'oncology, somatic mutation, CNV, driver gene, TCGA, tumor mutational '
            'burden, TMB, immunotherapy response.'
        ),
        'bioengineering': (
            'Biomaterial design, tissue engineering, and bioprocess optimization. '
            'Tools: FEniCS, OpenFOAM, BioNet. Methods: scaffold design, bioreactor '
            'modeling, fermentation optimization, protein expression optimization. '
            'Keywords: bioengineering, tissue engineering, biomaterial, scaffold, '
            'bioreactor, fermentation, bioprocess.'
        ),
        'virtual_cell': (
            'Virtual cell modeling, mechanistic ODE simulation, gene perturbation '
            'prediction, drug combination synergy, and tumor growth inhibition. '
            'Tools: Tellurium, COPASI, AMICI, GEARS, CPA, Geneformer, TranscriptFormer, '
            'PhysiCell, SBMLtoODEjax, COBRApy, LINCS L1000, scFoundation, rBio. '
            'Methods: ODE signaling cascade simulation (MAPK/ERK, PI3K/AKT, NF-kB, '
            'JAK-STAT, EGFR, Wnt, apoptosis, TGF-beta), SBML model simulation, '
            'CiPA cardiac safety (hERG, Nav1.5, Cav1.2, action potential, APD90, qNET, '
            'TdP risk), flux balance analysis FBA (glycolysis, TCA cycle, beta-oxidation, '
            'mitochondrial toxicity, DILI, steatosis, cholestasis), gene regulatory '
            'network perturbation (CRISPR KO/KD/OE CRISPRa CRISPRi), drug combination '
            'synergy (Bliss, ZIP, HSA, synergistic antagonistic additive), '
            'transcriptomic MoA via LINCS connectivity map, Simeoni TGI tumor growth '
            'inhibition, Norton-Simon, Monte Carlo virtual patient cohort, population '
            'pharmacokinetics PopPK, percent target attainment PTA, special populations. '
            'Keywords: virtual cell, mechanistic model, ODE simulation, signaling pathway, '
            'gene perturbation, single cell perturbation, GEARS, CPA drug combination, '
            'cardiac safety CiPA, metabolic flux FBA DILI, LINCS MoA connectivity map, '
            'tumor TGI Simeoni, virtual patient cohort PTA dose optimization, '
            'perturbation prediction, drug synergy, ion channel model.'
        ),
    }

    # Module-level BGE centroid cache — populated once per worker on first call
    _domain_centroids: Dict[str, List[float]] = {}

    def _get_domain_centroids(self) -> Dict[str, List[float]]:
        """Build and cache per-domain BGE centroids (once per process)."""
        if not self.__class__._domain_centroids:
            try:
                from .cryo_em_knowledge.rag_index import _get_bge_model
                model = _get_bge_model()
                domains = list(self._DOMAIN_DESCRIPTIONS.keys())
                vecs = model.encode(
                    [self._DOMAIN_DESCRIPTIONS[d] for d in domains],
                    normalize_embeddings=True,
                )
                self.__class__._domain_centroids = {
                    d: v.tolist() for d, v in zip(domains, vecs)
                }
            except Exception as e:
                logging.getLogger(__name__).warning(
                    "[DomainInfer] centroid build failed: %s", e
                )
        return self.__class__._domain_centroids

    def _infer_domain_from_intent(self, user_intent: str) -> str:
        """
        Infer knowledge domain from user intent using BGE cosine similarity
        against per-domain description centroids.

        Returns the best-matching key from _DOMAIN_KNOWLEDGE_FILES, or ''.
        Requires score ≥ 0.40 with margin ≥ 0.03 over second-best.
        """
        import math as _math
        centroids = self._get_domain_centroids()
        if not centroids:
            return ''
        try:
            from .cryo_em_knowledge.rag_index import _get_bge_model
            model = _get_bge_model()
            q_vec = model.encode([user_intent], normalize_embeddings=True)[0].tolist()

            def _cos(a: List[float], b: List[float]) -> float:
                dot = sum(x * y for x, y in zip(a, b))
                na = _math.sqrt(sum(x * x for x in a)) or 1.0
                nb = _math.sqrt(sum(x * x for x in b)) or 1.0
                return dot / (na * nb)

            scored = sorted(
                [(d, _cos(q_vec, c)) for d, c in centroids.items()],
                key=lambda x: -x[1]
            )
            best_domain, best_score = scored[0]
            second_score = scored[1][1] if len(scored) > 1 else 0.0
            if best_score >= 0.40 and (best_score - second_score) >= 0.03:
                return best_domain
        except Exception as e:
            logging.getLogger(__name__).warning(
                "[DomainInfer] BGE inference failed: %s", e
            )
        return ''

    def _build_knowledge_highlights(
        self,
        domain: str,
        workflow_name: str,
        workflow_tools: List[str],
    ) -> Dict[str, Any]:
        """
        Build best_practices, qc_thresholds, and literature_guidance from DB sources.

        Priority:
        1. cryo_em_protocols DB (cryo-EM / cryo-ET domain only) — protocol-level rules, QC gates, papers
        2. tool_knowledge DB (all domains) — per-tool use cases and primary citations
        3. Expert JSON file (all domains) — keyword-scored topic fallback
        """
        import json as _json
        import logging as _log
        log = _log.getLogger(__name__)

        best_practices: List[str] = []
        qc_thresholds: List[Dict] = []
        literature_guidance: List[Dict] = []

        # ── Path 1: cryo_em_protocols DB (cryo-EM / cryo-ET only) ──────────────
        if domain in ('cryo_em', 'cryo_et', 'bioimaging'):
            try:
                from .cryo_em_knowledge.retriever import get_retriever
                retriever = get_retriever()
                # Detect sample class from workflow name + tool list
                probe = workflow_name + ' ' + ' '.join(workflow_tools or [])
                sample_class = retriever.detect_sample_class(probe)
                if sample_class:
                    protocol = retriever.get_protocol(sample_class)
                    if protocol:
                        # retriever._row_to_dict pre-parses JSON fields → already Python objects
                        def _as_list(v):
                            if isinstance(v, list):
                                return v
                            if isinstance(v, str):
                                try:
                                    return _json.loads(v)
                                except Exception:
                                    return []
                            return []
                        # key_principles → best_practices
                        for principle in _as_list(protocol.get('key_principles'))[:4]:
                            if isinstance(principle, str) and principle.strip():
                                best_practices.append(principle.strip())
                        # qc_gates → qc_thresholds
                        for gate in _as_list(protocol.get('qc_gates'))[:5]:
                            if isinstance(gate, dict) and gate.get('name'):
                                qc_thresholds.append({
                                    'metric': gate['name'],
                                    'threshold': gate.get('criterion', ''),
                                    'context': gate.get('action_if_fail', ''),
                                    'source': sample_class,
                                })
                        # reference_papers → literature_guidance
                        for paper in _as_list(protocol.get('reference_papers'))[:3]:
                            if isinstance(paper, dict):
                                literature_guidance.append({
                                    'url': paper.get('doi', ''),
                                    'context': paper.get('title', ''),
                                })
                        log.info(
                            "[KnowledgeHighlights] cryo-EM DB path: class=%s bp=%d qc=%d lit=%d",
                            sample_class, len(best_practices), len(qc_thresholds), len(literature_guidance),
                        )
            except Exception as e:
                log.warning("[KnowledgeHighlights] cryo-EM DB lookup failed: %s", e)

        # ── Path 2: tool DB (works for every domain) ─────────────────────────────
        # Pulls from two tables: `tool_knowledge` (curated) and `tools` (rich scientific_context)
        tools_to_query = [t for t in (workflow_tools or []) if t and len(t) > 1]
        if tools_to_query:
            try:
                import sqlite3 as _sqlite3
                db_path = Path(__file__).resolve().parents[3] / "database" / "galaxy_ai_tools.db"
                if db_path.exists():
                    conn = _sqlite3.connect(str(db_path))
                    conn.row_factory = _sqlite3.Row
                    placeholders = ','.join('?' * len(tools_to_query))

                    # 2a. tool_knowledge — curated use_cases and primary citation
                    tk_rows = conn.execute(
                        f"SELECT tool_name, use_cases, primary_citation "
                        f"FROM tool_knowledge WHERE tool_name IN ({placeholders}) LIMIT 8",
                        tools_to_query,
                    ).fetchall()
                    for row in tk_rows:
                        uc_raw = row['use_cases']
                        if uc_raw:
                            uc_list = _json.loads(uc_raw) if isinstance(uc_raw, str) else uc_raw
                            for uc in (uc_list or [])[:2]:
                                if (isinstance(uc, str) and len(uc) > 20
                                        and not uc.lower().startswith('note:')
                                        and uc not in best_practices):
                                    best_practices.append(uc)
                                    break
                        cit_raw = row['primary_citation']
                        if cit_raw and len(literature_guidance) < 3:
                            cit = _json.loads(cit_raw) if isinstance(cit_raw, str) else cit_raw
                            doi = cit.get('doi', '') or cit.get('url', '')
                            title = cit.get('title', row['tool_name'])
                            if doi and not any(g.get('url') == doi for g in literature_guidance):
                                literature_guidance.append({'url': doi, 'context': title})

                    # 2b. tools.scientific_context — best_for and structured_citations
                    # Deduplicate by name; prefer rows with scientific_context populated
                    t_rows = conn.execute(
                        f"SELECT name, scientific_context, structured_citations "
                        f"FROM tools WHERE name IN ({placeholders}) "
                        f"AND scientific_context IS NOT NULL AND scientific_context != '' "
                        f"GROUP BY name LIMIT 8",
                        tools_to_query,
                    ).fetchall()
                    for row in t_rows:
                        sc_raw = row['scientific_context']
                        if sc_raw:
                            try:
                                sc = _json.loads(sc_raw) if isinstance(sc_raw, str) else sc_raw
                                best_for = (sc.get('tool_selection') or {}).get('best_for') or []
                                for bf in best_for[:2]:
                                    if (isinstance(bf, str) and len(bf) > 20
                                            and bf not in best_practices):
                                        best_practices.append(bf)
                                        break
                            except Exception:
                                pass
                        cits_raw = row['structured_citations']
                        if cits_raw and len(literature_guidance) < 3:
                            try:
                                cits = _json.loads(cits_raw) if isinstance(cits_raw, str) else cits_raw
                                for cit in (cits if isinstance(cits, list) else [])[:2]:
                                    doi = cit.get('doi', '') or cit.get('url', '')
                                    title = cit.get('title', row['name'])
                                    if doi and not any(g.get('url') == doi for g in literature_guidance):
                                        literature_guidance.append({'url': doi, 'context': title})
                                        break
                            except Exception:
                                pass

                    # 2c. cryo_em_tools.use_when — tool-specific guidance for cryo-EM workflows
                    if domain in ('cryo_em', 'cryo_et', 'bioimaging'):
                        ct_rows = conn.execute(
                            f"SELECT tool_name, use_when, key_parameters, biomate_status "
                            f"FROM cryo_em_tools WHERE tool_name IN ({placeholders}) LIMIT 6",
                            tools_to_query,
                        ).fetchall()
                        for row in ct_rows:
                            uw_raw = row['use_when']
                            if uw_raw:
                                uw_list = _json.loads(uw_raw) if isinstance(uw_raw, str) else uw_raw
                                for uw in (uw_list or [])[:1]:
                                    entry = f"{row['tool_name']}: use when {uw}"
                                    if entry not in best_practices:
                                        best_practices.append(entry)

                    conn.close()
            except Exception as e:
                log.warning("[KnowledgeHighlights] tool DB lookup failed: %s", e)

        # ── Path 3: expert JSON fallback (fills gaps when DB results are sparse) ─
        fname = self._DOMAIN_KNOWLEDGE_FILES.get(domain, '')
        if fname and len(best_practices) < 3:
            knowledge_dir = Path(__file__).parent.parent.parent.parent / 'scripts' / 'domain_knowledge'
            knowledge_path = knowledge_dir / fname
            if knowledge_path.exists():
                try:
                    with open(knowledge_path) as f:
                        all_topics = _json.load(f)
                    _normalize = lambda s: s.lower().replace('-', ' ').replace('_', ' ').replace('/', ' ')
                    all_keywords = set(_normalize(workflow_name).split())
                    for t in (workflow_tools or []):
                        all_keywords.update(_normalize(t).split())
                    scored = []
                    for topic_key, topic_data in all_topics.items():
                        topic_words = set(topic_key.lower().replace('_', ' ').split())
                        desc_words = set((topic_data.get('description', '') or '').lower().split())
                        score = len(topic_words & all_keywords) * 3 + len(desc_words & all_keywords)
                        if score > 0:
                            scored.append((score, topic_key, topic_data))
                    scored.sort(key=lambda x: -x[0])
                    import re as _re
                    for _score, _topic_key, topic_data in scored[:3]:
                        bpn = topic_data.get('best_practice_notes', '')
                        if isinstance(bpn, str) and bpn.strip():
                            items = _re.split(r'\n\s*\d+\.\s*|\.\s+(?=[A-Z])', bpn.strip())
                            for item in items[:3]:
                                item = item.strip()
                                if len(item) > 20 and item not in best_practices:
                                    best_practices.append(item)
                        elif isinstance(bpn, list):
                            for item in bpn[:3]:
                                if isinstance(item, str) and item.strip() and item not in best_practices:
                                    best_practices.append(item.strip())
                        kp = topic_data.get('key_parameters', {})
                        if isinstance(kp, dict):
                            for param_name, param_data in list(kp.items())[:5]:
                                for sit_name, sit_data in list((param_data.get('situations') or {}).items())[:3]:
                                    val = sit_data.get('value_or_range', '')
                                    if val and len(qc_thresholds) < 5:
                                        qc_thresholds.append({
                                            'metric': param_name,
                                            'threshold': str(val),
                                            'context': sit_data.get('when', ''),
                                            'source': sit_data.get('source', ''),
                                        })
                        for ref in (topic_data.get('key_references') or [])[:3]:
                            if len(literature_guidance) >= 3:
                                break
                            if isinstance(ref, str) and ref.startswith('http'):
                                literature_guidance.append({'url': ref, 'context': _topic_key})
                            elif isinstance(ref, dict):
                                literature_guidance.append({
                                    'url': ref.get('url', ref.get('doi', '')),
                                    'context': ref.get('title', _topic_key),
                                })
                except Exception as e:
                    log.warning("[KnowledgeHighlights] JSON fallback failed: %s", e)

        log.info(
            "[KnowledgeHighlights] domain=%s workflow=%s: bp=%d qc=%d lit=%d",
            domain, workflow_name, len(best_practices), len(qc_thresholds), len(literature_guidance),
        )
        return {
            'best_practices': best_practices[:3],
            'qc_thresholds': qc_thresholds[:5],
            'literature_guidance': literature_guidance[:3],
        }

    # =========================================================================
    # Track 3D-i — Consistent APA Citations
    # =========================================================================

    def _build_workflow_citations(
        self,
        workflow_tools: List[str],
        domain: str,
        tags: List[str],
    ) -> List[Dict[str, Any]]:
        """
        Build a list of APA-formatted citations for a workflow.
        Sources: (1) tool_knowledge DB, (2) domain landmark papers.
        """
        _DOMAIN_LANDMARK = {
            'genomics': {
                'index': 1, 'authors': ['Ewels PA', 'Peltzer A', 'Fillinger S', 'et al.'],
                'year': 2020, 'title': 'The nf-core framework for community-curated bioinformatics pipelines',
                'journal': 'Nature Biotechnology', 'doi': '10.1038/s41587-020-0439-x', 'pmid': '32055031',
            },
            'transcriptomics': {
                'index': 1, 'authors': ['Love MI', 'Huber W', 'Anders S'],
                'year': 2014, 'title': 'Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2',
                'journal': 'Genome Biology', 'doi': '10.1186/s13059-014-0550-8', 'pmid': '25516281',
            },
            'variant_calling': {
                'index': 1, 'authors': ['McKenna A', 'Hanna M', 'Banks E', 'et al.'],
                'year': 2010, 'title': 'The Genome Analysis Toolkit: A MapReduce framework for analyzing next-generation DNA sequencing data',
                'journal': 'Genome Research', 'doi': '10.1101/gr.107524.110', 'pmid': '20644199',
            },
            'cryo_em': {
                'index': 1, 'authors': ['Punjani A', 'Rubinstein JL', 'Fleet DJ', 'Brubaker MA'],
                'year': 2017, 'title': 'cryoSPARC: algorithms for rapid unsupervised cryo-EM structure determination',
                'journal': 'Nature Methods', 'doi': '10.1038/nmeth.4169', 'pmid': '28165473',
            },
            'drug_discovery': {
                'index': 1, 'authors': ['Jumper J', 'Evans R', 'Pritzel A', 'et al.'],
                'year': 2021, 'title': 'Highly accurate protein structure prediction with AlphaFold',
                'journal': 'Nature', 'doi': '10.1038/s41586-021-03819-2', 'pmid': '34265844',
            },
            'pharmacology': {
                'index': 1, 'authors': ['Jumper J', 'Evans R', 'Pritzel A', 'et al.'],
                'year': 2021, 'title': 'Highly accurate protein structure prediction with AlphaFold',
                'journal': 'Nature', 'doi': '10.1038/s41586-021-03819-2', 'pmid': '34265844',
            },
            'proteomics': {
                'index': 1, 'authors': ['Röst HL', 'Sachsenberg T', 'Aiche S', 'et al.'],
                'year': 2016, 'title': 'OpenMS: a flexible open-source software platform for mass spectrometry data analysis',
                'journal': 'Nature Methods', 'doi': '10.1038/nmeth.3959', 'pmid': '27575611',
            },
            'multi_omics': {
                'index': 1, 'authors': ['Röst HL', 'Sachsenberg T', 'Aiche S', 'et al.'],
                'year': 2016, 'title': 'OpenMS: a flexible open-source software platform for mass spectrometry data analysis',
                'journal': 'Nature Methods', 'doi': '10.1038/nmeth.3959', 'pmid': '27575611',
            },
            'single_cell': {
                'index': 1, 'authors': ['Hao Y', 'Stuart T', 'Kowalski MH', 'et al.'],
                'year': 2024, 'title': 'Dictionary learning for integrative, multimodal and scalable single-cell analysis',
                'journal': 'Nature Biotechnology', 'doi': '10.1038/s41587-023-01767-y', 'pmid': '37316556',
            },
            'structural_biology': {
                'index': 1, 'authors': ['Berman HM', 'Westbrook J', 'Feng Z', 'et al.'],
                'year': 2000, 'title': 'The Protein Data Bank',
                'journal': 'Nucleic Acids Research', 'doi': '10.1093/nar/28.1.235', 'pmid': '10592235',
            },
            'bioimaging': {
                'index': 1, 'authors': ['Punjani A', 'Rubinstein JL', 'Fleet DJ', 'Brubaker MA'],
                'year': 2017, 'title': 'cryoSPARC: algorithms for rapid unsupervised cryo-EM structure determination',
                'journal': 'Nature Methods', 'doi': '10.1038/nmeth.4169', 'pmid': '28165473',
            },
            'virtual_cell': {
                'index': 1, 'authors': ['Roohani Y', 'Huang K', 'Leskovec J'],
                'year': 2024, 'title': 'Predicting transcriptional outcomes of novel multigene perturbations with GEARS',
                'journal': 'Nature Biotechnology', 'doi': '10.1038/s41587-023-01905-6', 'pmid': '37749249',
            },
        }

        citations = []
        seen_dois: set = set()

        # Source 1: tool_knowledge DB citations via ToolKnowledgeProvider
        try:
            from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider
            provider = ToolKnowledgeProvider()
            for tool_name in (workflow_tools or [])[:10]:
                try:
                    cit = provider.get_citation(tool_name)
                    if cit and hasattr(cit, 'format_apa'):
                        apa = cit.format_apa()
                        doi = getattr(cit, 'doi', None) or ''
                        if doi in seen_dois:
                            continue
                        if doi:
                            seen_dois.add(doi)
                        raw_authors = getattr(cit, 'authors', [])
                        if isinstance(raw_authors, str):
                            raw_authors = [a.strip() for a in raw_authors.split(',') if a.strip()]
                        citations.append({
                            'index': len(citations) + 1,
                            'tool_name': tool_name,
                            'tool_id': tool_name,
                            'authors': raw_authors,
                            'year': getattr(cit, 'year', None),
                            'title': getattr(cit, 'title', ''),
                            'journal': getattr(cit, 'journal', ''),
                            'doi': doi,
                            'pmid': getattr(cit, 'pmid', None),
                            'formatted_apa': apa,
                        })
                except Exception:
                    continue
        except Exception:
            pass

        # Source 2: domain landmark paper
        landmark = _DOMAIN_LANDMARK.get(domain or '')
        if landmark:
            doi = landmark.get('doi', '')
            if doi not in seen_dois:
                seen_dois.add(doi)
                authors_list = landmark['authors']
                last_a = authors_list[0].split()[0] if authors_list else 'Unknown'
                apa = (f"{', '.join(authors_list)} ({landmark['year']}). "
                       f"{landmark['title']}. {landmark['journal']}. "
                       f"DOI: {doi}")
                citations.append({
                    'index': len(citations) + 1,
                    'tool_name': 'domain_landmark',
                    'tool_id': f"landmark_{domain}",
                    'authors': authors_list,
                    'year': landmark['year'],
                    'title': landmark['title'],
                    'journal': landmark['journal'],
                    'doi': doi,
                    'pmid': landmark.get('pmid'),
                    'formatted_apa': apa,
                })

        return citations
