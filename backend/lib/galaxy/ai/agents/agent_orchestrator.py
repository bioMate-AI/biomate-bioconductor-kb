"""
Agent Orchestrator

Coordinates the multi-agent workflow generation system:
1. EnhancedDomainRouter - Routes to domains (Hybrid: Keywords + LLM)
2. DomainSpecialistPool - Parallel domain specialists
3. WorkflowAssembler - Synthesizes and validates

Pipeline:
User Request → EnhancedDomainRouter → DomainSpecialists (parallel) → WorkflowAssembler → Result

Features:
- LLM-enhanced routing for ambiguous queries
- User pattern personalization
- Full audit trail
- Learning from corrections and outcomes
"""

import logging
import json
from dataclasses import dataclass, field, asdict
from typing import Dict, Optional, Any, List
import time

from .domain_router import DomainRouter, RoutingDecision
from .enhanced_domain_router import EnhancedDomainRouter, EnhancedRoutingDecision
from .domain_specialist import DomainSpecialistPool, DomainRecommendation
from .workflow_assembler import WorkflowAssembler, AssembledWorkflow

log = logging.getLogger(__name__)


@dataclass
class OrchestrationResult:
    """Result of multi-agent orchestration."""
    workflow: AssembledWorkflow
    routing: Any  # RoutingDecision or EnhancedRoutingDecision
    domain_recommendations: Dict[str, DomainRecommendation]
    timing: Dict[str, float] = field(default_factory=dict)
    success: bool = True
    error: Optional[str] = None
    audit_id: Optional[int] = None  # Audit record ID for corrections
    request_id: Optional[str] = None  # Request ID for tracking


class AgentOrchestrator:
    """
    Orchestrates the multi-agent workflow generation pipeline.

    Provides a unified interface for:
    - Routing queries to appropriate domains (with LLM enhancement)
    - Running domain specialists in parallel
    - Assembling validated workflows
    - Auditing all generation attempts
    - Learning from corrections and outcomes
    """

    def __init__(
        self,
        tool_search,
        llm_client,
        citation_db=None,
        user_patterns_adapter=None,
        audit_service=None,
        learning_service=None,
        use_enhanced_routing: bool = True,
        max_parallel_specialists: int = 3
    ):
        """
        Initialize orchestrator with all required components.

        Args:
            tool_search: UnifiedToolSearch instance
            llm_client: LLM client for specialists and assembler
            citation_db: Optional citation database
            user_patterns_adapter: Optional UserPatternsAdapter for personalization
            audit_service: Optional WorkflowAuditService for auditing
            learning_service: Optional WorkflowLearningService for learning
            use_enhanced_routing: Use LLM-enhanced routing (default True)
            max_parallel_specialists: Max parallel specialist calls
        """
        self.llm_client = llm_client
        self.audit = audit_service
        self.learning = learning_service
        self.patterns = user_patterns_adapter

        # Initialize router based on configuration
        if use_enhanced_routing:
            self.domain_router = EnhancedDomainRouter(
                llm_client=llm_client,
                user_patterns_adapter=user_patterns_adapter,
                audit_service=audit_service
            )
            log.info("Using EnhancedDomainRouter with LLM support")
        else:
            self.domain_router = DomainRouter(user_patterns_adapter)
            log.info("Using basic DomainRouter (keyword-only)")

        self.specialist_pool = DomainSpecialistPool(
            tool_search=tool_search,
            llm_client=llm_client,
            max_workers=max_parallel_specialists
        )
        self.workflow_assembler = WorkflowAssembler(
            llm_client=llm_client,
            citation_db=citation_db
        )

        log.info(f"AgentOrchestrator initialized with 3 agents, "
                f"audit={'enabled' if audit_service else 'disabled'}, "
                f"learning={'enabled' if learning_service else 'disabled'}")

    def generate_workflow(
        self,
        query: str,
        user_id: Optional[str] = None,
        user_context: Optional[Dict] = None,
        session_id: Optional[str] = None,
        parallel: bool = True,
        available_datasets: Optional[List[Dict]] = None,
    ) -> OrchestrationResult:
        """
        Generate workflow using multi-agent pipeline.

        Args:
            query: User's workflow request
            user_id: Optional user ID for personalization
            user_context: Optional pre-loaded user context
            session_id: Optional session ID for audit
            parallel: Run specialists in parallel (default True)

        Returns:
            OrchestrationResult with workflow and metadata
        """
        timing = {}
        start_time = time.time()
        request_id = None
        audit_id = None

        # ===== Start Audit =====
        if self.audit and user_id:
            try:
                request_id = self.audit.start_audit(
                    user_id=user_id,
                    query=query,
                    session_id=session_id,
                    user_context=user_context
                )
                log.debug(f"Started audit with request_id={request_id}")
            except Exception as e:
                log.warning(f"Failed to start audit: {e}")

        try:
            # ===== Phase 1: Domain Routing (Hybrid: Keywords + LLM) =====
            route_start = time.time()
            routing = self.domain_router.route(
                query=query,
                user_id=user_id,
                user_context=user_context
            )
            routing_latency_ms = int((time.time() - route_start) * 1000)
            timing['routing'] = time.time() - route_start

            # Get routing method (enhanced router provides this)
            routing_method = getattr(routing, 'routing_method', 'keyword')

            log.info(f"Routing completed in {timing['routing']:.3f}s via {routing_method}: "
                    f"primary={routing.primary_domain}, "
                    f"secondary={routing.secondary_domains}")

            # Record routing in audit
            if self.audit and request_id:
                try:
                    self.audit.record_routing(
                        request_id=request_id,
                        routing_decision=routing,
                        method=routing_method,
                        latency_ms=routing_latency_ms
                    )
                except Exception as e:
                    log.warning(f"Failed to record routing: {e}")

            # Determine which domains to consult
            domains_to_consult = [routing.primary_domain]
            if routing.secondary_domains and routing.complexity != "simple":
                domains_to_consult.extend(routing.secondary_domains[:2])

            # ===== Phase 2: Domain Specialists (Parallel LLM) =====
            specialist_start = time.time()
            domain_recommendations = self.specialist_pool.consult_specialists(
                query=query,
                domains=domains_to_consult,
                parallel=parallel,
                available_datasets=available_datasets,
            )
            specialist_latency_ms = int((time.time() - specialist_start) * 1000)
            timing['specialists'] = time.time() - specialist_start

            log.info(f"Specialists completed in {timing['specialists']:.3f}s: "
                    f"domains={list(domain_recommendations.keys())}")

            # Record specialists in audit
            if self.audit and request_id:
                try:
                    self.audit.record_specialists(
                        request_id=request_id,
                        domains_consulted=domains_to_consult,
                        recommendations=domain_recommendations,
                        latency_ms=specialist_latency_ms
                    )
                except Exception as e:
                    log.warning(f"Failed to record specialists: {e}")

            # ===== Phase 3: Workflow Assembly (1 LLM) =====
            assembly_start = time.time()
            workflow = self.workflow_assembler.assemble(
                query=query,
                domain_recommendations=domain_recommendations,
                user_context=user_context
            )
            assembly_latency_ms = int((time.time() - assembly_start) * 1000)
            timing['assembly'] = time.time() - assembly_start

            log.info(f"Assembly completed in {timing['assembly']:.3f}s: "
                    f"steps={len(workflow.workflow_steps)}, "
                    f"confidence={workflow.confidence:.2f}")

            timing['total'] = time.time() - start_time
            total_latency_ms = int(timing['total'] * 1000)
            log.info(f"Total orchestration time: {timing['total']:.3f}s")

            # ===== Complete Audit (Success) =====
            if self.audit and request_id:
                try:
                    audit_id = self.audit.complete_audit(
                        request_id=request_id,
                        success=True,
                        workflow_id=workflow.workflow_id if hasattr(workflow, 'workflow_id') else None,
                        workflow_steps_count=len(workflow.workflow_steps),
                        confidence=workflow.confidence,
                        total_latency_ms=total_latency_ms,
                        assembly_result=workflow
                    )
                except Exception as e:
                    log.warning(f"Failed to complete audit: {e}")

            return OrchestrationResult(
                workflow=workflow,
                routing=routing,
                domain_recommendations=domain_recommendations,
                timing=timing,
                success=True,
                audit_id=audit_id,
                request_id=request_id
            )

        except Exception as e:
            log.error(f"Orchestration failed: {e}", exc_info=True)
            timing['total'] = time.time() - start_time
            total_latency_ms = int(timing['total'] * 1000)

            # ===== Complete Audit (Failure) =====
            if self.audit and request_id:
                try:
                    audit_id = self.audit.complete_audit(
                        request_id=request_id,
                        success=False,
                        error_type=type(e).__name__,
                        error_message=str(e),
                        total_latency_ms=total_latency_ms
                    )
                except Exception as audit_err:
                    log.warning(f"Failed to complete audit on error: {audit_err}")

            # Return empty result with error
            return OrchestrationResult(
                workflow=AssembledWorkflow(
                    workflow_steps=[],
                    recommended_tools=[],
                    validation=None,
                    citations=[],
                    domain_sources=[],
                    confidence=0.0
                ),
                routing=RoutingDecision(primary_domain="unknown"),
                domain_recommendations={},
                timing=timing,
                success=False,
                error=str(e),
                audit_id=audit_id,
                request_id=request_id
            )

    def get_quick_recommendations(
        self,
        query: str,
        user_context: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """
        Get quick tool recommendations without full workflow generation.

        Useful for simpler queries or when full workflow isn't needed.

        Args:
            query: User's query
            user_context: Optional user context

        Returns:
            Dict with routing and top tool recommendations
        """
        # Just do routing + single specialist
        routing = self.domain_router.route(query, user_context=user_context)

        recommendations = self.specialist_pool.consult_specialists(
            query=query,
            domains=[routing.primary_domain],
            parallel=False
        )

        primary_rec = recommendations.get(routing.primary_domain)

        return {
            'domain': routing.primary_domain,
            'confidence': routing.confidence,
            'tools': [
                {
                    'tool_id': t.tool_id,
                    'tool_name': t.tool_name,
                    'rationale': t.rationale
                }
                for t in (primary_rec.recommended_tools if primary_rec else [])
            ][:5],
            'keywords': routing.matched_keywords
        }

    def get_supported_domains(self) -> List[str]:
        """Get list of supported domains."""
        return self.domain_router.get_all_domains()

    # ========================================================================
    # CORRECTION AND LEARNING METHODS
    # ========================================================================

    def record_correction(
        self,
        request_id: str,
        user_id: str,
        correction_type: str,
        original_value: Any,
        corrected_value: Any,
        reason: str = None
    ) -> Dict[str, Any]:
        """
        Record a user correction and trigger learning.

        Args:
            request_id: Request ID from generate_workflow
            user_id: User who made the correction
            correction_type: Type ('domain', 'tool_selection', 'parameters')
            original_value: Original suggested value
            corrected_value: User's corrected value
            reason: Optional reason for correction

        Returns:
            Dict with correction and learning results
        """
        results = {
            'recorded': False,
            'learned': False,
            'actions': []
        }

        # Record in audit
        if self.audit:
            try:
                audit_id = self.audit.record_correction(
                    request_id=request_id,
                    user_id=user_id,
                    correction_type=correction_type,
                    original_value=original_value,
                    corrected_value=corrected_value,
                    reason=reason
                )
                results['recorded'] = True
                results['audit_id'] = audit_id
            except Exception as e:
                log.error(f"Failed to record correction: {e}")
                results['error'] = str(e)

        # Trigger learning
        if self.learning:
            try:
                # Get query text from audit record for keyword extraction
                query_text = None
                if self.audit:
                    audit_record = self.audit.get_audit_by_request_id(request_id)
                    if audit_record:
                        query_text = audit_record.get('query_text')

                learning_result = self.learning.learn_from_correction(
                    user_id=user_id,
                    audit_id=results.get('audit_id', 0),
                    correction_type=correction_type,
                    original_value=original_value,
                    corrected_value=corrected_value,
                    query_text=query_text
                )
                results['learned'] = learning_result.get('learned', False)
                results['actions'].extend(learning_result.get('actions', []))
            except Exception as e:
                log.error(f"Failed to learn from correction: {e}")

        log.info(f"Correction recorded: type={correction_type}, "
                f"recorded={results['recorded']}, learned={results['learned']}")

        return results

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
            request_id: Request ID from generate_workflow
            user_id: User ID
            success: Whether workflow executed successfully
            user_kept: Whether user kept/used the workflow
            rating: User rating (1-5) if provided

        Returns:
            Dict with learning results
        """
        results = {'learned': False}

        if self.learning:
            try:
                # Get audit_id from request_id
                audit_id = None
                if self.audit:
                    audit_record = self.audit.get_audit_by_request_id(request_id)
                    if audit_record:
                        audit_id = audit_record.get('audit_id')

                if audit_id:
                    learning_result = self.learning.learn_from_workflow_outcome(
                        user_id=user_id,
                        audit_id=audit_id,
                        success=success,
                        user_kept=user_kept,
                        rating=rating
                    )
                    results['learned'] = learning_result.get('learned', False)
                    results['actions'] = learning_result.get('actions', [])
            except Exception as e:
                log.error(f"Failed to learn from outcome: {e}")
                results['error'] = str(e)

        return results

    def get_audit_history(
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
        if self.audit:
            return self.audit.get_user_audit_history(user_id, limit)
        return []

    def get_audit_statistics(self, user_id: str = None) -> Dict[str, Any]:
        """
        Get audit statistics.

        Args:
            user_id: Optional user ID to filter

        Returns:
            Audit statistics
        """
        if self.audit:
            return self.audit.get_audit_statistics(user_id)
        return {}


def create_agent_orchestrator(
    tool_search=None,
    llm_client=None,
    config=None,
    enable_audit: bool = True,
    enable_learning: bool = True,
    use_enhanced_routing: bool = True
) -> AgentOrchestrator:
    """
    Factory function to create AgentOrchestrator.

    Args:
        tool_search: UnifiedToolSearch instance (auto-created if None)
        llm_client: LLM client (auto-created if None)
        config: AIConfig for component initialization
        enable_audit: Enable workflow auditing (default True)
        enable_learning: Enable learning from corrections (default True)
        use_enhanced_routing: Use LLM-enhanced routing (default True)

    Returns:
        Configured AgentOrchestrator
    """
    from ..config import AIConfig
    from ..unified_tool_search import create_unified_search
    from ..llm_client import LLMClient
    from .user_patterns_adapter import UserPatternsAdapter
    from ..services import WorkflowAuditService, WorkflowLearningService

    if config is None:
        config = AIConfig()

    if llm_client is None:
        llm_client = LLMClient(config)

    if tool_search is None:
        tool_search = create_unified_search(llm_client=llm_client)

    # Initialize optional services
    patterns_adapter = UserPatternsAdapter() if (enable_learning or use_enhanced_routing) else None
    audit_service = WorkflowAuditService() if enable_audit else None
    learning_service = None

    if enable_learning and patterns_adapter:
        learning_service = WorkflowLearningService(
            user_patterns_adapter=patterns_adapter
        )

    return AgentOrchestrator(
        tool_search=tool_search,
        llm_client=llm_client,
        user_patterns_adapter=patterns_adapter,
        audit_service=audit_service,
        learning_service=learning_service,
        use_enhanced_routing=use_enhanced_routing,
        max_parallel_specialists=3
    )
